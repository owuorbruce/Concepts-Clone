import 'dart:convert';
import 'dart:io';
import 'dart:math' show Point;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:xml/xml.dart';

/// Canvas units per inch, see `kCanvasUnitsPerInch`.
const kObjectPackUnitsPerInch = 96.0;

/// The largest SVG an object pack accepts.
const kMaxObjectSvgBytes = 1024 * 1024;

/// How far an SVG's viewBox may differ from the spec's size before a
/// warning, in inches.
const kViewBoxTolerance = 0.5;

/// Separator between category and name in a component name.
const kObjectCategorySeparator = ' — ';

/// A spec or SVG that cannot be built into a pack.
class ObjectPackBuildException implements Exception {
  const ObjectPackBuildException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A built object pack.
class BuildResult {
  BuildResult(this.pack, this.warnings);

  final NoteData pack;
  final List<String> warnings;

  int get objectCount => pack.getComponents().length;

  Uint8List get bytes => pack.exportAsBytes();
}

enum _Sizing { inches, longestSide }

/// Builds the object pack described by the JSON [spec].
///
/// Throws an [ObjectPackBuildException] naming the file if the spec or one
/// of its SVGs is invalid.
Future<BuildResult> buildObjectPack(File spec) async {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(await spec.readAsString()) as Map<String, dynamic>;
  } on Object catch (e) {
    throw ObjectPackBuildException('${spec.path}: cannot read the spec: $e');
  }
  String text(String key, {bool required = true}) {
    final value = json[key];
    if (value is String && (value.isNotEmpty || !required)) return value;
    if (value == null && !required) return '';
    throw ObjectPackBuildException('${spec.path}: "$key" must be a string');
  }

  final id = text('id');
  final name = text('name');
  final description = text('description', required: false);
  final author = text('author');
  final license = text('license');
  final licenseUrl = text('licenseUrl', required: false);
  final sourceUrl = text('sourceUrl', required: false);
  final version = text('version');
  final sizing = switch (json['sizing']) {
    'inches' => _Sizing.inches,
    'longestSide' => _Sizing.longestSide,
    final other => throw ObjectPackBuildException(
      '${spec.path}: unknown sizing "$other"',
    ),
  };
  final longestSideIn = (json['longestSideIn'] as num?)?.toDouble();
  if (sizing == _Sizing.longestSide &&
      (longestSideIn == null || longestSideIn <= 0)) {
    throw ObjectPackBuildException(
      '${spec.path}: longestSide sizing needs a positive "longestSideIn"',
    );
  }
  final objects = json['objects'];
  if (objects is! List) {
    throw ObjectPackBuildException('${spec.path}: "objects" must be a list');
  }

  final warnings = <String>[];
  final source = {
    'pack': id,
    'author': author,
    'license': license,
    'licenseUrl': licenseUrl,
    'url': sourceUrl,
  };
  var pack = NoteData(Archive()).setMetadata(
    FileMetadata(
      type: NoteFileType.pack,
      fileVersion: kFileVersion,
      name: name,
      description: description,
      author: '$author · $license',
      version: version,
    ),
  );
  final names = <String>{};
  for (final (index, object) in objects.indexed) {
    if (object is! Map<String, dynamic>) {
      throw ObjectPackBuildException(
        '${spec.path}: object $index must be an object',
      );
    }
    final objectName = object['name'];
    final file = object['file'];
    if (objectName is! String || objectName.isEmpty || file is! String) {
      throw ObjectPackBuildException(
        '${spec.path}: object $index needs a "name" and a "file"',
      );
    }
    final category = object['category'] as String?;
    final componentName = category == null || category.isEmpty
        ? objectName
        : '$category$kObjectCategorySeparator$objectName';
    if (!names.add(componentName)) {
      throw ObjectPackBuildException(
        '${spec.path}: duplicate object name "$componentName"',
      );
    }

    final svgFile = File.fromUri(spec.absolute.parent.uri.resolve(file));
    final bytes = await _readSvg(svgFile, file);
    final document = _parseSvg(bytes, file);
    final viewBox = _viewBox(document.rootElement);

    final double width, height;
    final furnishing = <String, dynamic>{
      ...?(object['furnishing'] as Map<String, dynamic>?),
    };
    switch (sizing) {
      case _Sizing.inches:
        final widthIn = (object['widthIn'] as num?)?.toDouble();
        final depthIn = (object['depthIn'] as num?)?.toDouble();
        if (widthIn == null ||
            depthIn == null ||
            widthIn <= 0 ||
            depthIn <= 0) {
          throw ObjectPackBuildException(
            '$file: inches sizing needs positive "widthIn" and "depthIn"',
          );
        }
        if (viewBox == null) {
          warnings.add('$file: no viewBox, using the spec size');
        } else if ((viewBox.$1 - widthIn).abs() > kViewBoxTolerance ||
            (viewBox.$2 - depthIn).abs() > kViewBoxTolerance) {
          warnings.add(
            '$file: viewBox ${_format(viewBox.$1)} × ${_format(viewBox.$2)} '
            'differs from ${_format(widthIn)} × ${_format(depthIn)} in, '
            'using the spec size',
          );
        }
        width = widthIn * kObjectPackUnitsPerInch;
        height = depthIn * kObjectPackUnitsPerInch;
        if (furnishing.isNotEmpty) {
          furnishing['widthIn'] = object['widthIn'];
          furnishing['depthIn'] = object['depthIn'];
        }
      case _Sizing.longestSide:
        final size = viewBox ?? _sizeAttributes(document.rootElement);
        if (size == null || size.$1 <= 0 || size.$2 <= 0) {
          throw ObjectPackBuildException(
            '$file: longestSide sizing needs a viewBox or width and height',
          );
        }
        final longest = longestSideIn! * kObjectPackUnitsPerInch;
        final scale = longest / (size.$1 > size.$2 ? size.$1 : size.$2);
        width = size.$1 * scale;
        height = size.$2 * scale;
    }

    final element = SvgElement(
      source: Uri.dataFromBytes(bytes, mimeType: 'image/svg+xml').toString(),
      width: width,
      height: height,
      position: Point(-width / 2, -height / 2),
      extra: {
        'source': source,
        if (furnishing.isNotEmpty) 'furnishing': furnishing,
      },
    );
    pack = pack.setComponent(
      componentName,
      ButterflyComponent(elements: [element]),
    );
  }
  return BuildResult(pack, warnings);
}

Future<Uint8List> _readSvg(File file, String name) async {
  if (!await file.exists()) {
    throw ObjectPackBuildException('$name: file not found');
  }
  final length = await file.length();
  if (length > kMaxObjectSvgBytes) {
    throw ObjectPackBuildException(
      '$name: $length bytes, the limit is $kMaxObjectSvgBytes',
    );
  }
  return file.readAsBytes();
}

XmlDocument _parseSvg(Uint8List bytes, String name) {
  final String content;
  try {
    content = utf8.decode(bytes);
  } on FormatException {
    throw ObjectPackBuildException('$name: not UTF-8 text');
  }
  final lower = content.toLowerCase();
  if (lower.contains('<script')) {
    throw ObjectPackBuildException('$name: contains <script>');
  }
  if (lower.contains('<foreignobject')) {
    throw ObjectPackBuildException('$name: contains <foreignObject>');
  }
  final XmlDocument document;
  try {
    document = XmlDocument.parse(content);
  } on XmlException catch (e) {
    throw ObjectPackBuildException('$name: not well-formed XML: $e');
  }
  if (document.rootElement.name.local != 'svg') {
    throw ObjectPackBuildException('$name: the root element is not <svg>');
  }
  for (final element in document.descendantElements) {
    for (final attribute in element.attributes) {
      if (attribute.name.local != 'href') continue;
      final value = attribute.value.trim();
      if (value.startsWith('#') || value.startsWith('data:image/')) continue;
      throw ObjectPackBuildException(
        '$name: <${element.name.qualified}> links to "$value"',
      );
    }
  }
  return document;
}

(double, double)? _viewBox(XmlElement svg) {
  final value = svg.getAttribute('viewBox');
  if (value == null) return null;
  final parts = value
      .trim()
      .split(RegExp(r'[\s,]+'))
      .map(double.tryParse)
      .toList();
  if (parts.length != 4 || parts.any((e) => e == null)) return null;
  return (parts[2]!, parts[3]!);
}

(double, double)? _sizeAttributes(XmlElement svg) {
  double? parse(String? value) =>
      value == null ? null : double.tryParse(value.replaceAll('px', ''));
  final width = parse(svg.getAttribute('width'));
  final height = parse(svg.getAttribute('height'));
  if (width == null || height == null) return null;
  return (width, height);
}

String _format(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';
