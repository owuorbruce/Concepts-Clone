import 'dart:ui';

import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/views/amaze/shell.dart';
import 'package:butterfly/views/amaze/tool_slots.dart';
import 'package:butterfly/views/amaze/tool_wheel.dart';
import 'package:butterfly/views/amaze/wheel_prefs.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Tool _withId(Tool tool, String id) => tool.copyWith(id: id);

void main() {
  group('ToolWheelGeometry', () {
    const geometry = ToolWheelGeometry();

    List<(Offset, double)> ringButtons() => [
      for (var slot = 0; slot < kToolSlotCount; slot++)
        (geometry.slotCenter(slot), geometry.slotSize / 2),
      (geometry.undoCenter, geometry.historySize / 2),
      (geometry.redoCenter, geometry.historySize / 2),
    ];

    test('puts undo and redo at the bottom, outside the slots', () {
      expect(geometry.undoCenter.dy, greaterThan(geometry.radius / 2));
      expect(geometry.redoCenter.dy, greaterThan(geometry.radius / 2));
      expect(geometry.undoCenter.dx, lessThan(0));
      expect(geometry.redoCenter.dx, greaterThan(0));
    });

    test('keeps the outer ring buttons apart and inside the rim', () {
      final buttons = ringButtons();
      for (var i = 0; i < buttons.length; i++) {
        final (center, radius) = buttons[i];
        expect(center.distance + radius, lessThan(geometry.radius));
        expect(center.distance - radius, greaterThan(geometry.middleRadius));
        for (var j = i + 1; j < buttons.length; j++) {
          final (other, otherRadius) = buttons[j];
          final gap = (center - other).distance - radius - otherRadius;
          expect(gap, greaterThan(0), reason: 'buttons $i and $j overlap');
        }
      }
    });

    test('keeps adjustments clear of the slots and the center', () {
      for (final adjustment in ToolAdjustment.values) {
        final rect = Rect.fromCenter(
          center: geometry.adjustmentCenter(adjustment),
          width: geometry.adjustmentSize.width,
          height: geometry.adjustmentSize.height,
        );
        for (final (center, radius) in ringButtons()) {
          final closest = Offset(
            center.dx.clamp(rect.left, rect.right),
            center.dy.clamp(rect.top, rect.bottom),
          );
          expect((center - closest).distance, greaterThan(radius));
        }
        final nearest = Offset(
          0.0.clamp(rect.left, rect.right),
          0.0.clamp(rect.top, rect.bottom),
        );
        expect(nearest.distance, greaterThan(geometry.centerRadius));
      }
    });
  });

  group('tool slots', () {
    final tools = [
      _withId(Tool.select(), 'select'),
      _withId(Tool.undo(), 'undo'),
      _withId(Tool.pen(), 'pen'),
      _withId(Tool.redo(), 'redo'),
      _withId(Tool.eraser(), 'eraser'),
      _withId(Tool.hand(), 'hand'),
    ];

    test('skip undo and redo', () {
      expect(slotToolIndices(tools), [0, 2, 4, 5]);
    });

    test('hold at most eight tools', () {
      final many = [for (var i = 0; i < 12; i++) _withId(Tool.pen(), '$i')];
      expect(slotToolIndices(many), [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('move targets swap two slots with ToolReordered semantics', () {
      expect(slotMoveTarget(tools, 0, 1), ('select', 3));
      expect(slotMoveTarget(tools, 1, 0), ('pen', 0));
      expect(slotMoveTarget(tools, 3, 2), ('hand', 4));
      expect(slotMoveTarget(tools, 0, 4), isNull);
      expect(slotMoveTarget(tools, -1, 0), isNull);
    });

    test('the catalog offers tools but not undo or redo', () {
      final catalog = slotToolCatalog();
      expect(catalog, isNotEmpty);
      expect(catalog.whereType<UndoTool>(), isEmpty);
      expect(catalog.whereType<RedoTool>(), isEmpty);
      expect(catalog.whereType<PenTool>(), isNotEmpty);
      expect(catalog.whereType<ShapeTool>(), isNotEmpty);
    });
  });

  group('tool adjustments', () {
    test('only lists properties the tool has', () {
      expect(Tool.pen().adjustments, ToolAdjustment.values);
      expect(Tool.eraser().adjustments, [ToolAdjustment.size]);
      expect(Tool.laser().adjustments, [ToolAdjustment.size]);
      expect(Tool.hand().adjustments, isEmpty);
      expect(Tool.select().adjustments, isEmpty);
      final shape = Tool.shape(
        property: const ShapeProperty(shape: RectangleShape()),
      );
      expect(shape.adjustments, [ToolAdjustment.size, ToolAdjustment.opacity]);
    });

    test('opacity needs a solid paint', () {
      final tool = Tool.pen(
        property: const PenProperty(paint: ElementPaint.gradient()),
      );
      expect(tool.readAdjustment(ToolAdjustment.opacity), isNull);
      expect(tool.adjustments, [ToolAdjustment.size, ToolAdjustment.smoothing]);
    });

    test('writes the pen properties the renderer uses', () {
      final pen = Tool.pen() as PenTool;
      final wide = pen.writeAdjustment(ToolAdjustment.size, 12) as PenTool;
      expect(wide.property.strokeWidth, 12);
      final faded = pen.writeAdjustment(ToolAdjustment.opacity, 0.5) as PenTool;
      final paint = faded.property.paint as SolidElementPaint;
      expect(paint.color.a, 128);
      expect(paint.color.withValues(a: 255), pen.property.paint.previewColor);
      final smooth = pen.writeAdjustment(ToolAdjustment.smoothing, 0.9);
      expect((smooth as PenTool).property.smoothing, 0.9);
    });

    test('clamps to the range and keeps other tools unchanged', () {
      final pen = Tool.pen();
      final huge = pen.writeAdjustment(ToolAdjustment.size, 500) as PenTool;
      expect(huge.property.strokeWidth, 70);
      final eraser = Tool.eraser().writeAdjustment(ToolAdjustment.size, 0);
      expect((eraser as EraserTool).strokeWidth, 1);
      final hand = Tool.hand();
      expect(hand.writeAdjustment(ToolAdjustment.size, 10), same(hand));
    });

    test('formats values for the wheel', () {
      expect(formatAdjustment(ToolAdjustment.size, 5), '5.0');
      expect(formatAdjustment(ToolAdjustment.size, 12.4), '12');
      expect(formatAdjustment(ToolAdjustment.opacity, 0.5), '50%');
      expect(formatAdjustment(ToolAdjustment.smoothing, 1), '100%');
    });
  });

  test('clampToolWheelPosition keeps the wheel inside its bounds', () {
    const size = Size(100, 100);
    const bounds = Size(400, 300);
    expect(
      clampToolWheelPosition(const Offset(-20, 500), size, bounds),
      const Offset(0, 200),
    );
    expect(
      clampToolWheelPosition(const Offset(50, 50), size, const Size(60, 60)),
      Offset.zero,
    );
  });

  test('the wheel layout survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await loadToolWheelLayout()).mode, ToolWheelMode.wheel);
    await saveToolWheelLayout(
      const ToolWheelLayout(
        mode: ToolWheelMode.bar,
        position: Offset(0.25, 0.75),
        collapsed: true,
      ),
    );
    final loaded = await loadToolWheelLayout();
    expect(loaded.mode, ToolWheelMode.bar);
    expect(loaded.position, const Offset(0.25, 0.75));
    expect(loaded.collapsed, isTrue);
  });

  group('AmazeShellSettings', () {
    test('the classic flag wins over the aMaze flag', () {
      const settings = ButterflySettings(
        defaultTemplate: 'default',
        flags: [kAmazeShellFlag, kClassicEditorFlag],
      );
      expect(settings.usesAmazeShell, isFalse);
      expect(settings.usesFloatingEditor, isFalse);
    });

    test('the aMaze flag turns the shell on and the inline tools off', () {
      const settings = ButterflySettings(
        defaultTemplate: 'default',
        flags: [kAmazeShellFlag],
      );
      expect(settings.usesAmazeShell, isTrue);
      expect(settings.usesFloatingEditor, isTrue);
      expect(settings.usesInlineTools, isFalse);
    });

    test('follows the platform default without flags', () {
      const settings = ButterflySettings();
      expect(settings.usesAmazeShell, amazeShellIsDefault);
    });
  });
}
