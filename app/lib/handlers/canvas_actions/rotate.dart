part of '../handler.dart';

/// Within this angle of a quarter turn, the view snaps to it.
const kRotationSnapTolerance = 5 * pi / 180;

double _wrapPi(double angle) {
  final wrapped = (angle + pi) % (2 * pi) - pi;
  return wrapped.isFinite ? wrapped : 0;
}

/// [rotation] snapped to the nearest multiple of 90° when within
/// [kRotationSnapTolerance] of it.
@visibleForTesting
double snapViewRotation(double rotation) {
  if (!rotation.isFinite) return 0;
  const quarter = pi / 2;
  final nearest = (rotation / quarter).round() * quarter;
  if ((rotation - nearest).abs() <= kRotationSnapTolerance) return nearest;
  return rotation;
}

/// The angle from [from] to [to] around [center], from −π to π, positive
/// clockwise on screen (the sign the two-finger rotation uses).
@visibleForTesting
double sweptAngle(Offset center, Offset from, Offset to) {
  final a = from - center;
  final b = to - center;
  if (a.distanceSquared < 1e-12 || b.distanceSquared < 1e-12) return 0;
  return _wrapPi(atan2(b.dy, b.dx) - atan2(a.dy, a.dx));
}

/// [start] rotated by [sweep] around the screen point [center], snapped.
@visibleForTesting
CameraTransform rotateViewAround(
  CameraTransform start,
  Offset center,
  double sweep,
) => start.withRotation(snapViewRotation(start.rotation + sweep), center);

/// The view [t] of the way from [from] back to 0° around [center].
@visibleForTesting
CameraTransform rotationResetFrame(
  CameraTransform from,
  Offset center,
  double t,
) {
  final eased = _easeInOut(t);
  // Turn the short way round.
  final rotation = t >= 1 ? 0.0 : from.rotation * (1 - eased);
  return from.withRotation(rotation, center);
}

class RotateViewHandler extends ViewActionHandler {
  RotateViewHandler(super.data);

  double _sweep = 0;
  Offset? _last;

  @override
  void onPointerDown(PointerDownEvent event, EventContext context) {
    super.onPointerDown(event, context);
    _sweep = 0;
    _last = event.localPosition;
  }

  @override
  CameraTransform dragTransform(
    CameraTransform start,
    Offset startLocal,
    Offset local,
    Size viewport,
  ) {
    final center = viewport.center(Offset.zero);
    // Add up small steps so a drag can turn the view more than half a turn.
    final last = _last ?? startLocal;
    _sweep += sweptAngle(center, last, local);
    _last = local;
    return rotateViewAround(start, center, _sweep);
  }

  @override
  CameraTransform resetFrame(
    CameraTransform from,
    Offset local,
    Size viewport,
    double reference,
    double t,
  ) => rotationResetFrame(from, viewport.center(Offset.zero), t);

  @override
  String formatValue(CameraTransform transform, double reference) {
    var degrees = (transform.rotation * 180 / pi).round() % 360;
    if (degrees < 0) degrees += 360;
    return '$degrees°';
  }

  @override
  bool isLocked(PersistentLockState locks) => locks.lockRotation;

  @override
  MouseCursor get cursor => SystemMouseCursors.grab;
}
