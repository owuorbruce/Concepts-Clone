import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('densifyPenPoints', () {
    test('limits segment length and interpolates pressure', () {
      const points = [PathPoint(0, 0, 0.2), PathPoint(10, 0, 0.8)];
      final result = densifyPenPoints(points, 3);

      expect(result.first, same(points.first));
      expect(result.last, same(points.last));
      for (var i = 1; i < result.length; i++) {
        expect(
          (Offset(result[i].x, result[i].y) -
                  Offset(result[i - 1].x, result[i - 1].y))
              .distance,
          lessThanOrEqualTo(3),
        );
      }
      expect(result[1].pressure, closeTo(0.35, 1e-10));
      expect(result[2].pressure, closeTo(0.5, 1e-10));
      expect(result[3].pressure, closeTo(0.65, 1e-10));
    });

    test('keeps every original point in order as the same object', () {
      const points = [PathPoint(0, 0), PathPoint(5, 0), PathPoint(10, 0)];
      final result = densifyPenPoints(points, 2);
      var lastIndex = -1;
      for (final point in points) {
        final index = result.indexWhere(
          (candidate) => identical(candidate, point),
        );
        expect(index, greaterThan(lastIndex));
        lastIndex = index;
      }
    });

    test('returns input unchanged for short input and bad max segment', () {
      const empty = <PathPoint>[];
      const one = [PathPoint(0, 0)];
      const points = [PathPoint(0, 0), PathPoint(10, 0)];
      expect(densifyPenPoints(empty, 1), same(empty));
      expect(densifyPenPoints(one, 1), same(one));
      for (final value in [0.0, -1.0, double.nan, double.infinity]) {
        expect(densifyPenPoints(points, value), same(points));
      }
    });
  });

  group('nudgePenPoints', () {
    test('uses quadratic falloff and preserves pressure', () {
      const points = [PathPoint(0, 0, 0.2), PathPoint(5, 0, 0.7)];
      final result = nudgePenPoints(
        points,
        Offset.zero,
        10,
        const Offset(8, 4),
      )!;

      expect(result[0].x, 8);
      expect(result[0].y, 4);
      expect(result[0].pressure, points[0].pressure);
      expect(result[1].x, 7);
      expect(result[1].y, 1);
      expect(result[1].pressure, points[1].pressure);
    });

    test('keeps points at and beyond radius as the same objects', () {
      const points = [PathPoint(10, 0), PathPoint(11, 0)];
      final result = nudgePenPoints(
        points,
        Offset.zero,
        10,
        const Offset(5, 0),
      );
      expect(result, isNull);

      const mixed = [PathPoint(0, 0), PathPoint(10, 0), PathPoint(11, 0)];
      final mixedResult = nudgePenPoints(
        mixed,
        Offset.zero,
        10,
        const Offset(5, 0),
      )!;
      expect(mixedResult[1], same(mixed[1]));
      expect(mixedResult[2], same(mixed[2]));
    });

    test('returns null for invalid inputs', () {
      const points = [PathPoint(0, 0)];
      for (final radius in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          nudgePenPoints(points, Offset.zero, radius, Offset.zero),
          isNull,
        );
      }
      expect(
        nudgePenPoints(points, const Offset(double.nan, 0), 10, Offset.zero),
        isNull,
      );
      expect(
        nudgePenPoints(
          points,
          Offset.zero,
          10,
          const Offset(double.infinity, 0),
        ),
        isNull,
      );
    });
  });

  test('Nudge has its own handler; plain hand tools are unchanged', () {
    expect(
      Handler.fromTool(Tool.hand(displayIcon: 'amaze.nudge')),
      isA<NudgeHandler>(),
    );
    expect(Handler.fromTool(Tool.hand()), isNot(isA<NudgeHandler>()));
  });

  test('the library offers Nudge with its display icon', () {
    expect(LibraryEntry.nudge.available, isTrue);
    expect(LibraryEntry.nudge.createTool()!.displayIcon, kNudgeDisplayIcon);
  });
}
