import 'dart:ui';

import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('slice geometry', () {
    test('one crossing shares an exact point and interpolates pressure', () {
      const points = [PathPoint(0, 0, 0.2), PathPoint(100, 0, 0.8)];
      final pieces = splitPenPointsAtCut(points, [
        const Offset(50, -10),
        const Offset(50, 10),
      ])!;

      expect(pieces, hasLength(2));
      expect(pieces.map((piece) => piece.length), [2, 2]);
      expect(pieces.first.first, same(points.first));
      expect(pieces.last.last, same(points.last));
      expect(pieces.first.last, same(pieces.last.first));
      expect(pieces.first.last.x, closeTo(50, 1e-10));
      expect(pieces.first.last.y, closeTo(0, 1e-10));
      expect(pieces.first.last.pressure, closeTo(0.5, 1e-10));
    });

    test('two crossings across two stroke segments make three pieces', () {
      const points = [PathPoint(0, 0), PathPoint(50, 0), PathPoint(100, 0)];
      final pieces = splitPenPointsAtCut(points, [
        const Offset(25, -10),
        const Offset(25, 10),
        const Offset(75, 10),
        const Offset(75, -10),
      ])!;

      expect(pieces, hasLength(3));
      expect(pieces.first.last.x, closeTo(25, 1e-10));
      expect(pieces[1].first, same(pieces.first.last));
      expect(pieces[1].last.x, closeTo(75, 1e-10));
      expect(pieces.last.first, same(pieces[1].last));
    });

    test('two cut segments crossing one stroke segment stay ordered', () {
      const points = [PathPoint(0, 0), PathPoint(100, 0)];
      final pieces = splitPenPointsAtCut(points, [
        const Offset(75, -10),
        const Offset(75, 10),
        const Offset(25, 10),
        const Offset(25, -10),
      ])!;

      expect(pieces.map((piece) => piece.map((point) => point.x).toList()), [
        [0, 25],
        [25, 75],
        [75, 100],
      ]);
    });

    test('cut segments sharing a crossing do not duplicate the split', () {
      const points = [PathPoint(0, 0), PathPoint(100, 0)];
      final pieces = splitPenPointsAtCut(points, [
        const Offset(50, -10),
        const Offset(50, 0),
        const Offset(50, 10),
      ])!;

      expect(pieces, hasLength(2));
      expect(pieces.first.last, same(pieces.last.first));
    });

    test('a cut at an internal stroke vertex produces two valid pieces', () {
      const points = [PathPoint(0, 0), PathPoint(50, 0), PathPoint(100, 0)];
      final pieces = splitPenPointsAtCut(points, [
        const Offset(50, -10),
        const Offset(50, 10),
      ])!;

      expect(pieces, hasLength(2));
      expect(pieces.first, hasLength(2));
      expect(pieces.last, hasLength(2));
      expect(pieces.first.last, same(pieces.last.first));
    });

    test('no crossing, parallel, and collinear cuts do nothing', () {
      const points = [PathPoint(0, 0), PathPoint(100, 0)];
      for (final cut in [
        [const Offset(50, 5), const Offset(50, 10)],
        [const Offset(0, 5), const Offset(100, 5)],
        [const Offset(25, 0), const Offset(75, 0)],
      ]) {
        expect(splitPenPointsAtCut(points, cut), isNull);
      }
    });

    test('touching only the first or last stroke endpoint does nothing', () {
      const points = [PathPoint(0, 0), PathPoint(100, 0)];
      expect(
        splitPenPointsAtCut(points, [
          const Offset(0, -10),
          const Offset(0, 10),
        ]),
        isNull,
      );
      expect(
        splitPenPointsAtCut(points, [
          const Offset(100, -10),
          const Offset(100, 10),
        ]),
        isNull,
      );
    });

    test('rejects insufficient and non-finite coordinates', () {
      const points = [PathPoint(0, 0), PathPoint(100, 0)];
      const cut = [Offset(50, -10), Offset(50, 10)];
      expect(splitPenPointsAtCut([], cut), isNull);
      expect(splitPenPointsAtCut([points.first], cut), isNull);
      expect(splitPenPointsAtCut(points, []), isNull);
      expect(splitPenPointsAtCut(points, [Offset.zero]), isNull);
      expect(
        splitPenPointsAtCut([const PathPoint(double.nan, 0), points.last], cut),
        isNull,
      );
      expect(
        splitPenPointsAtCut(points, [
          const Offset(double.infinity, 0),
          cut.last,
        ]),
        isNull,
      );
    });
  });

  test('Slice has its own handler; other erasers are unchanged', () {
    expect(
      Handler.fromTool(Tool.eraser(displayIcon: 'amaze.slice')),
      isA<SliceHandler>(),
    );
    expect(Handler.fromTool(Tool.eraser()), isA<EraserHandler>());
  });

  test('the library makes the Slice display icon', () {
    expect(LibraryEntry.slice.createTool()!.displayIcon, kSliceDisplayIcon);
  });
}
