import 'dart:math';
import 'dart:ui';

import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'tool_harness.dart';

class MockEditorController extends Mock implements EditorController {}

void main() {
  test('snaps line endpoints to 45 degree increments', () {
    const start = Offset(10, 20);
    const cases = [
      (Offset(110, 30), 0.0),
      (Offset(20, 120), pi / 2),
      (Offset(-70, -40), -3 * pi / 4),
    ];

    for (final (end, direction) in cases) {
      final snapped = snapLineEndPosition(start, end);
      expect((snapped - start).direction, closeTo(direction, 1e-10));
      expect(
        (snapped - start).distance,
        closeTo((end - start).distance, 1e-10),
      );
    }
  });

  test('does not create shapes with zero size', () {
    final handler = ShapeHandler(ShapeTool());
    final cubit = MockEditorController();

    expect(
      handler.transformElements(
        Rect.fromPoints(Offset.zero, Offset.zero),
        '',
        cubit,
      ),
      isEmpty,
    );
  });

  test('still creates horizontal and vertical lines', () {
    final handler = ShapeHandler(
      ShapeTool(property: const ShapeProperty(shape: LineShape())),
    );
    final cubit = MockEditorController();

    expect(
      handler.transformElements(const Rect.fromLTRB(10, 10, 10, 20), '', cubit),
      isNotEmpty,
    );
    expect(
      handler.transformElements(const Rect.fromLTRB(10, 10, 20, 10), '', cubit),
      isNotEmpty,
    );
  });

  test('triangle creation preserves negative drag dimensions', () {
    final handler = ShapeHandler(
      ShapeTool(property: const ShapeProperty(shape: TriangleShape())),
    );
    final cubit = MockEditorController();

    final element =
        handler
                .transformElements(
                  const Rect.fromLTRB(100, 80, 10, 20),
                  '',
                  cubit,
                )
                .single
            as ShapeElement;

    expect(element.firstPosition.x, 100);
    expect(element.firstPosition.y, 80);
    expect(element.secondPosition.x, 10);
    expect(element.secondPosition.y, 20);
    expect(element.rotation, 0);
  });

  group('T2 shapes', () {
    test('4: a 7° line snaps to 0° on a hold, 2° at once', () {
      const start = Offset(0, 0);
      final end = Offset.fromDirection(-7 * pi / 180, 100);
      // Outside the 4° snap, so it stays until the pointer pauses.
      expect(snapShapeDrag(const LineShape(), start, end).snapped, isFalse);
      final result = snapShapeDrag(
        const LineShape(),
        start,
        end,
        perfect: true,
      );
      expect(result.snapped, isTrue);
      final near = Offset.fromDirection(2 * pi / 180, 100);
      expect(snapShapeDrag(const LineShape(), start, near).snapped, isTrue);
      expect((result.second - start).direction, closeTo(0, 1e-9));
      expect((result.second - start).distance, closeTo(100, 1e-9));
      // 9° is out of reach without a hold, but a hold snaps it.
      final free = Offset.fromDirection(9 * pi / 180, 100);
      expect(snapShapeDrag(const LineShape(), start, free).snapped, isFalse);
      final held = snapShapeDrag(const LineShape(), start, free, perfect: true);
      expect((held.second - start).direction, closeTo(pi / 12, 1e-9));
    });

    test('4: rectangles and circles snap to square near equal sides', () {
      final near = snapShapeDrag(
        const RectangleShape(),
        Offset.zero,
        const Offset(100, 96),
      );
      expect(near.snapped, isTrue);
      expect(near.second, const Offset(100, 100));
      final far = snapShapeDrag(
        const CircleShape(),
        Offset.zero,
        const Offset(-100, 80),
      );
      expect(far.snapped, isFalse);
      final held = snapShapeDrag(
        const CircleShape(),
        Offset.zero,
        const Offset(-100, 80),
        perfect: true,
      );
      expect(held.second, const Offset(-100, 100));
    });

    test('a held triangle is equilateral', () {
      final held = snapShapeDrag(
        const TriangleShape(),
        Offset.zero,
        const Offset(100, -30),
        perfect: true,
      );
      expect(held.second.dy, closeTo(-100 * sqrt(3) / 2, 1e-9));
    });

    test('the bubble names the size of each shape', () {
      expect(
        shapeMeasureText(
          const RectangleShape(),
          Offset.zero,
          const Offset(100, 50),
        ),
        '100 × 50 px',
      );
      expect(
        shapeMeasureText(
          const CircleShape(),
          Offset.zero,
          const Offset(80, 80),
        ),
        '⌀ 80 px',
      );
      expect(
        shapeMeasureText(const LineShape(), Offset.zero, const Offset(0, -50)),
        '50 px · 90°',
      );
    });

    testWidgets(
      '4: hold to perfect makes 100 × 96 a square; one undo step; selected',
      (tester) async {
        final harness = ToolHarness();
        await tester.runAsync(harness.setUp);
        addTearDown(() => tester.runAsync(harness.dispose));
        await harness.pumpContext(tester);
        final handler = ShapeHandler(
          ShapeTool(property: const ShapeProperty(shape: RectangleShape())),
        );
        await tester.runAsync(
          () => harness.drag(
            handler,
            const Offset(100, 100),
            const [Offset(150, 140), Offset(200, 196)],
            beforeEnd: () async {
              // Pause on the last point long enough to perfect it.
              await Future<void>.delayed(const Duration(milliseconds: 520));
              expect(handler.perfect, isTrue);
            },
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        expect(harness.createEvents, 1);
        final shape = harness.created.single.single as ShapeElement;
        final width = (shape.secondPosition.x - shape.firstPosition.x).abs();
        final height = (shape.secondPosition.y - shape.firstPosition.y).abs();
        expect(width, closeTo(100, 1e-6));
        expect(height, closeTo(100, 1e-6));
        expect(shape.id, isNotNull);
        // The new shape is selected with a temporary select tool.
        final temporary = harness.controller.toolCubit.state.temporaryHandler;
        expect(temporary, isA<SelectHandler>());
        expect((temporary as SelectHandler).getSelectionRect(), isNotNull);
        handler.dispose(harness.bloc);
      },
    );

    testWidgets('a second finger while drawing cancels the shape', (
      tester,
    ) async {
      final harness = ToolHarness();
      await tester.runAsync(harness.setUp);
      addTearDown(() => tester.runAsync(harness.dispose));
      final handler = ShapeHandler(ShapeTool());
      await tester.runAsync(
        () => harness.drag(
          handler,
          const Offset(10, 10),
          const [Offset(60, 60), Offset(90, 90)],
          beforeEnd: () async {
            handler.onPointerDown(
              const PointerDownEvent(pointer: 2, position: Offset(200, 200)),
              harness.context,
            );
          },
        ),
      );
      expect(harness.createEvents, 0);
      handler.dispose(harness.bloc);
    });
  });
}
