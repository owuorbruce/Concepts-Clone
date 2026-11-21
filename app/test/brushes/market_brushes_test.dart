import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:butterfly/brushes/brush_registry.dart';
import 'package:butterfly/brushes/textures.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly/services/asset.dart';
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

BrushDefinition asset(String id) => BrushDefinition.fromJson(
  jsonDecode(File('assets/brushes/$id.v1.json').readAsStringSync())
      as Map<String, dynamic>,
);

List<PathPoint> line(Offset a, Offset b, {double step = 2}) {
  final n = ((b - a).distance / step).ceil();
  return [
    for (var k = 0; k <= n; k++)
      () {
        final p = Offset.lerp(a, b, k / n)!;
        return PathPoint(p.dx, p.dy, 0.8, null, null, k * 12);
      }(),
  ];
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

/// RGBA bytes of [renderer] drawn on a transparent 300×300 canvas.
Future<Uint8List> raster(PenRenderer renderer) async {
  final recorder = ui.PictureRecorder();
  renderer.build(
    Canvas(recorder),
    const Size(300, 300),
    NoteData(Archive()),
    const DocumentPage(),
    DocumentInfo(),
    const CameraTransform(),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 300);
  final data = await image.toByteData();
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 300 + x) * 4 + 3];

PenElement stroke(String brush, List<PathPoint> points, {double width = 30}) =>
    PenElement(
      id: 'test:$brush',
      zoom: 1,
      points: points,
      property: PenProperty(
        brush: brush,
        strokeWidth: width,
        paint: const ElementPaint.solid(color: SRGBColor(0xff000000)),
      ),
    );

/// Counts image draws; everything else is ignored.
class _CountingCanvas implements Canvas {
  int imageRects = 0;

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      imageRects++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final marketIds = [
    for (final entry in LibraryEntry.of(LibrarySection.market))
      ...entry.packBrushIds,
  ];

  setUpAll(() async {
    for (final id in marketIds) {
      registerBrush(asset(id));
    }
    await loadBrushTextures();
  });

  test('every pack has 4 brushes, 16 in all', () {
    for (final entry in LibraryEntry.of(LibrarySection.market)) {
      expect(entry.packBrushIds, hasLength(4), reason: entry.name);
    }
    expect(marketIds.toSet(), hasLength(16));
  });

  test('6: every market definition loads and draws a short stroke', () async {
    for (final id in marketIds) {
      final definition = asset(id);
      expect(definition.id, id);
      expect(definition.version, 1);
      for (final name in [
        definition.texture,
        definition.pattern.texture,
        definition.grain.texture,
        definition.endStamp?.texture ?? '',
      ]) {
        if (name.isEmpty) continue;
        expect(kBrushTextureSizes, contains(name), reason: '$id: $name');
      }
      if (definition.pattern.texture.isNotEmpty) {
        expect(kPatternTextures, contains(definition.pattern.texture));
      }
      final renderer = await setUpPen(
        stroke(id, line(const Offset(40, 150), const Offset(260, 150))),
      );
      final pixels = await raster(renderer);
      var ink = 0;
      for (var i = 3; i < pixels.length; i += 4) {
        ink += pixels[i];
      }
      expect(ink, greaterThan(0), reason: id);
      renderer.dispose();
    }
  });

  test('every new texture generates and patterns tile', () {
    for (final name in [...kPatternTextures, 'splatter', 'blot', 'bleed']) {
      final pixels = generateTexturePixels(name);
      expect(pixels.any((value) => value > 0), isTrue, reason: name);
    }
    for (final name in kPatternTextures) {
      final size = kBrushTextureSizes[name]!;
      final pixels = generateTexturePixels(name);
      int a(int x, int y) => pixels[(y * size + x) * 4 + 3];
      // Opposite edges continue each other: no hard seam on any row.
      var seam = 0;
      for (var y = 0; y < size; y++) {
        seam += (a(0, y) - a(size - 1, y)).abs();
        seam += (a(y, 0) - a(y, size - 1)).abs();
      }
      expect(seam / (2 * size), lessThan(110), reason: name);
    }
  });

  test('7: patterns are anchored to the canvas, not the stroke', () async {
    // Two strokes that start in different places and cross at (150, 100).
    final across = await setUpPen(
      stroke(
        'amaze.hatch.hatch',
        line(const Offset(20, 100), const Offset(280, 100)),
        width: 50,
      ),
    );
    final down = await setUpPen(
      stroke(
        'amaze.hatch.hatch',
        line(const Offset(150, 10), const Offset(150, 290)),
        width: 50,
      ),
    );
    final a = await raster(across);
    final b = await raster(down);
    final seen = <int>{};
    for (var y = 92; y <= 108; y++) {
      for (var x = 142; x <= 158; x++) {
        expect(
          (alphaAt(a, x, y) - alphaAt(b, x, y)).abs(),
          lessThanOrEqualTo(3),
          reason: '($x, $y)',
        );
        seen.add(alphaAt(a, x, y) ~/ 32);
      }
    }
    // The spot really shows a pattern, not a solid fill.
    expect(seen.length, greaterThan(1));
    across.dispose();
    down.dispose();
  });

  test('8: drip pen draws its end stamp once', () async {
    final renderer = await setUpPen(
      stroke(
        'amaze.ink.dripPen',
        line(const Offset(20, 20), const Offset(200, 60)),
        width: 6,
      ),
    );
    final canvas = _CountingCanvas();
    renderer.localOrigin;
    renderer.buildLocal(canvas);
    expect(canvas.imageRects, 1);
    // Its bounds include the drop at the last point.
    expect(
      renderer.expandedRect.contains(const Offset(200 + 4, 60 + 4)),
      isTrue,
    );
    renderer.dispose();
  });
}
