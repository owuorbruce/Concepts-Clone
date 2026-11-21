import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:butterfly/brushes/brush_registry.dart';
import 'package:butterfly/brushes/outline_engine.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly/services/asset.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';

BrushDefinition asset(String id) => BrushDefinition.fromJson(
  jsonDecode(File('assets/brushes/$id.v1.json').readAsStringSync())
      as Map<String, dynamic>,
);

List<PathPoint> line(
  Offset from,
  Offset to, {
  int count = 101,
  double pressure = 1,
  int? durationMs,
}) => [
  for (var i = 0; i < count; i++)
    PathPoint(
      from.dx + (to.dx - from.dx) * i / (count - 1),
      from.dy + (to.dy - from.dy) * i / (count - 1),
      pressure,
      null,
      null,
      durationMs == null ? null : (durationMs * i / (count - 1)).round(),
    ),
];

StrokeGeometry geometry(
  List<PathPoint> points,
  BrushDefinition def, {
  double width = 10,
  double zoom = 1,
}) => StrokeGeometry.build(points, def, width, zoom: zoom, origin: Offset.zero);

double midWidth(StrokeGeometry g) => g.width[g.length ~/ 2];

/// Records the paths and paints drawn; ignores every other call.
class _RecordingCanvas implements Canvas {
  final paths = <(Path, Paint)>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add((path, paint));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<PenRenderer> setUpPen(PenElement element) async {
  final renderer = PenRenderer(element);
  final transform = TransformCubit(1);
  await renderer.setup(
    transform,
    NoteData(Archive()),
    AssetService(),
    const DocumentPage(),
  );
  await transform.close();
  return renderer;
}

_RecordingCanvas drawLocal(PenRenderer renderer) {
  final canvas = _RecordingCanvas();
  renderer.localOrigin;
  renderer.buildLocal(canvas);
  return canvas;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    for (final id in [
      'amaze.pen',
      'amaze.fountain',
      'amaze.dynamic',
      'amaze.fixed',
      'amaze.wire',
      'amaze.dotted',
    ]) {
      registerBrush(asset(id));
    }
  });

  final strokePoints = [
    for (var i = 0; i <= 60; i++)
      PathPoint(1e5 + i * 4.0, -2e4 + (i % 7) * 3.0, 0.3 + (i % 5) * 0.15),
  ];

  test('11: classic pens and unknown brushes keep the classic path', () async {
    final classic = await setUpPen(PenElement(id: 'a', points: strokePoints));
    final unknown = await setUpPen(
      PenElement(
        id: 'a',
        points: strokePoints,
        property: const PenProperty(brush: 'amaze.doesNotExist'),
      ),
    );
    expect(classic.brushDefinition, isNull);
    expect(unknown.brushDefinition, isNull);
    // The classic bounds: each point inflated by width + pressure × thinning.
    var expected = Rect.zero;
    for (final (i, p) in strokePoints.indexed) {
      final w = 5 + p.pressure * 0.4;
      final r = Rect.fromLTRB(p.x - w, p.y - w, p.x + w, p.y + w);
      expected = i == 0 ? r : expected.expandToInclude(r);
    }
    expect(classic.expandedRect, expected);
    expect(unknown.expandedRect, classic.expandedRect);
    final classicPaths = drawLocal(classic).paths;
    final unknownPaths = drawLocal(unknown).paths;
    expect(classicPaths, hasLength(1));
    expect(
      unknownPaths.single.$1.getBounds(),
      classicPaths.single.$1.getBounds(),
    );
    expect(classicPaths.single.$2.style, PaintingStyle.fill);

    // A brush stroke uses its outline's bounds instead.
    final pen = await setUpPen(
      PenElement(
        id: 'a',
        points: strokePoints,
        property: const PenProperty(brush: 'amaze.pen'),
      ),
    );
    expect(pen.brushDefinition?.id, 'amaze.pen');
    final outline = drawLocal(pen).paths.single.$1.getBounds();
    expect(pen.expandedRect, outline.shift(pen.localOrigin));
  });

  test('12: wire draws a zero-width stroke', () async {
    final wire = await setUpPen(
      PenElement(
        id: 'w',
        zoom: 2,
        points: strokePoints,
        property: const PenProperty(brush: 'amaze.wire', strokeWidth: 1),
      ),
    );
    final paint = drawLocal(wire).paths.single.$2;
    expect(paint.style, PaintingStyle.stroke);
    expect(paint.strokeWidth, 0);
    expect(wire.expandedRect, wire.rect.inflate(1));
  });

  test('4: fixed width ignores pressure', () {
    final def = asset('amaze.fixed');
    Rect bounds(double pressure) => buildOutline(
      line(Offset.zero, const Offset(500, 0), pressure: pressure),
      def,
      10,
      zoom: 1,
      origin: Offset.zero,
    ).getBounds();
    final light = bounds(0.3).height;
    final heavy = bounds(1).height;
    expect(light, closeTo(10, 0.1));
    expect(light, closeTo(heavy, heavy * 0.01));
  });

  test('5: pen follows pressure and tapers its ends', () {
    final def = asset('amaze.pen');
    final light = geometry(
      line(Offset.zero, const Offset(500, 0), pressure: 0.3),
      def,
    );
    final heavy = geometry(line(Offset.zero, const Offset(500, 0)), def);
    expect(midWidth(heavy), greaterThan(midWidth(light) * 1.5));
    expect(heavy.width.first, lessThan(midWidth(heavy) * 0.5));
    expect(heavy.width.last, lessThan(midWidth(heavy) * 0.5));
  });

  test('6: fountain is wider along one diagonal by about 1 / aspect', () {
    final def = asset('amaze.fountain');
    // Screen y points down: "along 45°" runs up and to the right.
    final up = geometry(line(Offset.zero, const Offset(300, -300)), def);
    final down = geometry(line(Offset.zero, const Offset(300, 300)), def);
    final ratio = midWidth(up) / midWidth(down);
    expect(ratio, closeTo(1 / def.nib.aspect, 0.15 / def.nib.aspect));
  });

  test('7: dynamic thins fast strokes; without times it ignores speed', () {
    final def = asset('amaze.dynamic');
    // 500 units at zoom 1: 0.6 px/ms slow, 3 px/ms fast.
    final slow = geometry(
      line(Offset.zero, const Offset(500, 0), durationMs: 833),
      def,
    );
    final fast = geometry(
      line(Offset.zero, const Offset(500, 0), durationMs: 167),
      def,
    );
    final untimed = geometry(line(Offset.zero, const Offset(500, 0)), def);
    expect(midWidth(fast), lessThan(midWidth(slow) * 0.7));
    // Without times speed is ignored: as wide as a stroke drawn at rest.
    expect(midWidth(untimed), greaterThanOrEqualTo(midWidth(slow)));
    expect(midWidth(slow), closeTo(midWidth(untimed), midWidth(untimed) * 0.2));
    final still = geometry(
      line(Offset.zero, const Offset(500, 0), durationMs: 500000),
      def,
    );
    expect(midWidth(untimed), closeTo(midWidth(still), midWidth(still) * 0.01));
  });

  test('8: dotted places a dot every (gap + 1) widths', () {
    final def = asset('amaze.dotted');
    final path = buildOutline(
      line(Offset.zero, const Offset(1000, 0)),
      def,
      10,
      zoom: 1,
      origin: Offset.zero,
    );
    final dots = path.computeMetrics().length;
    expect(dots, closeTo((1000 / 28).floor(), 1.5));
  });

  test('9: zigzag outline points are at most 1 / zoom apart', () {
    final def = asset('amaze.pen');
    const zoom = 50.0;
    final g = geometry(
      const [PathPoint(0, 0), PathPoint(5, 5), PathPoint(10, 0)],
      def,
      width: 2,
      zoom: zoom,
    );
    for (var i = 1; i < g.length; i++) {
      final step = (g[i] - g[i - 1]).distance;
      expect(step, lessThanOrEqualTo(1 / zoom + 1e-9));
      for (final side in [1, -1]) {
        Offset at(int j) =>
            g[j] +
            Offset(-sin(g.angle[j]), cos(g.angle[j])) * (side * g.width[j] / 2);
        expect((at(i) - at(i - 1)).distance, lessThanOrEqualTo(1.1 / zoom));
      }
    }
  });

  test('10: outlining 2,000 points is fast', () {
    final def = asset('amaze.pen');
    final random = Random(1);
    var x = 0.0, y = 0.0;
    final points = [
      for (var i = 0; i < 2000; i++)
        PathPoint(
          x += 1 + random.nextDouble(),
          y += random.nextDouble() * 2 - 1,
          0.3 + random.nextDouble() * 0.7,
          null,
          null,
          i * 8,
        ),
    ];
    // Warm up, then time.
    for (var i = 0; i < 3; i++) {
      buildOutline(points, def, 5, zoom: 1, origin: Offset.zero);
    }
    final watch = Stopwatch()..start();
    const runs = 10;
    for (var i = 0; i < runs; i++) {
      buildOutline(points, def, 5, zoom: 1, origin: Offset.zero);
    }
    final ms = watch.elapsedMicroseconds / runs / 1000;
    // ignore: avoid_print
    print('Outline of 2,000 points: ${ms.toStringAsFixed(2)} ms');
    expect(ms, lessThan(30));
  });

  test('single point is a circle of the stroke width', () {
    final bounds = buildOutline(
      const [PathPoint(5, 5)],
      asset('amaze.fixed'),
      10,
      zoom: 1,
      origin: Offset.zero,
    ).getBounds();
    expect(bounds.width, closeTo(10, 0.01));
    expect(bounds.center.dx, closeTo(5, 0.01));
  });
}
