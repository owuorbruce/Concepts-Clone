import 'dart:math';

import 'package:butterfly/brushes/brush_preview.dart';
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/widgets.dart';

/// Tools with an illustration in the Brush Library's preview strip.
enum ToolPreviewKind { lasso, slice, nudge, shapes, eraser }

/// The illustration of [tool] in the preview strip, or null.
ToolPreviewKind? toolPreviewKind(Tool tool) {
  switch (libraryEntryOf(tool)) {
    case LibraryEntry.lasso:
      return ToolPreviewKind.lasso;
    case LibraryEntry.slice:
      return ToolPreviewKind.slice;
    case LibraryEntry.nudge:
      return ToolPreviewKind.nudge;
    default:
  }
  return switch (ToolFamily.ofTool(tool)) {
    ToolFamily.select => ToolPreviewKind.lasso,
    ToolFamily.shapes ||
    ToolFamily.polygon ||
    ToolFamily.straightedge => ToolPreviewKind.shapes,
    ToolFamily.eraser => ToolPreviewKind.eraser,
    _ => null,
  };
}

Path _curve(Size size, double y, double amplitude, [double bend = 0]) {
  final path = Path()..moveTo(size.width * .1, y);
  path.cubicTo(
    size.width * .35,
    y - amplitude,
    size.width * .55,
    y + amplitude + bend,
    size.width * .9,
    y,
  );
  return path;
}

/// Draws the illustration of [kind] across a [size] strip.
void paintToolPreview(
  Canvas canvas,
  Size size,
  ToolPreviewKind kind, {
  required Color ink,
  required Color accent,
}) {
  final h = size.height, w = size.width;
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = max(2, h * .05)
    ..color = ink;
  final guide = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = max(1.5, h * .03)
    ..color = accent;
  void dashed(Path path) {
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(
          metric.extractPath(d, min(d + 6, metric.length)),
          guide,
        );
      }
    }
  }

  switch (kind) {
    case ToolPreviewKind.lasso:
      // Two marks with a lasso loop drawn around them.
      canvas.drawPath(
        _curve(Size(w * .55, h), h * .45, h * .18).shift(Offset(w * .2, 0)),
        stroke,
      );
      canvas.drawCircle(Offset(w * .62, h * .55), h * .1, stroke);
      dashed(
        Path()..addOval(
          Rect.fromCenter(
            center: Offset(w * .5, h * .5),
            width: w * .62,
            height: h * .8,
          ),
        ),
      );
    case ToolPreviewKind.slice:
      // A curve and the slice line cutting it in two.
      final curve = _curve(size, h * .5, h * .3);
      final metric = curve.computeMetrics().first;
      final half = metric.length / 2;
      canvas.drawPath(metric.extractPath(0, half - 4), stroke);
      canvas.drawPath(
        metric.extractPath(half + 4, metric.length).shift(const Offset(3, 2)),
        stroke,
      );
      dashed(
        Path()
          ..moveTo(w * .44, h * .08)
          ..lineTo(w * .56, h * .92),
      );
    case ToolPreviewKind.nudge:
      // A line bent by the nudge circle.
      final center = Offset(w * .5, h * .62);
      canvas.drawPath(
        Path()
          ..moveTo(w * .1, h * .5)
          ..cubicTo(w * .38, h * .5, w * .42, h * .24, w * .5, h * .24)
          ..cubicTo(w * .58, h * .24, w * .62, h * .5, w * .9, h * .5),
        stroke,
      );
      canvas.drawCircle(center, h * .2, guide);
    case ToolPreviewKind.shapes:
      // A rectangle with a dimension line above it.
      final rect = Rect.fromLTWH(w * .3, h * .38, w * .4, h * .44);
      canvas.drawRect(rect, stroke);
      final y = h * .2;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), guide);
      for (final x in [rect.left, rect.right]) {
        canvas.drawLine(Offset(x, y - h * .08), Offset(x, y + h * .08), guide);
      }
    case ToolPreviewKind.eraser:
      // A stroke with a gap where the eraser passed.
      final curve = _curve(size, h * .5, h * .25);
      final metric = curve.computeMetrics().first;
      final mid = metric.length / 2;
      canvas.drawPath(metric.extractPath(0, mid - h * .2), stroke);
      canvas.drawPath(metric.extractPath(mid + h * .2, metric.length), stroke);
      final at = metric.getTangentForOffset(mid)!.position;
      canvas.drawCircle(at, h * .2, guide);
  }
}

/// The illustration of [kind] in the preview strip, cached per kind, size
/// and colors.
class ToolStripPreview extends StatelessWidget {
  const ToolStripPreview(
    this.kind, {
    super.key,
    required this.ink,
    required this.accent,
  });

  final ToolPreviewKind kind;
  final Color ink, accent;

  @override
  Widget build(BuildContext context) => CachedPreview(
    cacheKey: ('tool', kind, ink.toARGB32(), accent.toARGB32()),
    painter: (canvas, size, _) =>
        paintToolPreview(canvas, size, kind, ink: ink, accent: accent),
  );
}

/// A light checkerboard, like a transparent canvas.
class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter({this.cell = 8});

  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final dark = Paint()..color = const Color(0xFFE9E9E9);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = y.isEven ? 0 : 1; x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(CheckerboardPainter oldDelegate) =>
      oldDelegate.cell != cell;
}
