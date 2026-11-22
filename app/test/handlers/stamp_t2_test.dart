import 'dart:math';

import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/views/amaze/objects/object_placement.dart';
import 'package:butterfly/views/amaze/objects/object_store.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tool_harness.dart';

ButterflyComponent _chair() => ButterflyComponent(
  elements: [
    ShapeElement(
      id: 'seat',
      firstPosition: const Point(-20, -20),
      secondPosition: const Point(20, 20),
    ),
    PenElement(
      id: 'back',
      points: const [PathPoint(-20, -30), PathPoint(20, -30)],
    ),
  ],
);

Map<String, dynamic> _withoutId(PadElement element) =>
    element.toJson()..remove('id');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => pendingStampTool.value = null);

  test('10: placing gives the same elements as the Objects panel', () async {
    final harness = ToolHarness();
    await harness.setUp();
    addTearDown(harness.dispose);
    final component = _chair();
    final handler = StampHandler(
      StampTool(
        component: NamedItem(name: 'Chair', item: component),
      ),
    );
    await handler.onTapUp(
      TapUpDetails(
        kind: PointerDeviceKind.touch,
        localPosition: const Offset(300, 200),
      ),
      harness.context,
    );
    await harness.settle();
    expect(harness.createEvents, 1);
    final placed = harness.created.single;
    final expected = placeComponentAt(component, const Offset(300, 200));
    expect(placed.map(_withoutId).toList(), expected.map(_withoutId).toList());
    expect(placed.every((element) => element.id != null), isTrue);
  });

  test('15: a stamp with no object asks the Objects panel for one', () async {
    final harness = ToolHarness();
    await harness.setUp();
    addTearDown(harness.dispose);
    final handler = StampHandler(StampTool(id: 'stamp'));
    await handler.onTapUp(
      TapUpDetails(
        kind: PointerDeviceKind.touch,
        localPosition: const Offset(10, 10),
      ),
      harness.context,
    );
    expect(harness.createEvents, 0);
    expect(pendingStampTool.value?.id, 'stamp');
    // Picking an object there gives it to the stamp, not the canvas.
    final entry = ObjectEntry.fromComponent(
      'pack',
      'Pack',
      NamedItem(name: 'Chair', item: _chair()),
    );
    expect(completeStampPick(harness.bloc, entry), isTrue);
    expect(pendingStampTool.value, isNull);
    expect(completeStampPick(harness.bloc, entry), isFalse);
  });
}
