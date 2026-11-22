import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/views/amaze/tool_slots.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tool_harness.dart';

const _red = SRGBColor(0xFFE02020);
const _blue = SRGBColor(0xFF2050E0);

void main() {
  testWidgets('9: tapping creates a label with the wheel size and color', (
    tester,
  ) async {
    final harness = ToolHarness();
    await tester.runAsync(harness.setUp);
    addTearDown(() => tester.runAsync(harness.dispose));
    await harness.pumpContext(tester);
    final handler = LabelHandler(
      LabelTool(foreground: _red, scale: 3, id: 'text-tool'),
    );
    await tester.runAsync(
      () => handler.create(harness.context, const Offset(200, 200)),
    );
    expect(handler.isCurrentlyEditing, isTrue);
    handler.updateEditingValue(
      const TextEditingValue(
        text: 'Hello',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    // The wheel turns the size up and picks another color while typing.
    handler.data = handler.data.copyWith(foreground: _blue, scale: 6);
    await tester.runAsync(harness.settle);
    // A tap away finishes the text in one undo step.
    await tester.runAsync(() async {
      handler.onTapUp(
        TapUpDetails(
          kind: PointerDeviceKind.touch,
          localPosition: const Offset(600, 500),
        ),
        harness.context,
      );
      await harness.settle();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(harness.createEvents, 1);
    final element = harness.created.single.single as TextElement;
    expect(element.foreground, _blue);
    expect(element.scale, closeTo(6, 1e-9));
    expect(element.area.paragraph.text, 'Hello');
    // It stays selected so it can be moved at once.
    final temporary = harness.controller.toolCubit.state.temporaryHandler;
    expect(temporary, isA<SelectHandler>());
    expect((temporary as SelectHandler).getSelectionRect(), isNotNull);
    handler.dispose(harness.bloc);
  });

  test('the wheel reads and writes the size of text', () {
    final tool = LabelTool(scale: 2);
    expect(tool.readAdjustment(ToolAdjustment.size), 2);
    final bigger = tool.writeAdjustment(ToolAdjustment.size, 5) as LabelTool;
    expect(bigger.scale, 5);
  });
}
