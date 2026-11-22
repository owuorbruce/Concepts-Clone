import 'dart:math';
import 'dart:ui';

/// Default step of [snapAngle]: 15°.
const kSnapAngleStep = pi / 12;

/// Default tolerance of [snapAngle]: 4°.
const kSnapAngleTolerance = 4 * pi / 180;

/// How close, in screen pixels, a point must be to snap to another.
const kSnapPointTolerance = 12.0;

/// [angle] (radians) moved to the nearest multiple of [step] when it is
/// within [tolerance] of it. Returns whether it snapped.
({double angle, bool snapped}) snapAngle(
  double angle, {
  double step = kSnapAngleStep,
  double tolerance = kSnapAngleTolerance,
}) {
  if (!angle.isFinite || step <= 0) return (angle: angle, snapped: false);
  final nearest = (angle / step).round() * step;
  if ((angle - nearest).abs() <= tolerance) {
    return (angle: nearest, snapped: true);
  }
  return (angle: angle, snapped: false);
}

/// [angle] snapped to the nearest of [targets] (radians, compared modulo
/// a half turn so mirrored directions count too) within [tolerance].
({double angle, bool snapped}) snapAngleTo(
  double angle,
  Iterable<double> targets, {
  double tolerance = kSnapAngleTolerance,
}) {
  double? best;
  var bestDistance = double.infinity;
  for (final target in targets) {
    // Distance on the circle of directions with a period of pi.
    var delta = (angle - target) % pi;
    if (delta > pi / 2) delta -= pi;
    if (delta.abs() < bestDistance) {
      bestDistance = delta.abs();
      best = angle - delta;
    }
  }
  if (best != null && bestDistance <= tolerance) {
    return (angle: best, snapped: true);
  }
  return (angle: angle, snapped: false);
}

/// The nearest of [candidates] to [point] within [tolerance], in the same
/// units as the points. Returns [point] itself when none is close enough.
///
/// To snap within [kSnapPointTolerance] screen pixels in document space,
/// pass `kSnapPointTolerance / zoom` as [tolerance].
({Offset point, bool snapped}) snapToPoint(
  Offset point,
  Iterable<Offset> candidates, {
  double tolerance = kSnapPointTolerance,
}) {
  Offset? best;
  var bestDistance = tolerance * tolerance;
  for (final candidate in candidates) {
    final distance = (candidate - point).distanceSquared;
    if (distance <= bestDistance) {
      bestDistance = distance;
      best = candidate;
    }
  }
  if (best == null) return (point: point, snapped: false);
  return (point: best, snapped: true);
}

/// The end of a segment from [start] towards [end] with its direction
/// snapped by [snapAngle]. The length stays the same.
({Offset point, double angle, bool snapped}) snapSegment(
  Offset start,
  Offset end, {
  double step = kSnapAngleStep,
  double tolerance = kSnapAngleTolerance,
}) {
  final delta = end - start;
  final length = delta.distance;
  if (length == 0) return (point: end, angle: 0, snapped: false);
  final result = snapAngle(delta.direction, step: step, tolerance: tolerance);
  if (!result.snapped) {
    return (point: end, angle: delta.direction, snapped: false);
  }
  return (
    point: start + Offset.fromDirection(result.angle, length),
    angle: result.angle,
    snapped: true,
  );
}

/// Angle in degrees from 0 to 360 for display, with up on the screen as
/// positive like a protractor.
double displayDegrees(double radians) {
  var degrees = -radians * 180 / pi;
  degrees %= 360;
  if (degrees < 0) degrees += 360;
  // Avoid "360°" from rounding.
  if (degrees >= 359.95) degrees = 0;
  return degrees;
}
