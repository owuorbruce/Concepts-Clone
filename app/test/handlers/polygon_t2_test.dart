import 'dart:math';

import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tool_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ToolHarness harness;
  late PolygonHandler handler;

  setUp(() async {
    harness = ToolHarness();
    await harness.setUp();
    handler = PolygonHandler(PolygonTool());
  });

  tearDown(() => harness.dispose());

  Future<void> tap(Offset position) async {
    handler.onTapUp(
      TapUpDetails(kind: PointerDeviceKind.touch, localPosition: position),
      harness.context,
    );
    await harness.settle();
  }

  /// Waits out the double-tap window so the next tap is a new one.
  Future<void> pause() =>
      Future<void>.delayed(const Duration(milliseconds: 320));

  test('5: tapping the first corner closes the polygon', () async {
    await tap(const Offset(100, 100));
    await pause();
    await tap(const Offset(300, 100));
    await pause();
    await tap(const Offset(300, 300));
    await pause();
    await tap(const Offset(104, 103));
    await harness.settle();
    expect(harness.createEvents, 1);
    final polygon = harness.created.single.single as PolygonElement;
    expect(polygon.points.length, 4);
    expect(polygon.points.first.x, polygon.points.last.x);
    expect(polygon.points.first.y, polygon.points.last.y);
  });

  test('5: undo while drawing removes one corner', () async {
    await harness.controller.toolCubit.changeTool(
      harness.controller,
      harness.bloc,
      handler: handler,
      allowBake: false,
    );
    expect(harness.controller.toolCubit.getHandler(), same(handler));
    await tap(const Offset(100, 100));
    await pause();
    await tap(const Offset(300, 100));
    await pause();
    await tap(const Offset(300, 300));
    harness.bloc.sendUndo();
    await harness.settle();
    expect(harness.createEvents, 0);
    await pause();
    await tap(const Offset(100, 300));
    await pause();
    // Finish open with a double-tap on a new corner.
    await tap(const Offset(500, 300));
    await tap(const Offset(500, 300));
    await harness.settle();
    final polygon = harness.created.single.single as PolygonElement;
    expect(
      [for (final point in polygon.points) Offset(point.x, point.y)],
      const [
        Offset(100, 100),
        Offset(300, 100),
        Offset(100, 300),
        Offset(500, 300),
      ],
    );
  });

  test('sides snap to 15° and corners to existing corners', () async {
    await tap(const Offset(100, 100));
    await pause();
    // 3° off horizontal snaps flat.
    await tap(Offset(100 + 200 * cos(pi / 60), 100 + 200 * sin(pi / 60)));
    await pause();
    final snapped = handler.snapCorner(harness.context, const Offset(108, 96));
    expect(snapped.snapped, isTrue);
    expect(snapped.point, const Offset(100, 100));
    await tap(const Offset(300, 400));
    await pause();
    await tap(const Offset(300, 400));
    await tap(const Offset(300, 400));
    await harness.settle();
    final polygon = harness.created.single.single as PolygonElement;
    expect(polygon.points[1].y, closeTo(100, 1e-9));
    expect(polygon.points[1].x, closeTo(300, 1e-6));
  });
}
