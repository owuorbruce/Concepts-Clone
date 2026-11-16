import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly/renderers/textures/texture.dart';
import 'package:butterfly/view_painter.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts draw calls; every other canvas call is accepted and ignored.
class _CountingCanvas implements ui.Canvas {
  var verticalLines = 0;
  var horizontalLines = 0;
  var paths = 0;
  var rects = 0;

  @override
  void drawLine(ui.Offset p1, ui.Offset p2, ui.Paint paint) {
    if (p1.dx == p2.dx) {
      verticalLines++;
    } else {
      horizontalLines++;
    }
  }

  @override
  void drawPath(ui.Path path, ui.Paint paint) => paths++;

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) => rects++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _screen = ui.Size(1920, 1080);

_CountingCanvas _drawBackground(PatternTexture texture, double zoom) {
  final canvas = _CountingCanvas();
  TextureBackgroundRenderer(TextureBackground(texture: texture)).build(
    canvas,
    _screen,
    NoteData(Archive()),
    const DocumentPage(),
    const DocumentInfo(),
    CameraTransform(1, const ui.Offset(123456789, -98765.4321), zoom),
  );
  return canvas;
}

PenRenderer _pen(double x, double length) => PenRenderer(
  PenElement(
    property: const PenProperty(strokeWidth: 2, thinning: 0),
    points: [PathPoint(x, 0), PathPoint(x + length, 0)],
  ),
  null,
  ui.Rect.fromLTRB(x, 0, x + length, 0),
  ui.Rect.fromLTRB(x - 2, -2, x + length + 2, 2),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adaptive pattern background', () {
    final quad = PatternTemplate.quad.create();
    final dotted = PatternTemplate.dotted.create();

    test('draws at most 400 lines per direction at 1e-6, quickly', () {
      for (final texture in [quad, dotted]) {
        final stopwatch = Stopwatch()..start();
        final canvas = _drawBackground(texture, 1e-6);
        stopwatch.stop();
        expect(canvas.verticalLines, inInclusiveRange(1, 400));
        expect(canvas.horizontalLines, inInclusiveRange(1, 400));
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      }
    });

    test('stays within the line budget across the whole zoom range', () {
      for (var exponent = -6.0; exponent <= 3; exponent += 0.25) {
        final zoom = pow(10, exponent).toDouble();
        final canvas = _drawBackground(quad, zoom);
        expect(canvas.verticalLines, lessThanOrEqualTo(400), reason: '$zoom');
        expect(canvas.horizontalLines, lessThanOrEqualTo(400), reason: '$zoom');
      }
    });

    test('keeps the defined spacing at normal and higher zoom', () {
      for (final zoom in [1.0, 10.0, 1000.0]) {
        final level = patternLevel(quad, zoom, _screen / zoom)!;
        expect(level.multiplier, 1);
        expect(level.fade, 1);
      }
    });

    test('switches to five times bigger boxes below 8 px', () {
      // 40 units at 0.1x are 4 px on screen: one level up is 20 px.
      final level = patternLevel(quad, 0.1, _screen / 0.1)!;
      expect(level.multiplier, 5);
      expect(level.fade, closeTo((20 - 8) / 16, 1e-9));
    });

    test('the grid tool stays within its budget at any zoom', () {
      final tool = GridTool(xSize: 20, ySize: 20, zoomDependent: true);
      for (final zoom in [1e-6, 1e-3, 1.0, 1000.0]) {
        final canvas = _CountingCanvas();
        GridRenderer(tool).build(
          canvas,
          _screen,
          NoteData(Archive()),
          const DocumentPage(),
          const DocumentInfo(),
          CameraTransform(1, const ui.Offset(987654321, 12345), zoom),
        );
        expect(canvas.verticalLines, lessThanOrEqualTo(400), reason: '$zoom');
        expect(canvas.horizontalLines, lessThanOrEqualTo(400), reason: '$zoom');
      }
    });
  });

  test('1,000 strokes at 1e-5 skip tiny ones and dot small ones', () {
    // At 1e-5, 1e2 units are 0.001 px, 1.5e5 units 1.5 px, 1e6 units 10 px.
    final renderers = <Renderer<PadElement>>[
      for (var i = 0; i < 500; i++) _pen(i * 1e3, 1e2),
      for (var i = 0; i < 300; i++) _pen(1e6 + i * 2e5, 1.5e5),
      for (var i = 0; i < 200; i++) _pen(1e8 + i * 2e6, 1e6),
    ];
    final canvas = _CountingCanvas();
    ViewPainter(
      NoteData(Archive()),
      const DocumentPage(),
      const DocumentInfo(),
      transform: const CameraTransform(1, ui.Offset.zero, 1e-5),
      cameraViewport: CameraViewport.unbaked(
        unbakedElements: renderers,
        visibleElements: renderers,
        visibleUnbakedElements: renderers,
      ),
    ).paint(canvas, _screen);
    expect(canvas.paths, 200);
    expect(canvas.rects, 300);
  });

  test('tiny-element culling leaves normal zoom and exports alone', () {
    final tiny = _pen(0, 0.1);
    expect(elementDetail(tiny, 1), ElementDetail.full);
    expect(elementDetail(tiny, 1e-3), ElementDetail.skip);

    final canvas = _CountingCanvas();
    ViewPainter(
      NoteData(Archive()),
      const DocumentPage(),
      const DocumentInfo(),
      transform: const CameraTransform(1, ui.Offset.zero, 1e-3),
      reduceDetail: false,
      cameraViewport: CameraViewport.unbaked(
        unbakedElements: [tiny],
        visibleElements: [tiny],
        visibleUnbakedElements: [tiny],
      ),
    ).paint(canvas, _screen);
    expect(canvas.paths, 1);
  });

  test('the bake never exceeds the viewport at extreme zoom', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsCubit(await SharedPreferences.getInstance());
    final cubit = RendererCubit(settings);
    const viewport = ui.Size(1280, 800);
    final multiplier = settings.state.renderResolution.multiplier;
    for (final zoom in [1e-6, 1000.0]) {
      final transform = TransformCubit(1)
        ..teleport(const ui.Offset(5e8, -3e8), zoom);
      void expectBounded() {
        final rect = cubit.getViewportRect(transform, viewportSize: viewport);
        final imageSize = rect.size * transform.state.size;
        expect(
          imageSize.width,
          lessThanOrEqualTo(viewport.width * multiplier + 2),
        );
        expect(
          imageSize.height,
          lessThanOrEqualTo(viewport.height * multiplier + 2),
        );
      }

      expectBounded();
      // A long fling covers many screens; the bake still stays one screen.
      transform.slide(ui.Offset(viewport.width * 50 / zoom, 0), 0);
      expect(transform.state.friction, isNotNull);
      expectBounded();
      await transform.close();
    }
    await cubit.close();
    await settings.close();
  });

  group('Precision far from the origin', () {
    const size = ui.Size(120, 40);
    const world = 1e6;

    // Returns the left edge of the red shape on screen, in pixels, with
    // sub-pixel accuracy from antialiasing coverage.
    Future<double> leftEdge(double cameraOffset) async {
      final renderer = ShapeRenderer(
        ShapeElement(
          firstPosition: const Point(world + 0.05, world),
          secondPosition: const Point(world + 0.1, world + 0.04),
          property: const ShapeProperty(
            strokeWidth: 0,
            shape: RectangleShape(
              fillPaint: ElementPaint.solid(color: SRGBColor(0xFFFF0000)),
            ),
          ),
        ),
      );
      final recorder = ui.PictureRecorder();
      ViewPainter(
        NoteData(Archive()),
        const DocumentPage(),
        const DocumentInfo(),
        transform: CameraTransform(
          1,
          ui.Offset(world + cameraOffset, world),
          1000,
        ),
        cameraViewport: CameraViewport.unbaked(
          unbakedElements: [renderer],
          visibleElements: [renderer],
          visibleUnbakedElements: [renderer],
        ),
      ).paint(ui.Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final ByteData data = (await image.toByteData())!;
      image.dispose();
      picture.dispose();
      const row = 20;
      var covered = 0.0;
      int? first;
      for (var x = 0; x < size.width; x++) {
        // White background, red shape: coverage is how much green is gone.
        final green = data.getUint8((row * size.width.toInt() + x) * 4 + 1);
        final coverage = 1 - green / 255;
        if (coverage > 0.01) {
          first ??= x;
          covered += coverage;
        }
      }
      expect(first, isNotNull);
      // The shape is 50 px wide; its left edge is the right edge minus that.
      final firstFull = first! + 1;
      final partial =
          1 - data.getUint8((row * size.width.toInt() + first) * 4 + 1) / 255;
      expect(covered, closeTo(50, 1));
      return firstFull - partial;
    }

    test('a shape at (1e6, 1e6) and 1000x lands within 0.5 px', () async {
      for (final offset in [0.0123, 0.0127, 0.0131, 0.0002]) {
        final expected = (0.05 - offset) * 1000;
        expect(
          await leftEdge(offset),
          closeTo(expected, 0.5),
          reason: '$offset',
        );
      }
    });
  });
}
