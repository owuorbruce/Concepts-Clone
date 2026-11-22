import 'dart:io';
import 'dart:math';

import 'package:butterfly_api/butterfly_api.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:test/test.dart';

String _svg(String viewBox, String body) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$viewBox">$body</svg>';

List<Point<double>> _points(PenElement element) =>
    element.points.map((p) => Point(p.x, p.y)).toList();

bool _closed(PenElement element) {
  final points = _points(element);
  return points.length > 2 && points.first == points.last;
}

double _maxSpacing(PenElement element) {
  final points = _points(element);
  var result = 0.0;
  for (var i = 1; i < points.length; i++) {
    result = max(result, (points[i] - points[i - 1]).magnitude);
  }
  return result;
}

SRGBColor _color(ElementPaint paint) => (paint as SolidElementPaint).color;

Matcher _near(Point<double> expected, [double tolerance = 0.01]) =>
    predicate<Point<double>>(
      (p) => (p - expected).magnitude <= tolerance,
      'within $tolerance of $expected',
    );

List<File> _sources(String pack) =>
    Directory('tool/object_packs/$pack/source')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.svg'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

void main() {
  test('a rect becomes one closed outline through its corners', () {
    final result = svgToPenElements(
      _svg('0 0 10 5', '<rect x="0" y="0" width="10" height="5"/>'),
      const Rectangle(0, 0, 100, 50),
    )!;
    expect(result, hasLength(1));
    final element = result.single;
    expect(_closed(element), isTrue);
    final points = _points(element);
    for (final corner in const [
      Point(0.0, 0.0),
      Point(100.0, 0.0),
      Point(100.0, 50.0),
      Point(0.0, 50.0),
    ]) {
      expect(points, contains(_near(corner)));
    }
    expect(_maxSpacing(element), lessThanOrEqualTo(kSvgStrokeMaxSpacing));
    expect(element.points.every((p) => p.pressure == 1), isTrue);
    expect(element.property.thinning, 0);
    expect(element.property.smoothing, 0);
    expect(element.property.streamline, 0);
  });

  test('rx rounds the corners inside the box', () {
    final result = svgToPenElements(
      _svg('0 0 10 5', '<rect width="10" height="5" rx="2"/>'),
      const Rectangle(0, 0, 100, 50),
    )!;
    final points = _points(result.single);
    for (final corner in const [
      Point(0.0, 0.0),
      Point(100.0, 0.0),
      Point(100.0, 50.0),
      Point(0.0, 50.0),
    ]) {
      expect(points, isNot(contains(_near(corner, 1e-6))));
    }
    for (final p in points) {
      expect(p.x, inInclusiveRange(-1e-9, 100 + 1e-9));
      expect(p.y, inInclusiveRange(-1e-9, 50 + 1e-9));
    }
  });

  test('a circle keeps its radius when scaled', () {
    final result = svgToPenElements(
      _svg('0 0 20 20', '<circle cx="10" cy="10" r="10"/>'),
      const Rectangle(0, 0, 40, 40),
    )!;
    expect(_closed(result.single), isTrue);
    for (final p in _points(result.single)) {
      expect(p.distanceTo(const Point(20, 20)), closeTo(20, 0.1));
    }
  });

  test('a dashed line becomes one element per dash', () {
    final result = svgToPenElements(
      _svg(
        '0 0 10 1',
        '<line x1="0" y1="0.5" x2="10" y2="0.5" stroke="#000" '
            'stroke-dasharray="2 2"/>',
      ),
      const Rectangle(0, 0, 10, 1),
    )!;
    expect(result.length, inInclusiveRange(2, 4));
    expect(result, hasLength(3));
    for (final dash in result) {
      expect(_color(dash.property.fillPaint).a, 0);
      final points = _points(dash);
      expect((points.last - points.first).magnitude, closeTo(2, 1e-9));
    }
  });

  test('a dashed filled shape puts the fill before the dashes', () {
    final result = svgToPenElements(
      _svg(
        '0 0 10 10',
        '<rect width="10" height="10" fill="#cbd5e1" stroke="#374151" '
            'stroke-dasharray="1"/>',
      ),
      const Rectangle(0, 0, 10, 10),
    )!;
    expect(
      _color(result.first.property.fillPaint),
      const SRGBColor(0xFFCBD5E1),
    );
    expect(_color(result.first.property.paint).a, 0);
    expect(result.length, greaterThan(10));
    for (final dash in result.skip(1)) {
      expect(_color(dash.property.fillPaint).a, 0);
      expect(_color(dash.property.paint), const SRGBColor(0xFF374151));
    }
  });

  test('paths with M, L, C, Q, A and Z give closed and open outlines', () {
    final result = svgToPenElements(
      _svg(
        '0 0 40 10',
        '<path stroke="#000" fill="none" d="M0 0 L10 0 C12 0 12 5 10 5 '
            'Q5 8 0 5 A2 2 0 0 1 0 1 Z m20 0 l10 0 h5 v3"/>',
      ),
      const Rectangle(0, 0, 40, 10),
    )!;
    expect(result, hasLength(2));
    expect(_closed(result[0]), isTrue);
    expect(_closed(result[1]), isFalse);
    expect(_points(result[1]).last, _near(const Point(35, 3)));
    expect(_maxSpacing(result[0]), lessThanOrEqualTo(kSvgStrokeMaxSpacing));
  });

  test('fill defaults to black, none is transparent, hex is kept', () {
    PenElement only(String attributes) => svgToPenElements(
      _svg('0 0 1 1', '<rect width="1" height="1" stroke="#000" $attributes/>'),
      const Rectangle(0, 0, 1, 1),
    )!.single;
    expect(_color(only('fill="none"').property.fillPaint).a, 0);
    expect(
      _color(only('fill="#cbd5e1"').property.fillPaint),
      const SRGBColor(0xFFCBD5E1),
    );
    expect(
      _color(only('fill="#fff"').property.fillPaint),
      const SRGBColor(0xFFFFFFFF),
    );
    expect(_color(only('').property.fillPaint), const SRGBColor(0xFF000000));
    expect(
      _color(only('fill="#ffffff" fill-opacity="0.5"').property.fillPaint).a,
      128,
    );
  });

  test('stroke-width is scaled with the drawing', () {
    final result = svgToPenElements(
      _svg(
        '0 0 1 1',
        '<line x1="0" y1="0" x2="1" y2="1" stroke="#374151" '
            'stroke-width="1.2"/>',
      ),
      const Rectangle(0, 0, 96, 96),
    )!;
    expect(result.single.property.strokeWidth, closeTo(115.2, 1e-9));
  });

  test('shapes with neither stroke nor fill are skipped', () {
    final result = svgToPenElements(
      _svg('0 0 1 1', '<line x1="0" y1="0" x2="1" y2="1"/>'),
      const Rectangle(0, 0, 1, 1),
    );
    expect(result, isEmpty);
  });

  test('unsupported features give null', () {
    const target = Rectangle<double>(0, 0, 10, 10);
    for (final body in [
      '<rect width="1" height="1" transform="rotate(45)"/>',
      '<g><rect width="1" height="1"/></g>',
      '<rect width="1" height="1" style="fill:red"/>',
      '<style>rect{fill:red}</style><rect width="1" height="1"/>',
      '<defs><linearGradient id="g"/></defs><rect width="1" height="1"/>',
      '<rect width="1" height="1" fill="url(#g)"/>',
      '<rect width="1" height="1" fill="red"/>',
      '<use href="#a"/>',
      '<image href="data:image/png;base64,AA==" width="1" height="1"/>',
      '<text>Hi</text>',
      '<path d="M0 0 L x"/>',
    ]) {
      expect(
        svgToPenElements(_svg('0 0 10 10', body), target),
        isNull,
        reason: body,
      );
    }
  });

  test('every furniture SVG converts; the sofa gives 6 elements', () {
    final files = _sources('furniture');
    expect(files, hasLength(98));
    for (final file in files) {
      final result = svgToPenElements(
        file.readAsStringSync(),
        const Rectangle(0, 0, 960, 960),
      );
      expect(result, isNotNull, reason: file.path);
      expect(result, isNotEmpty, reason: file.path);
    }
    final sofa = svgToPenElements(
      File('tool/object_packs/furniture/source/sofa.svg').readAsStringSync(),
      const Rectangle(-4032, -1728, 8064, 3456),
    )!;
    expect(sofa, hasLength(6));
  });

  test('every architecture SVG converts', () {
    final files = _sources('architecture');
    expect(files, hasLength(26));
    for (final file in files) {
      final result = svgToPenElements(
        file.readAsStringSync(),
        const Rectangle(0, 0, 960, 960),
      );
      expect(result, isNotNull, reason: file.path);
      expect(result, isNotEmpty, reason: file.path);
    }
  });

  test('a door swing is a quarter circle around its hinge', () {
    // door-30-left: 30 × 34.5 in, hinged at (0, 4.5), drawn at 1 unit/in.
    final result = svgToPenElements(
      File('tool/object_packs/architecture/source/door-30-left.svg')
          .readAsStringSync(),
      const Rectangle(0, 0, 30, 34.5),
    )!;
    expect(result, hasLength(3));
    final swing = _points(result.last);
    expect(_closed(result.last), isFalse);
    for (final p in swing) {
      expect(p.distanceTo(const Point(0, 4.5)), closeTo(30, 0.1));
      expect(p.x, greaterThanOrEqualTo(-1e-9));
      expect(p.y, greaterThanOrEqualTo(4.5 - 1e-9));
    }
  });
}
