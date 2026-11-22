part of '../handler.dart';

/// Vertical drag, in screen pixels, that doubles or halves the zoom.
const kZoomDragDoubling = 200.0;

/// [start] zoomed around the screen point [anchor] for a vertical drag of
/// [dy] pixels: up (negative) zooms in, down zooms out, ×2 per 200 px.
@visibleForTesting
CameraTransform zoomViewAround(
  CameraTransform start,
  Offset anchor,
  double dy,
) {
  if (!dy.isFinite) return start;
  final factor = exp(-dy * ln2 / kZoomDragDoubling);
  return start.withSize(start.size * factor, anchor);
}

/// The view [t] of the way from [from] to [target] zoom around [anchor],
/// interpolated in log space so the speed looks even.
@visibleForTesting
CameraTransform zoomResetFrame(
  CameraTransform from,
  Offset anchor,
  double target,
  double t,
) {
  final eased = _easeInOut(t);
  final start = log(from.size);
  final end = log(target);
  final size = t >= 1 ? target : exp(start + (end - start) * eased);
  return from.withSize(size, anchor);
}

class ZoomViewHandler extends ViewActionHandler {
  ZoomViewHandler(super.data);

  @override
  CameraTransform dragTransform(
    CameraTransform start,
    Offset startLocal,
    Offset local,
    Size viewport,
  ) => zoomViewAround(start, startLocal, local.dy - startLocal.dy);

  @override
  CameraTransform resetFrame(
    CameraTransform from,
    Offset local,
    Size viewport,
    double reference,
    double t,
  ) => zoomResetFrame(from, local, reference, t);

  @override
  String formatValue(CameraTransform transform, double reference) =>
      '${formatZoomPercent(transform.size / reference * 100)} %';

  @override
  bool isLocked(PersistentLockState locks) => locks.lockZoom;

  @override
  MouseCursor get cursor => SystemMouseCursors.zoomIn;
}
