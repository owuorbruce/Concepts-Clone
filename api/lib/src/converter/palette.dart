import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dart_leap/dart_leap.dart';

import '../models/pack.dart';

/// File extensions accepted by [importPaletteFile].
const kPaletteFileExtensions = ['gpl', 'ase', 'aco', 'swatches', 'hex', 'txt'];

typedef _RawPalette = (String name, List<SRGBColor> colors);

final _invalidNameCharacters = RegExp(r'[/\\:*?"<>|]');

/// Reads a palette file into one or more named color palettes.
///
/// Supported formats, chosen by [fileExtension]:
/// * `gpl`: GIMP, Krita and Inkscape palettes, including RGBA palettes
/// * `ase`: Adobe Swatch Exchange; every group becomes its own palette
/// * `aco`: Photoshop color swatches (version 1 and 2)
/// * `swatches`: Procreate swatches
/// * `hex`: one `RRGGBB` or `RRGGBBAA` color per line (e.g. Lospec)
/// * `txt`: Paint.NET palettes (`AARRGGBB`, `;` comments)
///
/// Palettes without a name of their own are called [name]. Color names are
/// not kept because [ColorPalette] has no field for them.
///
/// Throws a [FormatException] if the file can't be read or has no colors.
List<NamedItem<ColorPalette>> importPaletteFile(
  Uint8List data, {
  required String fileExtension,
  required String name,
}) {
  final List<_RawPalette> raw;
  try {
    raw = _readPalettes(data, fileExtension.toLowerCase(), name);
  } on RangeError {
    throw const FormatException('Palette file is truncated or corrupt');
  }
  final result = <NamedItem<ColorPalette>>[];
  for (final (paletteName, colors) in raw) {
    if (colors.isEmpty) continue;
    var itemName = paletteName.replaceAll(_invalidNameCharacters, '-').trim();
    if (itemName.isEmpty) itemName = name;
    final palette = ColorPalette(colors: colors);
    result.add(NamedItem(name: itemName, item: palette));
  }
  if (result.isEmpty) {
    throw const FormatException('Palette file contains no colors');
  }
  return result;
}

List<_RawPalette> _readPalettes(
  Uint8List data,
  String extension,
  String name,
) {
  switch (extension) {
    case 'gpl':
      return _readGpl(_decodeText(data), name);
    case 'ase':
      return _readAse(data, name);
    case 'aco':
      return [(name, _readAco(data))];
    case 'swatches':
      return _readProcreate(data, name);
    case 'hex':
      return [(name, _readHexList(_decodeText(data), alphaFirst: false))];
    case 'txt':
      return [(name, _readHexList(_decodeText(data), alphaFirst: true))];
  }
  throw FormatException('Unsupported palette format: .$extension');
}

String _decodeText(Uint8List data) {
  final text = utf8.decode(data, allowMalformed: true);
  return text.startsWith('﻿') ? text.substring(1) : text;
}

List<_RawPalette> _readGpl(String text, String name) {
  final lines = const LineSplitter().convert(text);
  if (lines.isEmpty || !lines.first.trim().startsWith('GIMP Palette')) {
    throw const FormatException('Not a GIMP palette');
  }
  var paletteName = name;
  var channels = 3;
  final colors = <SRGBColor>[];
  for (final line in lines.skip(1)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (trimmed.startsWith('Name:')) {
      paletteName = trimmed.substring(5).trim();
      continue;
    }
    if (trimmed.startsWith('Channels:')) {
      final isRgba = trimmed.substring(9).trim().toUpperCase() == 'RGBA';
      channels = isRgba ? 4 : 3;
      continue;
    }
    final values = <int>[];
    for (final part in trimmed.split(RegExp(r'\s+')).take(channels)) {
      final value = int.tryParse(part);
      if (value == null) break;
      values.add(value);
    }
    if (values.length != channels) continue;
    final alpha = channels == 4 ? values[3] : 255;
    colors.add(_argb(alpha, values[0], values[1], values[2]));
  }
  return [(paletteName, colors)];
}

final _hexPattern = RegExp(r'\b([0-9a-fA-F]{8}|[0-9a-fA-F]{6})\b');

List<SRGBColor> _readHexList(String text, {required bool alphaFirst}) {
  final colors = <SRGBColor>[];
  for (final line in const LineSplitter().convert(text)) {
    final content = line.split(';').first;
    for (final match in _hexPattern.allMatches(content)) {
      colors.add(_parseHex(match.group(1)!, alphaFirst: alphaFirst));
    }
  }
  return colors;
}

SRGBColor _parseHex(String hex, {required bool alphaFirst}) {
  final value = int.parse(hex, radix: 16);
  if (hex.length == 6) return SRGBColor(0xFF000000 + value);
  if (alphaFirst) return SRGBColor(value);
  final alpha = value % 0x100;
  return SRGBColor(alpha * 0x1000000 + value ~/ 0x100);
}

List<_RawPalette> _readAse(Uint8List data, String name) {
  final reader = _ByteReader(data);
  if (reader.ascii(4) != 'ASEF') {
    throw const FormatException('Not an Adobe Swatch Exchange file');
  }
  reader.skip(4);
  final blockCount = reader.uint32();
  final ungrouped = <SRGBColor>[];
  final palettes = <_RawPalette>[(name, ungrouped)];
  List<SRGBColor>? group;
  for (var i = 0; i < blockCount && !reader.isDone; i++) {
    final type = reader.uint16();
    final block = reader.sub(reader.uint32());
    switch (type) {
      case 0xC001:
        final groupName = block.isDone ? '' : block.utf16(block.uint16());
        group = [];
        palettes.add((groupName, group));
      case 0xC002:
        group = null;
      case 0x0001:
        block.utf16(block.uint16());
        final color = _readAseColor(block);
        if (color != null) (group ?? ungrouped).add(color);
    }
  }
  return palettes;
}

SRGBColor? _readAseColor(_ByteReader block) {
  switch (block.ascii(4)) {
    case 'RGB ':
      return _rgbFloat(block.float32(), block.float32(), block.float32());
    case 'CMYK':
      final [c, m, y, k] = [for (var i = 0; i < 4; i++) block.float32()];
      return _cmyk(c, m, y, k);
    case 'LAB ':
      final [l, a, b] = [for (var i = 0; i < 3; i++) block.float32()];
      return _lab(l <= 1 ? l * 100 : l, a, b);
    case 'Gray':
      final value = block.float32();
      return _rgbFloat(value, value, value);
  }
  return null;
}

List<SRGBColor> _readAco(Uint8List data) {
  final reader = _ByteReader(data);
  var colors = <SRGBColor>[];
  // Version 1 comes first; an optional version 2 section repeats the colors
  // with names and takes precedence.
  while (!reader.isDone) {
    final version = reader.uint16();
    if (version != 1 && version != 2) {
      throw const FormatException('Not a Photoshop swatch file');
    }
    final count = reader.uint16();
    final section = <SRGBColor>[];
    for (var i = 0; i < count; i++) {
      final color = _readAcoColor(reader);
      if (version == 2) reader.utf16(reader.uint32());
      if (color != null) section.add(color);
    }
    colors = section;
  }
  return colors;
}

SRGBColor? _readAcoColor(_ByteReader reader) {
  final space = reader.uint16();
  final [w, x, y, z] = [for (var i = 0; i < 4; i++) reader.uint16()];
  switch (space) {
    case 0: // RGB
      return _rgbFloat(w / 65535, x / 65535, y / 65535);
    case 1: // HSB
      return _hsv(w / 65535 * 360, x / 65535, y / 65535);
    case 2: // CMYK, 0 means full ink
      return _cmyk(1 - w / 65535, 1 - x / 65535, 1 - y / 65535, 1 - z / 65535);
    case 7: // Lab
      return _lab(w / 100, x.toSigned(16) / 100, y.toSigned(16) / 100);
    case 8: // Grayscale as ink, 0 is white
      final value = 1 - w / 10000;
      return _rgbFloat(value, value, value);
  }
  return null;
}

List<_RawPalette> _readProcreate(Uint8List data, String name) {
  final json = _decodeProcreateJson(data);
  final entries = json is List ? json : [json];
  final palettes = <_RawPalette>[];
  for (final entry in entries) {
    if (entry is! Map) continue;
    final swatches = entry['swatches'];
    if (swatches is! List) continue;
    final colors = <SRGBColor>[];
    for (final swatch in swatches) {
      if (swatch is! Map) continue;
      final color = _procreateColor(swatch);
      if (color != null) colors.add(color);
    }
    final paletteName = entry['name'];
    palettes.add((paletteName is String ? paletteName : name, colors));
  }
  return palettes;
}

Object? _decodeProcreateJson(Uint8List data) {
  try {
    final archive = ZipDecoder().decodeBytes(data);
    final bytes = archive.findFile('Swatches.json')?.readBytes();
    if (bytes == null) {
      throw const FormatException('Procreate swatches without Swatches.json');
    }
    return jsonDecode(utf8.decode(bytes));
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Not a Procreate swatches file');
  }
}

SRGBColor? _procreateColor(Map<dynamic, dynamic> swatch) {
  final hue = swatch['hue'];
  final saturation = swatch['saturation'];
  final brightness = swatch['brightness'];
  if (hue is! num || saturation is! num || brightness is! num) return null;
  final alpha = swatch['alpha'];
  final opacity = alpha is num ? alpha.toDouble() : 1.0;
  final degrees = hue.toDouble() * 360;
  final s = saturation.toDouble();
  return _hsv(degrees, s, brightness.toDouble(), opacity);
}

int _byte(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);

int _unit(double value) {
  if (value.isNaN) return 0;
  return (value.clamp(0.0, 1.0) * 255).round();
}

SRGBColor _argb(int a, int r, int g, int b) {
  final rgb = _byte(r) * 0x10000 + _byte(g) * 0x100 + _byte(b);
  return SRGBColor(_byte(a) * 0x1000000 + rgb);
}

SRGBColor _rgbFloat(double r, double g, double b, [double a = 1]) {
  return _argb(_unit(a), _unit(r), _unit(g), _unit(b));
}

SRGBColor _cmyk(double c, double m, double y, double k) {
  final white = 1 - k;
  return _rgbFloat((1 - c) * white, (1 - m) * white, (1 - y) * white);
}

SRGBColor _hsv(double h, double s, double v, [double alpha = 1]) {
  final hue = h.isFinite ? (h % 360) / 60 : 0.0;
  final c = v * s;
  final x = c * (1 - (hue % 2 - 1).abs());
  final m = v - c;
  final (r, g, b) = switch (hue.floor()) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  return _rgbFloat(r + m, g + m, b + m, alpha);
}

/// Converts CIE Lab (D50, as used by Adobe) to sRGB.
SRGBColor _lab(double l, double a, double b) {
  final fy = (l + 16) / 116;
  final x = 0.96422 * _labInverse(fy + a / 500);
  final y = _labInverse(fy);
  final z = 0.82521 * _labInverse(fy - b / 200);
  final red = 3.1338561 * x - 1.6168667 * y - 0.4906146 * z;
  final green = -0.9787684 * x + 1.9161415 * y + 0.0334540 * z;
  final blue = 0.0719453 * x - 0.2289914 * y + 1.4052427 * z;
  return _rgbFloat(_gamma(red), _gamma(green), _gamma(blue));
}

double _labInverse(double t) {
  const delta = 6 / 29;
  return t > delta ? t * t * t : 3 * delta * delta * (t - 4 / 29);
}

double _gamma(double linear) {
  if (linear <= 0.0031308) return 12.92 * linear;
  return 1.055 * pow(linear, 1 / 2.4).toDouble() - 0.055;
}

class _ByteReader {
  final ByteData _data;
  int _offset = 0;

  _ByteReader(Uint8List bytes) : _data = ByteData.sublistView(bytes);

  bool get isDone => _offset >= _data.lengthInBytes;

  int _advance(int count) {
    final start = _offset;
    if (count < 0 || start + count > _data.lengthInBytes) {
      throw RangeError('Unexpected end of palette data');
    }
    _offset += count;
    return start;
  }

  void skip(int count) => _advance(count);

  int uint16() => _data.getUint16(_advance(2));

  int uint32() => _data.getUint32(_advance(4));

  double float32() => _data.getFloat32(_advance(4));

  String ascii(int length) {
    final start = _advance(length);
    final bytes = Uint8List.sublistView(_data, start, start + length);
    return String.fromCharCodes(bytes);
  }

  _ByteReader sub(int length) {
    final start = _advance(length);
    return _ByteReader(Uint8List.sublistView(_data, start, start + length));
  }

  String utf16(int length) {
    final units = <int>[];
    for (var i = 0; i < length; i++) {
      units.add(uint16());
    }
    if (units.isNotEmpty && units.last == 0) units.removeLast();
    return String.fromCharCodes(units);
  }
}
