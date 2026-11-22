import 'dart:math';

import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tool_harness.dart';

ShapeElement _box(String id, double left, double width) => ShapeElement(
  id: id,
  firstPosition: Point(left, 100),
  secondPosition: Point(left + width, 140),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('insert space moves the right side whole, in one undo step', () async {
    final harness = ToolHarness();
    await harness.setUp(
      content: [
        _box('left', 0, 40),
        _box('across', 180, 60),
        _box('right', 400, 40),
      ],
    );
    addTearDown(harness.dispose);
    final handler = SpacerHandler(SpacerTool(axis: Axis2D.horizontal));
    await harness.drag(handler, const Offset(200, 50), const [
      Offset(220, 52),
      Offset(260, 60),
    ]);
    await harness.settle();
    expect(harness.changed, hasLength(1));
    final changes = harness.changed.single;
    expect(changes.keys, containsAll(['across', 'right']));
    expect(changes.keys, isNot(contains('left')));
    final across = changes['across']!.single as ShapeElement;
    // Moved by the drag along the axis only, and not stretched.
    expect(across.firstPosition.x, closeTo(240, 1e-9));
    expect(across.secondPosition.x - across.firstPosition.x, 60);
    expect(across.firstPosition.y, 100);
  });

  test('dragging back brings the right side together', () async {
    final harness = ToolHarness();
    await harness.setUp(content: [_box('left', 0, 40), _box('right', 400, 40)]);
    addTearDown(harness.dispose);
    final handler = SpacerHandler(SpacerTool(axis: Axis2D.horizontal));
    await harness.drag(handler, const Offset(200, 50), const [Offset(150, 50)]);
    final right = harness.changed.single['right']!.single as ShapeElement;
    expect(right.firstPosition.x, closeTo(350, 1e-9));
    expect(harness.changed.single.keys, isNot(contains('left')));
  });
}
