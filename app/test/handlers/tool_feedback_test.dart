import 'dart:math';
import 'dart:ui';

import 'package:butterfly/handlers/tool_feedback/tool_feedback.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';

double _deg(double degrees) => degrees * pi / 180;

List<Offset> _tap(Offset center, double radius) =>
    Rect.fromCircle(center: center, radius: radius).toPolygonPoints();

extension on Rect {
  List<Offset> toPolygonPoints() => [
    topLeft,
    topRight,
    bottomRight,
    bottomLeft,
  ];
}

PathHitCalculator _line(double width) {
  final points = [
    for (var x = 0; x <= 100; x += 10) PathPoint(x.toDouble(), 0),
  ];
  return PathHitCalculator(
    const Rect.fromLTRB(0, 0, 100, 0),
    points,
    0,
    strokeWidth: width,
  );
}

void main() {
  group('snapAngle', () {
    test('snaps 13° to 15° and leaves 9° alone', () {
      final snapped = snapAngle(_deg(13));
      expect(snapped.snapped, isTrue);
      expect(snapped.angle, closeTo(_deg(15), 1e-9));
      final free = snapAngle(_deg(9));
      expect(free.snapped, isFalse);
      expect(free.angle, closeTo(_deg(9), 1e-9));
    });

    test('snapAngleTo counts mirrored directions', () {
      final result = snapAngleTo(_deg(178), [0]);
      expect(result.snapped, isTrue);
      expect(result.angle, closeTo(pi, 1e-9));
    });
  });

  group('snapToPoint', () {
    test('picks the nearest point within 12 px', () {
      final result = snapToPoint(const Offset(100, 100), const [
        Offset(110, 100),
        Offset(105, 103),
        Offset(200, 200),
      ]);
      expect(result.snapped, isTrue);
      expect(result.point, const Offset(105, 103));
    });

    test('ignores points farther than 12 px', () {
      final result = snapToPoint(const Offset(0, 0), const [Offset(13, 0)]);
      expect(result.snapped, isFalse);
      expect(result.point, Offset.zero);
    });

    test('tolerance scales with zoom', () {
      // At 4× zoom, 12 screen px are 3 document units.
      final result = snapToPoint(Offset.zero, const [
        Offset(4, 0),
      ], tolerance: kSnapPointTolerance / 4);
      expect(result.snapped, isFalse);
    });
  });

  group('HoldToPerfect', () {
    testWidgets('fires after 450 ms of stillness', (tester) async {
      var fired = 0;
      final hold = HoldToPerfect(onHold: () => fired++);
      hold.move(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 200));
      // Drifting less than 4 px keeps the wait going.
      hold.move(const Offset(12, 11));
      await tester.pump(const Duration(milliseconds: 240));
      expect(fired, 0);
      await tester.pump(const Duration(milliseconds: 20));
      expect(fired, 1);
      expect(hold.fired, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(fired, 1);
      hold.cancel();
    });

    testWidgets('does not fire while moving', (tester) async {
      var fired = 0;
      final hold = HoldToPerfect(onHold: () => fired++);
      for (var i = 0; i < 20; i++) {
        hold.move(Offset(i * 10.0, 0));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(fired, 0);
      hold.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(fired, 0);
    });
  });

  group('SnapHaptics', () {
    test('ticks once per engage', () {
      final haptics = SnapHaptics(enabled: false);
      haptics.update(true);
      haptics.update(true);
      haptics.update(true);
      expect(haptics.ticks, 1);
      haptics.update(false);
      haptics.update(true);
      expect(haptics.ticks, 2);
    });
  });

  group('width-aware hit testing', () {
    test('a 40-unit-wide stroke is hit 15 units from its centerline', () {
      final line = _line(40);
      final tap = _tap(const Offset(50, 15), 0.5);
      expect(line.hitPolygonAt(tap), isTrue);
      expect(line.hitPolygon(tap), isTrue);
      // Beyond half the width it misses.
      expect(line.hitPolygonAt(_tap(const Offset(50, 25), 0.5)), isFalse);
    });

    test('a 1-unit stroke is hit within 6 screen px', () {
      final line = _line(1);
      // At zoom 1, 5.5 units are 5.5 screen px.
      expect(line.hitPolygonAt(_tap(const Offset(50, 5.5), 0)), isTrue);
      expect(line.hitPolygonAt(_tap(const Offset(50, 7), 0)), isFalse);
      // At zoom 2, 6 screen px are 3 units.
      expect(
        line.hitPolygonAt(_tap(const Offset(50, 2.8), 0), zoom: 2),
        isTrue,
      );
      expect(
        line.hitPolygonAt(_tap(const Offset(50, 3.5), 0), zoom: 2),
        isFalse,
      );
    });

    test('a single tap point near a stroke hits', () {
      final line = _line(1);
      expect(line.hitPolygonAt([const Offset(30, 4)]), isTrue);
      expect(line.hitPolygonAt([const Offset(30, 9)]), isFalse);
    });

    test('other hit calculators ignore the zoom', () {
      final calculator = DefaultHitCalculator(
        const Rect.fromLTWH(0, 0, 10, 10),
        0,
      );
      expect(calculator.hitPolygonAt([const Offset(5, 5)], zoom: 3), isTrue);
      expect(calculator.hitPolygonAt([const Offset(15, 5)], zoom: 3), isFalse);
    });
  });

  group('formatting', () {
    test('lengths use px or feet and inches', () {
      expect(formatLength(120.4), '120 px');
      expect(formatLength(96 * 30, MeasureUnits.feetInches), "2' 6\"");
      expect(formatAngle(-pi / 4), '45°');
      expect(formatSize(100, 50), '100 × 50 px');
    });
  });
}
