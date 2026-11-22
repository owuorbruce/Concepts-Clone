import 'dart:math';

import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/renderers/foregrounds/select.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'tool_harness.dart';

List<PadElement> _strokes(int count) => [
  for (var i = 0; i < count; i++)
    PenElement(
      id: 'stroke-$i',
      points: [
        PathPoint((i % 20) * 30.0, (i ~/ 20) * 30.0),
        PathPoint((i % 20) * 30.0 + 20, (i ~/ 20) * 30.0 + 10),
      ],
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('selection manager', () {
    test('7: rotation snaps to 15°', () {
      final manager = RectSelectionForegroundManager()
        ..rotationSnapStep = 15
        ..select(const Rect.fromLTWH(0, 0, 100, 100))
        ..startTransformWithCorner(
          SelectionTransformCorner.center,
          const Offset(100, 50),
        );
      // Turn the handle 13° around the center.
      const pivot = Offset(50, 50);
      manager.updateCurrentPosition(
        pivot + Offset.fromDirection(13 * pi / 180, 50),
      );
      final transform = manager.getTransform()!;
      expect(transform.rotation, closeTo(15, 1e-9));
      expect(manager.rotationSnapped, isTrue);
      manager.updateCurrentPosition(
        pivot + Offset.fromDirection(8 * pi / 180, 50),
      );
      expect(manager.getTransform()!.rotation, closeTo(8, 1e-9));
      expect(manager.rotationSnapped, isFalse);
    });

    test('corner handles keep the aspect ratio, side handles do not', () {
      final manager = RectSelectionForegroundManager()
        ..proportionalCorners = true
        ..select(const Rect.fromLTWH(0, 0, 100, 50))
        ..startTransformWithCorner(
          SelectionTransformCorner.bottomRight,
          const Offset(100, 50),
        )
        ..updateCurrentPosition(const Offset(200, 60));
      var transform = manager.getTransform()!;
      expect(transform.scaleX, transform.scaleY);
      manager
        ..startTransformWithCorner(
          SelectionTransformCorner.centerRight,
          const Offset(100, 25),
        )
        ..updateCurrentPosition(const Offset(200, 25));
      transform = manager.getTransform()!;
      expect(transform.scaleX, 2);
      expect(transform.scaleY, 1);
    });
  });

  group('select handler', () {
    late ToolHarness harness;

    setUp(() async {
      harness = ToolHarness();
      await harness.setUp(content: _strokes(300));
    });

    tearDown(() => harness.dispose());

    test('7: moving 300 elements builds no new elements per frame', () async {
      final handler = SelectHandler(SelectTool());
      handler.selectAll(harness.bloc);
      expect(handler.getSelectionRect(), isNotNull);
      final state = harness.state;
      handler.transform(harness.bloc, null, position: const Offset(10, 10));
      final before = SelectHandler.previewTransforms;
      for (var i = 1; i <= 30; i++) {
        handler.onScaleUpdate(
          ScaleUpdateDetails(
            localFocalPoint: Offset(10.0 + i * 3, 10.0 + i * 2),
            pointerCount: 1,
          ),
          harness.context,
        );
        final foregrounds = handler.createForegrounds(
          harness.controller,
          state.data,
          state.page,
          state.info,
        );
        expect(foregrounds.whereType<SelectionPreviewRenderer>(), hasLength(1));
      }
      expect(SelectHandler.previewTransforms, before);
      // Releasing applies the move once, in one undo step.
      await handler.onScaleEnd(ScaleEndDetails(), harness.context);
      await harness.settle();
      expect(SelectHandler.previewTransforms - before, 300);
    });

    test('the move preview puts elements where the move does', () async {
      final handler = SelectHandler(SelectTool());
      handler.selectAll(harness.bloc, (r) => r.element.id == 'stroke-21');
      handler.transform(
        harness.bloc,
        SelectionTransformCorner.center,
        position: handler.getSelectionRect()!.center + const Offset(40, 0),
      );
      final center = handler.getSelectionRect()!.center;
      handler.onScaleUpdate(
        ScaleUpdateDetails(
          localFocalPoint: center + Offset.fromDirection(0.7, 40),
          pointerCount: 1,
        ),
        harness.context,
      );
      final matrix = handler.previewMatrix()!;
      final renderer = harness.controller.rendererCubit.renderers.firstWhere(
        (r) => r.element.id == 'stroke-21',
      );
      await handler.onScaleEnd(ScaleEndDetails(), harness.context);
      await harness.settle();
      final moved = harness.content.firstWhere(
        (element) => element.id == 'stroke-21',
      ) as PenElement;
      final original = renderer.element as PenElement;
      final movedRenderer = Renderer.fromInstance(moved as PadElement);
      expect(moved, isNot(original));
      for (final point in original.points) {
        final local = Offset(point.x, point.y);
        final expected = MatrixUtils.transformPoint(
          matrix,
          renderer.transformPoint(local),
        );
        final actual = movedRenderer.transformPoint(local);
        expect(actual.dx, closeTo(expected.dx, 1e-6));
        expect(actual.dy, closeTo(expected.dy, 1e-6));
      }
    });
  });
}
