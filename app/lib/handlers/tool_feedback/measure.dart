import 'dart:math';

import 'package:butterfly/views/amaze/floor_plan/floor_plan.dart'
    show formatFeetInches;
import 'package:butterfly_api/butterfly_api.dart';
import 'package:material_ui/material_ui.dart';

import '../../cubits/transform.dart';
import '../../renderers/renderer.dart';
import 'snap.dart';

/// How lengths are shown in a [MeasureBubble].
enum MeasureUnits {
  /// Canvas units, shown as px.
  pixels,

  /// Feet and inches, as the floor plan uses them.
  feetInches,
}

/// The units of [page]: feet and inches when it holds floor plan walls,
/// otherwise px. Documents have no unit setting of their own.
MeasureUnits measureUnitsOf(DocumentPage? page) {
  if (page == null) return MeasureUnits.pixels;
  return _unitsCache[page] ??= _computeUnits(page);
}

final _unitsCache = Expando<MeasureUnits>('measureUnits');

MeasureUnits _computeUnits(DocumentPage page) {
  for (final layer in page.layers) {
    for (final element in layer.content) {
      if (element.extra.containsKey(kWallExtraKey)) {
        return MeasureUnits.feetInches;
      }
    }
  }
  return MeasureUnits.pixels;
}

/// [units] canvas units as a length.
String formatLength(double units, [MeasureUnits mode = MeasureUnits.pixels]) {
  return switch (mode) {
    MeasureUnits.feetInches => formatFeetInches(units),
    MeasureUnits.pixels => '${units.abs().round()} px',
  };
}

/// "w × h" in [mode].
String formatSize(
  double width,
  double height, [
  MeasureUnits mode = MeasureUnits.pixels,
]) {
  if (mode == MeasureUnits.pixels) {
    return '${width.abs().round()} × ${height.abs().round()} px';
  }
  return '${formatFeetInches(width)} × ${formatFeetInches(height)}';
}

/// [radians] as degrees, like `45°`.
String formatAngle(double radians) {
  final degrees = displayDegrees(radians);
  final rounded = (degrees * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) return '${rounded.round()}°';
  return '${rounded.toStringAsFixed(1)}°';
}

/// A length and an angle, like `120 px · 45°`.
String formatLengthAngle(
  Offset delta, [
  MeasureUnits mode = MeasureUnits.pixels,
]) => '${formatLength(delta.distance, mode)} · ${formatAngle(delta.direction)}';

/// [value] as a percent, like `125%`.
String formatPercent(double value) => '${(value * 100).round()}%';

/// What a [MeasureBubble] shows and where: [position] is in screen pixels
/// relative to the canvas.
typedef MeasureBubbleData = ({Offset position, String text});

/// A small label with a length, size, angle or percent next to the pointer.
/// Drawn in screen space, so it keeps its size and stays upright at any
/// view.
class MeasureBubble extends Renderer<MeasureBubbleData> {
  MeasureBubble(super.element, this.scheme);

  final ColorScheme scheme;

  /// Offset from the pointer to the bubble's corner, up and to the right so
  /// a finger or pen does not hide it.
  static const anchorOffset = Offset(18, -44);

  @override
  void build(
    Canvas canvas,
    Size size,
    NoteData document,
    DocumentPage page,
    DocumentInfo info,
    CameraTransform transform, [
    ColorScheme? colorScheme,
    bool foreground = false,
  ]) {
    final painter = TextPainter(
      text: TextSpan(
        text: element.text,
        style: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    // Undo the camera so the bubble is drawn in screen pixels.
    canvas.translate(transform.position.dx, transform.position.dy);
    canvas.scale(1 / transform.size);
    canvas.rotate(-transform.rotation);
    var anchor = element.position + anchorOffset;
    // Keep the bubble on screen near the top and right edges.
    final width = painter.width + 16, height = painter.height + 8;
    if (size.width > 0 && anchor.dx + width > size.width) {
      anchor = Offset(element.position.dx - 18 - width, anchor.dy);
    }
    anchor = Offset(anchor.dx, max(anchor.dy, 4));
    final rect = Rect.fromLTWH(anchor.dx, anchor.dy, width, height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()..color = scheme.inverseSurface.withValues(alpha: 0.9),
    );
    painter.paint(canvas, rect.topLeft + const Offset(8, 4));
    canvas.restore();
    painter.dispose();
  }
}
