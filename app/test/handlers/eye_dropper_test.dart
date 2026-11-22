import 'dart:ui' as ui;

import 'package:butterfly/brushes/brush_registry.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/view_painter.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import 'tool_harness.dart';

const _blue = SRGBColor(0xFF2050E0);
const _red = SRGBColor(0xFFE02020);

List<PadElement> _watercolor() => [
  PenElement(
    id: 'wash',
    property: const PenProperty(
      brush: 'amaze.watercolor',
      strokeWidth: 40,
      paint: ElementPaint.solid(color: _red),
    ),
    points: [
      for (var x = 100; x <= 500; x += 10) PathPoint(x.toDouble(), 300, 1),
    ],
  ),
];

void main() {
  testWidgets('8: sampling watercolor over blue gives the composited color', (
    tester,
  ) async {
    await tester.runAsync(loadBrushRegistry);
    final harness = ToolHarness();
    await tester.runAsync(
      () => harness.setUp(
        content: _watercolor(),
        backgrounds: [
          Background.texture(texture: const PatternTexture(boxColor: _blue)),
        ],
      ),
    );
    addTearDown(() => tester.runAsync(harness.dispose));
    await tester.runAsync(harness.bake);
    when(() => harness.context.devicePixelRatio).thenReturn(1);
    final handler = EyeDropperHandler(EyeDropperTool());
    const point = Offset(300, 300);
    final picked = await tester.runAsync(
      () => handler.pick(harness.context, point),
    );
    expect(picked, isNotNull);

    // What the canvas shows: the whole viewport painted as on screen.
    final state = harness.state;
    final reference = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ViewPainter(
        state.data,
        state.page,
        state.info,
        cameraViewport: harness.controller.rendererCubit.state.cameraViewport,
        transform: harness.controller.transformCubit.state,
      ).paint(Canvas(recorder), const Size(800, 600));
      final picture = recorder.endRecording();
      final image = await picture.toImage(800, 600);
      final bytes = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      image.dispose();
      picture.dispose();
      final offset = (300 * 800 + 300) * 4;
      return (
        r: bytes!.getUint8(offset),
        g: bytes.getUint8(offset + 1),
        b: bytes.getUint8(offset + 2),
      );
    });
    final color = picked!;
    final expected = reference!;
    expect((color.r - expected.r).abs(), lessThanOrEqualTo(2));
    expect((color.g - expected.g).abs(), lessThanOrEqualTo(2));
    expect((color.b - expected.b).abs(), lessThanOrEqualTo(2));
    // Not the stroke's raw color, and not the bare background.
    expect(color.value, isNot(_red.value));
    expect(color.value, isNot(_blue.value));

    // Outside the stroke it is the background.
    final background = await tester.runAsync(
      () => handler.pick(harness.context, const Offset(300, 100)),
    );
    expect((background!.b - _blue.b).abs(), lessThanOrEqualTo(2));
    handler.dispose(harness.bloc);
  });

  test('a sample reads pixels at the device pixel ratio', () {
    expect(kEyeDropperZoom, 5);
    expect(kEyeDropperSampleRadius, greaterThan(EyeDropperMagnifier.radius));
  });
}
