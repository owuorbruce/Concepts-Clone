import 'dart:ui';

import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/views/amaze/shell.dart';
import 'package:butterfly/views/amaze/tool_wheel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolWheelGeometry', () {
    const geometry = ToolWheelGeometry();

    test('starts at the top and goes clockwise', () {
      final top = geometry.slotCenter(0);
      final right = geometry.slotCenter(2);
      final bottom = geometry.slotCenter(4);
      expect(top.dx, closeTo(0, 0.001));
      expect(top.dy, closeTo(-geometry.slotDistance, 0.001));
      expect(right.dx, closeTo(geometry.slotDistance, 0.001));
      expect(bottom.dy, closeTo(geometry.slotDistance, 0.001));
    });

    test('keeps every slot between the hub and the rim', () {
      for (var slot = 0; slot < kToolWheelSlots; slot++) {
        final distance = geometry.slotCenter(slot).distance;
        final half = geometry.slotSize / 2;
        expect(distance - half, greaterThan(geometry.hubRadius));
        expect(distance + half, lessThan(geometry.radius));
      }
    });

    test('slots do not overlap', () {
      final first = geometry.slotCenter(0);
      final second = geometry.slotCenter(1);
      expect((first - second).distance, greaterThan(geometry.slotSize));
    });
  });

  group('tool wheel pages', () {
    test('always has at least one page', () {
      expect(toolWheelPageCount(0), 1);
      expect(toolWheelPageCount(kToolWheelSlots), 1);
      expect(toolWheelPageCount(kToolWheelSlots + 1), 2);
    });

    test('lists the tools of a page and clamps the page', () {
      expect(toolWheelPage(6, 0), [0, 1, 2, 3, 4, 5]);
      expect(toolWheelPage(10, 1), [8, 9]);
      expect(toolWheelPage(10, 5), [8, 9]);
      expect(toolWheelPage(10, -1), [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(toolWheelPage(0, 0), isEmpty);
    });

    test('finds the page of a tool', () {
      expect(toolWheelPageOf(0), 0);
      expect(toolWheelPageOf(kToolWheelSlots), 1);
      expect(toolWheelPageOf(-3), 0);
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
      clampToolWheelPosition(const Offset(120, 80), size, bounds),
      const Offset(120, 80),
    );
    expect(
      clampToolWheelPosition(const Offset(50, 50), size, const Size(60, 60)),
      Offset.zero,
    );
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
