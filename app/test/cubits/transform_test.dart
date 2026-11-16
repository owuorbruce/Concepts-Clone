import 'dart:math';

import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/views/zoom.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CameraTransform rotation', () {
    test('converts between screen and document coordinates', () {
      const transform = CameraTransform(1, Offset(10, 20), 2, pi / 3);
      const documentPoint = Offset(35, -12);

      final screenPoint = transform.globalToLocal(documentPoint);
      final restored = transform.localToGlobal(screenPoint);

      expect(restored.dx, closeTo(documentPoint.dx, 1e-9));
      expect(restored.dy, closeTo(documentPoint.dy, 1e-9));
    });

    test('keeps the gesture focal point fixed while rotating', () {
      const transform = CameraTransform(1, Offset(10, 20), 2, pi / 6);
      const focalPoint = Offset(240, 120);
      final documentPoint = transform.localToGlobal(focalPoint);

      final rotated = transform.withRotation(pi / 2, focalPoint);

      final restored = rotated.localToGlobal(focalPoint);
      expect(restored.dx, closeTo(documentPoint.dx, 1e-9));
      expect(restored.dy, closeTo(documentPoint.dy, 1e-9));
    });

    test('keeps the gesture focal point fixed while zooming', () {
      const transform = CameraTransform(1, Offset(10, 20), 2, pi / 4);
      const focalPoint = Offset(240, 120);
      final documentPoint = transform.localToGlobal(focalPoint);

      final zoomed = transform.withSize(4, focalPoint);

      final restored = zoomed.localToGlobal(focalPoint);
      expect(restored.dx, closeTo(documentPoint.dx, 1e-9));
      expect(restored.dy, closeTo(documentPoint.dy, 1e-9));
    });

    test('uses all four corners for a rotated viewport', () {
      const transform = CameraTransform(1, Offset.zero, 1, pi / 4);
      const viewport = Rect.fromLTWH(0, 0, 100, 50);
      final bounds = transform.localToGlobalRect(viewport);
      final corners = [
        viewport.topLeft,
        viewport.topRight,
        viewport.bottomLeft,
        viewport.bottomRight,
      ].map(transform.localToGlobal);

      expect(bounds.left, closeTo(corners.map((e) => e.dx).reduce(min), 1e-9));
      expect(bounds.top, closeTo(corners.map((e) => e.dy).reduce(min), 1e-9));
      expect(bounds.right, closeTo(corners.map((e) => e.dx).reduce(max), 1e-9));
      expect(
        bounds.bottom,
        closeTo(corners.map((e) => e.dy).reduce(max), 1e-9),
      );
    });
  });

  group('CameraTransform friction', () {
    test('starts the animation at the current position and size', () {
      const transform = CameraTransform(1, Offset(10, 20), 2);

      final sliding = transform.withFriction(const Offset(100, -50), 2);
      final friction = sliding.friction!;
      final animationStart = sliding.withFrictionless(
        friction.beginOffset,
        friction.beginSize,
      );

      expect(animationStart.position, transform.position);
      expect(animationStart.size, transform.size);
    });
  });

  group('Endless zoom range', () {
    const transform = CameraTransform(1, Offset(10, 20), 2);

    test('withSize clamps to the endless range', () {
      expect(kMinZoom, 1e-6);
      expect(kMaxZoom, 1000);
      expect(transform.withSize(1e-9).size, kMinZoom);
      expect(transform.withSize(0).size, kMinZoom);
      expect(transform.withSize(-5).size, kMinZoom);
      expect(transform.withSize(1e9).size, kMaxZoom);
      expect(transform.withSize(1e-5).size, 1e-5);
      expect(transform.withSize(500).size, 500);
    });

    test('NaN and infinite sizes keep the current size', () {
      for (final size in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final result = transform.withSize(size, const Offset(30, 40));
        expect(result.size, transform.size);
        expect(result.position, transform.position);
      }
      expect(
        transform.withFriction(Offset.zero, double.nan).size,
        transform.size,
      );
    });

    for (final zoom in [1e-4, 1.0, 1000.0]) {
      test('zooming to $zoom keeps the focal point fixed', () {
        const start = CameraTransform(1, Offset(123456.7, -98765.4), 0.37);
        const focal = Offset(412, 233);
        final documentPoint = start.localToGlobal(focal);

        final zoomed = start.withSize(zoom, focal);

        expect(zoomed.size, zoom);
        final screen = zoomed.globalToLocal(documentPoint);
        expect(screen.dx, closeTo(focal.dx, 0.5));
        expect(screen.dy, closeTo(focal.dy, 0.5));
      });
    }

    test('fit-to-area reaches 1e-5 and 500', () async {
      final cubit = TransformCubit(1);
      cubit.teleportToArea(
        const Area(width: 1e8, height: 1e8, position: Point(0, 0)),
        const Size(1000, 1000),
      );
      expect(cubit.state.size, closeTo(1e-5, 1e-12));
      cubit.teleportToArea(
        const Area(width: 2, height: 2, position: Point(5, 5)),
        const Size(1000, 1000),
      );
      expect(cubit.state.size, closeTo(500, 1e-9));
      await cubit.close();
    });

    test('waypoints reach 1e-5 and 500', () async {
      final cubit = TransformCubit(1);
      cubit.teleportToWaypoint(const Waypoint('far', Point(1e7, 1e7), 1e-5));
      expect(cubit.state.size, 1e-5);
      cubit.teleportToWaypoint(const Waypoint('near', Point(3, 4), 500));
      expect(cubit.state.size, 500);
      await cubit.close();
    });

    test('a fling reaches 1e-5 and 500 without stopping at 0.1 or 10', () {
      // The fling's scale velocity is relative: ln(factor) * -ln(drag).
      final dragLog = -log(kDrag);
      final out = const CameraTransform(
        1,
        Offset.zero,
        1e-4,
      ).withFriction(Offset.zero, log(0.1) * dragLog);
      expect(out.size, closeTo(1e-5, 1e-8));

      final inward = const CameraTransform(
        1,
        Offset.zero,
        100,
      ).withFriction(Offset.zero, log(5) * dragLog);
      expect(inward.size, closeTo(500, 0.5));
    });
  });

  group('Zoom display', () {
    test('formats percentages with sensible precision', () {
      expect(formatZoomPercent(0.0001), '0.0001');
      expect(formatZoomPercent(0.05), '0.05');
      expect(formatZoomPercent(0.5), '0.5');
      expect(formatZoomPercent(1.5), '1.5');
      expect(formatZoomPercent(12), '12');
      expect(formatZoomPercent(100), '100');
      expect(formatZoomPercent(250), '250');
      expect(formatZoomPercent(50000), '50,000');
      expect(formatZoomPercent(100000), '100,000');
    });

    test('typed values keep enough decimals', () {
      expect(zoomFractionDigits(0.0001), greaterThanOrEqualTo(4));
      expect(zoomFractionDigits(0.05), greaterThanOrEqualTo(2));
      expect(zoomFractionDigits(250), 0);
    });
  });
}
