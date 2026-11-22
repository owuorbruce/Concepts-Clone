import 'dart:math';
import 'dart:ui';

import 'package:butterfly/brushes/dynamics.dart' show stableHash;
import 'package:butterfly/brushes/stamp_engine.dart' show kBrushSeedKey;
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tool.canvasAction', () {
    test('round-trips through JSON with its defaults', () {
      final tool = Tool.canvasAction(kind: CanvasActionKind.nudge);
      final json = tool.toJson();
      final read = Tool.fromJson(json) as CanvasActionTool;
      expect(read.kind, CanvasActionKind.nudge);
      expect(read.radius, 60);
      expect(read.strength, 0.6);
      final empty = Tool.fromJson({'type': 'canvasAction'});
      expect((empty as CanvasActionTool).kind, CanvasActionKind.rotate);
    });

    test('each kind has its own handler and category', () {
      Handler of(CanvasActionKind kind) =>
          Handler.fromTool(Tool.canvasAction(kind: kind));
      expect(of(CanvasActionKind.rotate), isA<RotateViewHandler>());
      expect(of(CanvasActionKind.zoom), isA<ZoomViewHandler>());
      expect(of(CanvasActionKind.nudge), isA<CanvasNudgeHandler>());
      expect(of(CanvasActionKind.slice), isA<CanvasSliceHandler>());
      expect(
        Tool.canvasAction(kind: CanvasActionKind.zoom).category,
        ToolCategory.action,
      );
      expect(
        Tool.canvasAction(kind: CanvasActionKind.slice).category,
        ToolCategory.surface,
      );
    });

    test('the library builds them', () {
      for (final (entry, kind) in [
        (LibraryEntry.rotate, CanvasActionKind.rotate),
        (LibraryEntry.zoom, CanvasActionKind.zoom),
        (LibraryEntry.nudge, CanvasActionKind.nudge),
        (LibraryEntry.slice, CanvasActionKind.slice),
      ]) {
        final tool = entry.createTool()! as CanvasActionTool;
        expect(tool.kind, kind);
        expect(libraryEntryOf(tool), entry);
      }
    });
  });

  group('rotate', () {
    const viewport = Size(800, 600);
    final center = viewport.center(Offset.zero);

    test('a quarter-turn drag around the center turns the view by π/2', () {
      const start = CameraTransform();
      // Sweep from right of the center to below it, in small steps.
      var sweep = 0.0;
      var last = center + const Offset(200, 0);
      for (var i = 1; i <= 30; i++) {
        final angle = i / 30 * pi / 2;
        final next = center + Offset(cos(angle), sin(angle)) * 200;
        sweep += sweptAngle(center, last, next);
        last = next;
      }
      final result = rotateViewAround(start, center, sweep);
      expect(result.rotation, closeTo(pi / 2, 0.01));
      // The screen center keeps showing the same canvas point.
      expect(
        (result.localToGlobal(center) - start.localToGlobal(center)).distance,
        lessThan(1e-6),
      );
    });

    test('snaps within 5° of a quarter turn, not further', () {
      const start = CameraTransform();
      final near = rotateViewAround(start, center, pi / 2 - 4 * pi / 180);
      expect(near.rotation, closeTo(pi / 2, 1e-9));
      final far = rotateViewAround(start, center, pi / 2 - 8 * pi / 180);
      expect(far.rotation, closeTo(pi / 2 - 8 * pi / 180, 1e-9));
      expect(snapViewRotation(pi - 0.02), closeTo(pi, 1e-9));
      expect(snapViewRotation(double.nan), 0);
    });

    test('a double-tap animates back to 0', () {
      final taps = DoubleTapTracker();
      taps.down(const Offset(10, 10), Duration.zero);
      expect(
        taps.up(const Offset(11, 10), const Duration(milliseconds: 60)),
        isFalse,
      );
      taps.down(const Offset(12, 11), const Duration(milliseconds: 160));
      expect(
        taps.up(const Offset(12, 11), const Duration(milliseconds: 220)),
        isTrue,
      );

      final turned = const CameraTransform().withRotation(1.2, center);
      final halfway = rotationResetFrame(turned, center, 0.5);
      expect(halfway.rotation, closeTo(0.6, 1e-9));
      expect(rotationResetFrame(turned, center, 1).rotation, 0);
    });

    test('a slow second tap or a drag is not a double-tap', () {
      final taps = DoubleTapTracker();
      taps.down(Offset.zero, Duration.zero);
      taps.up(Offset.zero, const Duration(milliseconds: 50));
      taps.down(Offset.zero, const Duration(milliseconds: 600));
      expect(taps.up(Offset.zero, const Duration(milliseconds: 650)), isFalse);
      taps.down(Offset.zero, const Duration(milliseconds: 700));
      expect(
        taps.up(const Offset(80, 0), const Duration(milliseconds: 750)),
        isFalse,
      );
    });
  });

  group('zoom', () {
    test('a 200 px upward drag doubles the zoom around its start', () {
      const start = CameraTransform(1, Offset(120, -40), 1.5, 0.3);
      const anchor = Offset(300, 200);
      final result = zoomViewAround(start, anchor, -200);
      expect(result.size, closeTo(3, 1e-9));
      final fixed = start.localToGlobal(anchor);
      final moved = result.globalToLocal(fixed);
      expect((moved - anchor).distance, lessThanOrEqualTo(0.5));
      expect(zoomViewAround(start, anchor, 200).size, closeTo(0.75, 1e-9));
    });

    test('stays within the zoom limits', () {
      const start = CameraTransform(1, Offset.zero, kMaxZoom);
      expect(zoomViewAround(start, Offset.zero, -2000).size, kMaxZoom);
    });

    test('a double-tap goes to 100 % around the tap', () {
      const from = CameraTransform(1, Offset(10, 10), 4);
      const tap = Offset(50, 60);
      final result = zoomResetFrame(from, tap, 1, 1);
      expect(result.size, 1);
      expect(
        (result.globalToLocal(from.localToGlobal(tap)) - tap).distance,
        lessThan(1e-6),
      );
    });
  });

  group('nudge', () {
    const strength = 0.6;
    const radius = 40.0;

    test('moves points by delta × strength × (1 − d/R)²', () {
      const points = [
        PathPoint(0, 0), // at the pointer
        PathPoint(radius / 2, 0), // at R/2
        PathPoint(radius * 1.5, 0), // beyond R
      ];
      final result = nudgeStep(
        points,
        Offset.zero,
        radius,
        const Offset(0, 100),
        strength,
      )!;
      expect(result[0].y, closeTo(100 * strength, 1e-9));
      expect(result[1].y, closeTo(100 * strength / 4, 1e-9));
      expect(result[2], same(points[2]));
    });

    test('bends a long straight line smoothly after resampling', () {
      const line = [PathPoint(-200, 0), PathPoint(200, 0)];
      final dense = densifyPenPoints(line, radius / 4);
      final result = nudgeStep(
        dense,
        Offset.zero,
        radius,
        const Offset(0, 10),
        strength,
      )!;
      // Neighbouring points never jump more than the falloff allows.
      for (var i = 1; i < result.length; i++) {
        expect((result[i].y - result[i - 1].y).abs(), lessThan(10 * strength));
      }
      expect(result.map((p) => p.y).reduce(max), closeTo(6, 1e-9));
    });

    test('a zero strength or no nearby points changes nothing', () {
      const points = [PathPoint(0, 0), PathPoint(5, 0)];
      expect(
        nudgeStep(points, Offset.zero, radius, const Offset(1, 1), 0),
        isNull,
      );
      expect(
        nudgeStep(
          points,
          const Offset(500, 500),
          radius,
          const Offset(1, 1),
          strength,
        ),
        isNull,
      );
    });

    test('walls, rooms and non-pen elements are skipped', () {
      PenElement pen([Map<String, dynamic> extra = const {}]) => PenElement(
        id: 'p',
        points: const [PathPoint(0, 0), PathPoint(1, 1)],
        extra: extra,
      );
      expect(isEditablePenStroke(pen()), isTrue);
      expect(
        isEditablePenStroke(
          pen({
            kWallExtraKey: {'id': 'w'},
          }),
        ),
        isFalse,
      );
      expect(
        isEditablePenStroke(
          pen({
            kRoomExtraKey: {'id': 'r'},
          }),
        ),
        isFalse,
      );
      expect(isEditablePenStroke(ShapeElement(id: 't')), isFalse);
    });
  });

  group('slice', () {
    // An S-curve: left along the top, down, right, down, left again.
    final sCurve = PenElement(
      id: 's',
      points: const [
        PathPoint(20, 0),
        PathPoint(0, 0),
        PathPoint(0, 20),
        PathPoint(20, 20),
        PathPoint(20, 40),
        PathPoint(0, 40),
      ],
      property: const PenProperty(
        brush: 'amaze.marker',
        brushVersion: 1,
        strokeWidth: 7,
        paint: ElementPaint.solid(color: SRGBColor(0xffcc2200)),
      ),
      collection: 'c',
      extra: const {'note': 1},
    );

    test('a line crossing the S-curve twice makes 3 pieces', () {
      var next = 0;
      final changes = sliceElements(
        [sCurve],
        // Down through the top and the middle bar: two crossings.
        const [Offset(5, -5), Offset(5, 25)],
        newId: () => 'n${next++}',
      );
      // One entry: one ElementsChanged, one undo step back to the original.
      expect(changes.keys, ['s']);
      final pieces = changes['s']!.cast<PenElement>();
      expect(pieces, hasLength(3));
      expect(pieces.map((p) => p.id), ['n0', 'n1', 'n2']);
      for (var i = 1; i < pieces.length; i++) {
        final end = pieces[i - 1].points.last;
        final start = pieces[i].points.first;
        expect(end.x, start.x);
        expect(end.y, start.y);
      }
      for (final piece in pieces) {
        expect(piece.points.length, greaterThanOrEqualTo(2));
        expect(piece.property.brush, 'amaze.marker');
        expect(piece.property.brushVersion, 1);
        expect(piece.property.strokeWidth, 7);
        expect(piece.property.paint, sCurve.property.paint);
        expect(piece.collection, 'c');
        // The pieces keep the stroke's extra and its texture seed.
        expect(piece.extra, {'note': 1, kBrushSeedKey: stableHash('s')});
      }
    });

    test('a cut across nothing changes nothing', () {
      expect(
        sliceElements([sCurve], const [Offset(100, 100), Offset(200, 120)]),
        isEmpty,
      );
    });

    test('walls are not cut', () {
      final wall = sCurve.copyWith(
        extra: {
          kWallExtraKey: {'id': 'w'},
        },
      );
      expect(
        sliceElements([wall], const [Offset(5, -5), Offset(5, 25)]),
        isEmpty,
      );
    });
  });
}
