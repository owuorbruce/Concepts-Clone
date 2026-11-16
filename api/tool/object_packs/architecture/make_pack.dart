// Writes the Architecture object pack: top-view walls, doors, windows and
// stairs as SVGs in source/, and pack.json, its object pack spec.
//
// Usage, from api/: dart run tool/object_packs/architecture/make_pack.dart
//
// Every SVG has a viewBox in inches and uses only what svgToPenElements
// converts: rect, line and path (M, L, A), with hex fills and strokes.
import 'dart:convert';
import 'dart:io';

const _stroke = '#374151';
const _wall = '#cbd5e1';
const _white = '#ffffff';
const _line = 'stroke="$_stroke" stroke-width="0.5"';

/// Wall thickness of door and window stubs, in inches.
const _stub = 4.5;

String _n(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

String _inches(num value) => '${_n(value)}″';

String _svg(num width, num depth, List<String> shapes) =>
    '<svg xmlns="http://www.w3.org/2000/svg" '
    'viewBox="0 0 ${_n(width)} ${_n(depth)}" '
    'width="${_n(width)}" height="${_n(depth)}">\n'
    '${shapes.map((e) => '  $e\n').join()}'
    '</svg>\n';

String _rect(num x, num y, num width, num height, String fill) =>
    '<rect x="${_n(x)}" y="${_n(y)}" width="${_n(width)}" '
    'height="${_n(height)}" fill="$fill" $_line/>';

String _lineShape(num x1, num y1, num x2, num y2) =>
    '<line x1="${_n(x1)}" y1="${_n(y1)}" x2="${_n(x2)}" y2="${_n(y2)}" '
    '$_line/>';

String _path(String d) => '<path d="$d" fill="none" $_line/>';

class _Object {
  const _Object(
    this.category,
    this.name,
    this.file,
    this.width,
    this.depth,
    this.svg,
  );

  final String category, name, file;
  final num width, depth;
  final String svg;
}

/// A door leaf hinged at [hingeX] that swings into the room below the
/// wall stub, with its quarter-circle swing.
List<String> _leaf(num hingeX, num width, {required bool towardRight}) {
  const leaf = 1.5;
  final bottom = _stub + width;
  final tipX = towardRight ? hingeX + width : hingeX - width;
  return [
    _rect(towardRight ? hingeX : hingeX - leaf, _stub, leaf, width, _white),
    // From the open leaf's tip back to the closed position on the wall.
    _path(
      'M ${_n(hingeX)} ${_n(bottom)} '
      'A ${_n(width)} ${_n(width)} 0 0 ${towardRight ? 0 : 1} '
      '${_n(tipX)} ${_n(_stub)}',
    ),
  ];
}

List<_Object> _objects() {
  final objects = <_Object>[];
  for (final thickness in [4.5, 6]) {
    for (final length in [24, 48, 96, 120]) {
      objects.add(
        _Object(
          'Walls',
          'Wall ${_inches(thickness)} × ${_inches(length)}',
          'wall-${_n(thickness)}x$length.svg',
          length,
          thickness,
          _svg(length, thickness, [_rect(0, 0, length, thickness, _wall)]),
        ),
      );
    }
  }
  for (final width in [24, 28, 30, 32, 36]) {
    for (final left in [true, false]) {
      final side = left ? 'left' : 'right';
      objects.add(
        _Object(
          'Doors',
          'Door ${_inches(width)} $side',
          'door-$width-$side.svg',
          width,
          _stub + width,
          _svg(width, _stub + width, [
            _rect(0, 0, width, _stub, _white),
            ..._leaf(left ? 0 : width, width, towardRight: left),
          ]),
        ),
      );
    }
  }
  const doubleWidth = 60;
  const half = doubleWidth / 2;
  objects.add(
    _Object(
      'Doors',
      'Double door ${_inches(doubleWidth)}',
      'door-double-$doubleWidth.svg',
      doubleWidth,
      _stub + half,
      _svg(doubleWidth, _stub + half, [
        _rect(0, 0, doubleWidth, _stub, _white),
        ..._leaf(0, half, towardRight: true),
        ..._leaf(doubleWidth, half, towardRight: false),
      ]),
    ),
  );
  const slidingWidth = 72;
  const panel = slidingWidth / 2 + 1;
  objects.add(
    _Object(
      'Doors',
      'Sliding door ${_inches(slidingWidth)}',
      'door-sliding-$slidingWidth.svg',
      slidingWidth,
      _stub,
      _svg(slidingWidth, _stub, [
        _rect(0, 0, slidingWidth, _stub, _white),
        _rect(0, 1, panel, 1.25, _white),
        _rect(slidingWidth - panel, 2.25, panel, 1.25, _white),
      ]),
    ),
  );
  for (final width in [24, 36, 48, 60, 72]) {
    objects.add(
      _Object(
        'Windows',
        'Window ${_inches(width)}',
        'window-$width.svg',
        width,
        _stub,
        _svg(width, _stub, [
          _rect(0, 0, width, _stub, _wall),
          _rect(1, 1, width - 2, _stub - 2, _white),
          _lineShape(1, _stub / 2, width - 1, _stub / 2),
        ]),
      ),
    );
  }
  const stairWidth = 36, stairLength = 120, tread = 10;
  objects.add(
    _Object(
      'Stairs',
      'Straight stairs ${_inches(stairWidth)} × ${_inches(stairLength)}',
      'stairs-straight-${stairWidth}x$stairLength.svg',
      stairWidth,
      stairLength,
      _svg(stairWidth, stairLength, [
        _rect(0, 0, stairWidth, stairLength, _white),
        for (var y = tread; y < stairLength; y += tread)
          _lineShape(0, y, stairWidth, y),
        // The arrow points up the run.
        _path('M 18 ${stairLength - 6} L 18 6 M 13 14 L 18 6 L 23 14'),
      ]),
    ),
  );
  return objects;
}

/// The floor plan tags of [object]: walls are valid walls when placed, doors
/// and windows open a wall they are placed on.
Map<String, Object>? _extra(_Object object) => switch (object.category) {
  'Walls' => {
    'amaze.wall': {'thicknessIn': object.depth},
  },
  'Doors' => {
    'amaze.opening': {'kind': 'door', 'widthIn': object.width},
  },
  'Windows' => {
    'amaze.opening': {'kind': 'window', 'widthIn': object.width},
  },
  _ => null,
};

void main() {
  final directory = File.fromUri(Platform.script).parent;
  final source = Directory('${directory.path}/source')
    ..createSync(recursive: true);
  for (final file in source.listSync().whereType<File>()) {
    if (file.path.endsWith('.svg')) file.deleteSync();
  }
  final objects = _objects();
  for (final object in objects) {
    File('${source.path}/${object.file}').writeAsStringSync(object.svg);
  }
  final spec = {
    'id': 'architecture',
    'name': 'Architecture',
    'description': 'Top-view walls, doors, windows and stairs at real size.',
    'author': 'aMaze',
    'license': 'CC0-1.0',
    'licenseUrl': 'https://creativecommons.org/publicdomain/zero/1.0/',
    'sourceUrl': '',
    'version': '1.0.0',
    'sizing': 'inches',
    'objects': [
      for (final object in objects)
        {
          'name': object.name,
          'category': object.category,
          'file': 'source/${object.file}',
          'widthIn': object.width,
          'depthIn': object.depth,
          'extra': ?_extra(object),
        },
    ],
  };
  File(
    '${directory.path}/pack.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(spec)}\n');
  stdout.writeln('Wrote ${objects.length} objects to ${source.path}.');
}
