import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:butterfly/brushes/brush_registry.dart';
import 'package:butterfly/brushes/dynamics.dart' show stableHash;
import 'package:butterfly/brushes/stamp_engine.dart';
import 'package:butterfly/brushes/textures.dart';
import 'package:butterfly/handlers/handler.dart' show cutPenPointsForEraser;
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

BrushDefinition asset(String id) => BrushDefinition.fromJson(
  jsonDecode(File('assets/brushes/$id.v1.json').readAsStringSync())
      as Map<String, dynamic>,
);

List<PathPoint> polyline(List<Offset> corners, {double step = 2}) {
  final points = <PathPoint>[];
  for (var i = 1; i < corners.length; i++) {
    final a = corners[i - 1], b = corners[i];
    final n = ((b - a).distance / step).ceil();
    for (var k = i == 1 ? 0 : 1; k <= n; k++) {
      final p = Offset.lerp(a, b, k / n)!;
      points.add(PathPoint(p.dx, p.dy));
    }
  }
  return points;
}

StampStroke stamps(
  List<PathPoint> points,
  BrushDefinition def, {
  double width = 10,
  String seed = 'a',
  Offset origin = Offset.zero,
}) => StampStroke.build(
  points,
  def,
  width,
  zoom: 1,
  origin: origin,
  seed: stableHash(seed),
);

/// RGBA bytes of what [draw] paints on a [size]×[size] transparent canvas.
Future<Uint8List> raster(void Function(Canvas canvas) draw, [int size = 300]) {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  return () async {
    final image = await picture.toImage(size, size);
    final data = await image.toByteData();
    image.dispose();
    picture.dispose();
    return data!.buffer.asUint8List();
  }();
}

int channel(Uint8List rgba, int x, int y, int c, [int size = 300]) =>
    rgba[(y * size + x) * 4 + c];

int alphaAt(Uint8List rgba, int x, int y) => channel(rgba, x, y, 3);

double meanAlpha(Uint8List rgba, Rect area) {
  var sum = 0, count = 0;
  for (var y = area.top.toInt(); y < area.bottom; y++) {
    for (var x = area.left.toInt(); x < area.right; x++) {
      sum += alphaAt(rgba, x, y);
      count++;
    }
  }
  return sum / count;
}

/// Draws [points] with [def] the way the renderer does: at its origin.
void drawStroke(
  Canvas canvas,
  List<PathPoint> points,
  BrushDefinition def,
  Color color, {
  double width = 10,
  String seed = 'a',
}) {
  var left = points.first.x, top = points.first.y;
  for (final p in points) {
    if (p.x < left) left = p.x;
    if (p.y < top) top = p.y;
  }
  final origin = Offset(left, top);
  final s = stamps(points, def, width: width, seed: seed, origin: origin);
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  drawStampStroke(canvas, s, def, color, origin: origin);
  canvas.restore();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final id in [
      'amaze.softPencil',
      'amaze.hardPencil',
      'amaze.marker',
      'amaze.airbrush',
      'amaze.watercolor',
    ]) {
      registerBrush(asset(id));
    }
    await loadBrushTextures();
  });

  test('14: stamps are spaced by spacing × width', () {
    const def = BrushDefinition(
      engine: BrushEngine.stamp,
      texture: 'round-hard',
      spacing: 0.15,
      width: BrushWidth(pressureGamma: 0),
    );
    final s = stamps(
      polyline(const [Offset.zero, Offset(1000, 0)], step: 5),
      def,
    );
    expect(s.length, closeTo(1000 / 1.5, 1000 / 1.5 * 0.05));
  });

  test('15: stamps repeat for an element and differ between elements', () {
    final def = asset('amaze.softPencil');
    final points = polyline(const [Offset.zero, Offset(300, 40)]);
    final a = stamps(points, def, seed: 'element-1');
    final again = stamps(points, def, seed: 'element-1');
    final other = stamps(points, def, seed: 'element-2');
    expect(again.x, a.x);
    expect(again.y, a.y);
    expect(again.angle, a.angle);
    expect(other.angle, isNot(a.angle));
  });

  test(
    '16: a marker does not darken over itself, a second stroke does',
    () async {
      final def = asset('amaze.marker');
      const color = Color.fromRGBO(255, 0, 0, 0.6);
      // Right, down, left, then up through the first line at (100, 60).
      final loop = polyline(const [
        Offset(20, 60),
        Offset(160, 60),
        Offset(160, 120),
        Offset(100, 120),
        Offset(100, 20),
      ]);
      final once = await raster((c) => drawStroke(c, loop, def, color));
      final crossing = alphaAt(once, 100, 60);
      final single = alphaAt(once, 50, 60);
      expect(single, closeTo(153, 3));
      expect((crossing - single).abs(), lessThanOrEqualTo(2));

      final line = polyline(const [Offset(20, 60), Offset(160, 60)]);
      final twice = await raster((c) {
        drawStroke(c, line, def, color, seed: 'a');
        drawStroke(c, line, def, color, seed: 'b');
      });
      expect(alphaAt(twice, 50, 60), greaterThan(single + 40));
    },
  );

  test('17: watercolor has darker wet edges and mixes', () async {
    final def = asset('amaze.watercolor');
    const blue = Color.fromRGBO(30, 90, 230, 0.5);
    const yellow = Color.fromRGBO(240, 210, 20, 0.5);
    final line = polyline(const [Offset(30, 100), Offset(270, 100)]);
    final stroke = await raster(
      (c) => drawStroke(c, line, def, blue, width: 40),
    );
    final center = meanAlpha(stroke, const Rect.fromLTRB(120, 98, 180, 102));
    // Find the darkest band between the center and the rim.
    var edge = 0.0;
    for (var dy = 6; dy <= 18; dy++) {
      final band = meanAlpha(
        stroke,
        Rect.fromLTRB(120, 100.0 + dy, 180, 101.0 + dy),
      );
      if (band > edge) edge = band;
    }
    expect(edge, greaterThan(center));

    double luminance(Uint8List rgba, int x, int y) =>
        0.2126 * channel(rgba, x, y, 0) +
        0.7152 * channel(rgba, x, y, 1) +
        0.0722 * channel(rgba, x, y, 2);
    final white = Paint()..color = const Color(0xFFFFFFFF);
    final vertical = polyline(const [Offset(150, 20), Offset(150, 280)]);
    final both = await raster((c) {
      c.drawRect(const Rect.fromLTWH(0, 0, 300, 300), white);
      drawStroke(c, line, def, yellow, width: 40, seed: 'y');
      drawStroke(c, vertical, def, blue, width: 40, seed: 'b');
    });
    final mixed = luminance(both, 150, 100);
    final yellowOnly = luminance(both, 60, 100);
    final blueOnly = luminance(both, 150, 250);
    expect(mixed, lessThan(yellowOnly));
    expect(mixed, lessThan(blueOnly));
    // Mixed: less blue than the blue stroke, less red than the yellow one.
    expect(channel(both, 150, 100, 2), lessThan(channel(both, 150, 250, 2)));
    expect(channel(both, 150, 100, 0), lessThan(channel(both, 60, 100, 0)));
  });

  test('18: grain stays put on the canvas', () async {
    const def = BrushDefinition(
      engine: BrushEngine.stamp,
      texture: 'round-hard',
      spacing: 0.05,
      buildUp: false,
      width: BrushWidth(pressureGamma: 0),
      grain: BrushGrain(texture: 'paper', strength: 1),
    );
    const color = Color(0xFF000000);
    final across = polyline(const [Offset(17, 100), Offset(230, 100)]);
    final down = polyline(const [Offset(100, 33), Offset(100, 260)]);
    final a = await raster((c) => drawStroke(c, across, def, color, width: 30));
    final b = await raster((c) => drawStroke(c, down, def, color, width: 30));
    var differing = 0;
    for (var y = 92; y < 108; y++) {
      for (var x = 92; x < 108; x++) {
        if ((alphaAt(a, x, y) - alphaAt(b, x, y)).abs() > 2) differing++;
      }
    }
    expect(differing, 0);
    // The grain really is there: the alpha varies.
    final values = {for (var x = 92; x < 108; x++) alphaAt(a, x, 100)};
    expect(values.length, greaterThan(3));
  });

  test('19: generated textures are identical on every build', () {
    for (final name in kBrushTextureSizes.keys) {
      expect(generateTexturePixels(name), generateTexturePixels(name));
    }
  });

  test('20: building and recording 2,000 pencil points is fast', () {
    final def = asset('amaze.softPencil');
    var x = 0.0;
    final points = [
      for (var i = 0; i < 2000; i++)
        PathPoint(x += 1.5, 50 + (i % 40) * 0.5, 0.6, 0.3, 0, i * 8),
    ];
    void run() {
      final s = stamps(points, def, width: 4);
      recordStampStroke(
        s,
        def,
        const Color(0xFF000000),
        origin: Offset.zero,
      ).dispose();
    }

    for (var i = 0; i < 3; i++) {
      run();
    }
    final watch = Stopwatch()..start();
    const runs = 10;
    for (var i = 0; i < runs; i++) {
      run();
    }
    final ms = watch.elapsedMicroseconds / runs / 1000;
    // ignore: avoid_print
    print('Stamps of 2,000 points: ${ms.toStringAsFixed(2)} ms');
    expect(ms, lessThan(60));
  });

  test('21: SVG export embeds a pencil stroke as an image', () async {
    final element = PenElement(
      id: 'pencil',
      zoom: 1,
      points: polyline(const [Offset(10, 10), Offset(200, 80)]),
      property: const PenProperty(brush: 'amaze.softPencil', strokeWidth: 6),
    );
    final renderer = PenRenderer(element);
    await renderer.prepareExport(pixelsPerUnit: 2);
    final xml = XmlDocument.parse('<svg/>');
    renderer.buildSvg(
      xml,
      NoteData(Archive()),
      const DocumentPage(),
      Rect.largest,
    );
    final image = xml.findAllElements('image').single;
    final rect = Rect.fromLTWH(
      double.parse(image.getAttribute('x')!),
      double.parse(image.getAttribute('y')!),
      double.parse(image.getAttribute('width')!),
      double.parse(image.getAttribute('height')!),
    );
    const points = Rect.fromLTRB(10, 10, 200, 80);
    expect(rect.inflate(1e-6).contains(points.topLeft), isTrue);
    expect(rect.inflate(1e-6).contains(points.bottomRight), isTrue);
    expect(points.inflate(6 * 3).contains(rect.topLeft), isTrue);
    expect(points.inflate(6 * 3).contains(rect.bottomRight), isTrue);
    expect(image.getAttribute('href'), startsWith('data:image/png;base64,'));
    renderer.dispose();
  });

  group('Stable texture across edits', () {
    final def = asset('amaze.softPencil');
    setUpAll(() => registerBrush(def));

    // A gentle S-curve with a pressure ramp, sampled like pen input.
    List<PathPoint> curve() => [
      for (var i = 0; i <= 120; i++)
        PathPoint(
          20 + i * 2.0,
          100 + 30 * sin(i / 120 * 2 * pi),
          0.2 + 0.8 * i / 120,
        ),
    ];

    StampStroke build(PenElement element) {
      final first = element.points.first;
      return StampStroke.build(
        element.points,
        def,
        element.property.strokeWidth,
        zoom: element.zoom ?? 1,
        origin: Offset(first.x, first.y),
        seed: brushSeedOf(element.extra, element.id),
        start: StampWalkStart.of(element.extra),
      );
    }

    test('strokes without a seed use their id, as before', () {
      expect(brushSeedOf(const {}, 'element-1'), stableHash('element-1'));
      expect(brushSeedOf(const {kBrushSeedKey: 42}, 'element-1'), 42);
      final points = polyline([const Offset(10, 10), const Offset(200, 40)]);
      final before = stamps(points, def, seed: 'element-1');
      final now = StampStroke.build(
        points,
        def,
        10,
        zoom: 1,
        origin: Offset.zero,
        seed: brushSeedOf(const {}, 'element-1'),
      );
      expect(now.x, before.x);
      expect(now.angle, before.angle);
    });

    for (final seeded in [true, false]) {
      test('erasing the middle keeps every surviving stamp '
          '(${seeded ? 'seeded' : 'old stroke'})', () {
        final original = PenElement(
          id: 'stroke',
          zoom: 1,
          extra: seeded ? const {kBrushSeedKey: 123456} : const {},
          property: const PenProperty(
            brush: 'amaze.softPencil',
            strokeWidth: 8,
          ),
          points: curve(),
        );
        final pieces = cutPenPointsForEraser(
          original.points,
          const Offset(140, 100),
          6,
        )!;
        expect(pieces, hasLength(2));
        final whole = build(original);
        final origin = Offset(original.points.first.x, original.points.first.y);
        final byIndex = {
          for (var i = 0; i < whole.length; i++) whole.index[i]: i,
        };
        var matched = 0;
        for (final points in pieces) {
          final piece = PenElement(
            id: 'new-${points.length}',
            zoom: 1,
            property: original.property,
            points: points,
            extra: brushPieceExtra(original, points),
          );
          expect(
            piece.extra[kBrushSeedKey],
            brushSeedOf(original.extra, 'stroke'),
          );
          expect(piece.extra[kBrushSeedOffsetKey], isA<double>());
          final part = build(piece);
          final partOrigin = Offset(points.first.x, points.first.y);
          expect(part.length, greaterThan(10));
          for (var i = 0; i < part.length; i++) {
            final j = byIndex[part.index[i]];
            expect(j, isNotNull, reason: 'stamp ${part.index[i]}');
            expect(
              part.x[i] + partOrigin.dx,
              closeTo(whole.x[j!] + origin.dx, .01),
            );
            expect(
              part.y[i] + partOrigin.dy,
              closeTo(whole.y[j] + origin.dy, .01),
            );
            expect(part.size[i], closeTo(whole.size[j], .01));
            expect(part.angle[i], closeTo(whole.angle[j], .01));
            matched++;
          }
        }
        // Everything outside the erased gap survives.
        expect(matched, greaterThan(whole.length * .8));
      });
    }
  });
}
