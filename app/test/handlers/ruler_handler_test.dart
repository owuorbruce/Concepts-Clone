import 'dart:ui';
import 'dart:math';

import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:material_ui/material_ui.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ruler bounds follow a rotated viewport', () {
    final handler = RulerHandler(RulerTool());
    const camera = CameraTransform(1, Offset(10, 20), 2, pi / 2);
    final center = camera.globalToLocal(
      handler.getRect(const Size(800, 600), camera).center,
    );
    expect(center.dx, closeTo(400, 1e-7));
    expect(center.dy, closeTo(300, 1e-7));
  });

  test('default ruler pivots around the center of the viewport', () {
    final handler = RulerHandler(RulerTool());

    expect(
      handler.getRect(const Size(800, 600)).center,
      const Offset(400, 300),
    );
  });

  test('transformed ruler pivots around the center of the viewport', () {
    final handler = RulerHandler(RulerTool());
    const transform = CameraTransform(1, Offset(10, 20), 2);

    expect(
      handler.getRect(const Size(800, 600), transform).center,
      const Offset(210, 170),
    );
  });

  test('ruler rotation snaps to horizontal and vertical quarter turns', () {
    expect(snapRulerRotation(4), 0);
    expect(snapRulerRotation(87), 90);
    expect(snapRulerRotation(184), 180);
    expect(snapRulerRotation(273), 270);
    expect(snapRulerRotation(356), 0);
    expect(snapRulerRotation(-3), 0);
  });

  test('ruler rotation keeps angles outside the snap threshold', () {
    expect(snapRulerRotation(6), 6);
    expect(snapRulerRotation(84), 84);
    expect(snapRulerRotation(96), 96);
    expect(snapRulerRotation(-6), 354);
  });

  test('ruler foreground contrasts with its background when unset', () {
    final ruler = RulerTool();

    expect(resolveRulerForegroundColor(ruler, Colors.black), Colors.white);
    expect(resolveRulerForegroundColor(ruler, Colors.white), Colors.black);
    expect(
      resolveRulerForegroundColor(ruler, const Color(0xFF00695C)),
      Colors.white,
    );
    expect(
      resolveRulerForegroundColor(ruler, const Color(0xFFFFF59D)),
      Colors.black,
    );
  });

  test('ruler foreground uses the configured color', () {
    final ruler = RulerTool(foreground: const SRGBColor(0xFF123456));

    expect(
      resolveRulerForegroundColor(ruler, Colors.black),
      const Color(0xFF123456),
    );
  });

  test('6: a 13° twist snaps to 15°, and 60° and mirrors snap too', () {
    expect(snapRulerRotation(13), closeTo(15, 1e-6));
    expect(snapRulerRotationResult(13).snapped, isTrue);
    expect(snapRulerRotation(58), closeTo(60, 1e-6));
    expect(snapRulerRotation(122), closeTo(120, 1e-6));
    expect(snapRulerRotation(197), closeTo(195, 1e-6));
    // 75° is not a snap angle.
    expect(snapRulerRotation(74), 74);
    expect(snapRulerRotationResult(74).snapped, isFalse);
  });

  test('6: strokes near the edge are projected onto it', () {
    final handler = RulerHandler(RulerTool());
    const viewport = Size(800, 600);
    final rect = handler.getRect(viewport);
    // A stroke starting 15 px above the top edge and wobbling runs flat
    // along the edge, like a brush stroke drawn freehand.
    final stroke = [
      for (var i = 0; i < 10; i++)
        Offset(200 + i * 30.0, rect.top - 15 + sin(i.toDouble()) * 6),
    ];
    for (final point in stroke) {
      final projected = handler.getPointerPosition(point, viewport);
      expect(projected.dy, closeTo(rect.top, 1e-9));
      expect(projected.dx, closeTo(point.dx, 1e-9));
    }
    // Farther than 24 px it is left alone.
    final far = Offset(300, rect.top - 30);
    expect(handler.getPointerPosition(far, viewport), far);
  });

  test('6: projection follows a rotated ruler', () {
    final handler = RulerHandler(RulerTool())..setRotation(30);
    const viewport = Size(800, 600);
    final rect = handler.getRect(viewport);
    final pivot = rect.center;
    final angle = 30 * pi / 180;
    Offset turn(Offset p, double a) {
      final d = p - pivot;
      return pivot +
          Offset(d.dx * cos(a) - d.dy * sin(a), d.dx * sin(a) + d.dy * cos(a));
    }

    final point = turn(Offset(pivot.dx + 50, rect.bottom + 10), angle);
    final projected = handler.getPointerPosition(point, viewport);
    final local = turn(projected, -angle);
    expect(local.dy, closeTo(rect.bottom, 1e-6));
  });
}
