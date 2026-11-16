part of 'handler.dart';

class GridHandler extends Handler<GridTool> with PointerManipulationHandler {
  GridHandler(super.data);

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) => [GridRenderer(data)];

  @override
  SelectState onSelected(BuildContext context, [bool wasAdded = true]) {
    return SelectState.toggle;
  }

  @override
  Offset getPointerPosition(
    Offset position,
    Size viewportSize, [
    CameraTransform transform = const .new(),
  ]) {
    final grid = _gridGeometry(data, transform);
    final point = transform.localToGlobal(position);
    double snap(double value, double origin, double step) =>
        step > 0 ? ((value - origin) / step).round() * step + origin : value;
    return transform.globalToLocal(
      Offset(
        snap(point.dx, grid.origin.dx, grid.spacing.dx),
        snap(point.dy, grid.origin.dy, grid.spacing.dy),
      ),
    );
  }
}

class GridRenderer extends Renderer<GridTool> {
  GridRenderer(super.element);

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
    final grid = _gridGeometry(element, transform);
    final bounds = transform.localToGlobalRect(Offset.zero & size);
    final color = element.color.toColor();
    final strokeWidth = element.stroke / transform.size;
    final major = Paint()
      ..strokeWidth = strokeWidth
      ..color = color;
    void drawAxis(
      double origin,
      double spacing,
      double start,
      double end,
      void Function(double value, Paint paint) line,
    ) {
      final level = gridLevel(spacing * transform.size, end - start, spacing);
      if (level == null) return;
      final step = spacing * level.multiplier;
      final minor = level.fade >= 1
          ? major
          : (Paint()
              ..strokeWidth = strokeWidth
              ..color = color.withValues(alpha: color.a * level.fade));
      final firstIndex = ((start - origin) / step).floor();
      final count = min(
        ((end - start) / step).ceil() + 1,
        kMaxGridLinesPerDirection,
      );
      for (var i = 0; i <= count; i++) {
        final index = firstIndex + i;
        final value = origin + index * step;
        if (value > end) break;
        // Every fifth line belongs to the next coarser level: keep it solid
        // while the finer lines fade in.
        final isMajor = level.fade >= 1 || index % kGridLevelFactor == 0;
        if (!isMajor && level.fade <= 0) continue;
        line(value, isMajor ? major : minor);
      }
    }

    final dx = grid.spacing.dx;
    if (dx > 0 && dx.isFinite) {
      drawAxis(
        grid.origin.dx,
        dx,
        bounds.left,
        bounds.right,
        (x, paint) => canvas.drawLine(
          Offset(x, bounds.top),
          Offset(x, bounds.bottom),
          paint,
        ),
      );
    }
    final dy = grid.spacing.dy;
    if (dy > 0 && dy.isFinite) {
      drawAxis(
        grid.origin.dy,
        dy,
        bounds.top,
        bounds.bottom,
        (y, paint) => canvas.drawLine(
          Offset(bounds.left, y),
          Offset(bounds.right, y),
          paint,
        ),
      );
    }
  }
}

/// Most lines the grid draws per direction, at any zoom.
const kMaxGridLinesPerDirection = 400;

/// Factor between two grid levels.
const kGridLevelFactor = 5;

/// Picks the grid level like a dot grid: when lines are closer than 8 px on
/// screen, every fifth line is drawn instead, and the finer lines fade in from
/// 8 to 24 px. [screenSpacing] is the defined spacing in screen pixels,
/// [extent] and [spacing] are in canvas units. Zoomed in, the multiplier
/// stays 1.
@visibleForTesting
({double multiplier, double fade})? gridLevel(
  double screenSpacing,
  double extent,
  double spacing,
) {
  if (!screenSpacing.isFinite || screenSpacing <= 0) return null;
  if (!extent.isFinite || !spacing.isFinite || spacing <= 0) return null;
  var multiplier = 1.0;
  for (var i = 0; i < 64; i++) {
    if (screenSpacing * multiplier >= 8 &&
        extent / (spacing * multiplier) <= kMaxGridLinesPerDirection - 2) {
      break;
    }
    multiplier *= kGridLevelFactor;
  }
  final fade = ((screenSpacing * multiplier - 8) / 16).clamp(0.0, 1.0);
  return (multiplier: multiplier, fade: fade.toDouble());
}

({Offset origin, Offset spacing}) _gridGeometry(
  GridTool tool,
  CameraTransform transform,
) => (
  origin:
      Offset(tool.xOffset, tool.yOffset) / transform.size +
      (tool.positionDependent ? Offset.zero : transform.position),
  spacing:
      Offset(tool.xSize, tool.ySize) /
      (tool.zoomDependent ? 1 : transform.size),
);
