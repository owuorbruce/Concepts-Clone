import 'dart:math';
import 'dart:ui';

/// Steadies a stroke while it is drawn.
///
/// Points are smoothed exponentially in screen coordinates, so the effect
/// feels the same at every zoom. [finish] then catches the stroke up with
/// the pen tip, so it ends where the pen was lifted.
class StrokeStabilizer {
  /// [smoothing] goes from 0 (the stroke follows the input exactly) to 1
  /// (the calmest line); values outside are clamped.
  StrokeStabilizer(double smoothing)
    : smoothing = smoothing.clamp(0.0, 1.0).toDouble(),
      alpha = 1 - 0.9 * pow(smoothing.clamp(0.0, 1.0), 1.5);

  final double smoothing;

  /// How far each smoothed point moves toward the input, from 0.1 to 1.
  final double alpha;

  /// Catch-up points [finish] adds.
  static const finishSteps = 4;

  /// [finish] adds nothing when the stroke is already this close to the tip.
  static const finishTolerance = 0.5;

  Offset? _last;

  /// The last point given out, or null before the first one.
  Offset? get last => _last;

  /// The smoothed position for the input [raw]. The first point passes
  /// through unchanged.
  Offset add(Offset raw) {
    final previous = _last;
    final next = previous == null || alpha >= 1
        ? raw
        : previous + (raw - previous) * alpha;
    _last = next;
    return next;
  }

  /// Evenly spaced points from the last smoothed point to [raw], ending
  /// exactly at [raw], or none if the stroke is already within
  /// [finishTolerance] of it.
  List<Offset> finish(Offset raw) {
    final previous = _last;
    if (previous == null || (raw - previous).distance <= finishTolerance) {
      return const [];
    }
    _last = raw;
    return [
      for (var i = 1; i < finishSteps; i++)
        previous + (raw - previous) * (i / finishSteps),
      raw,
    ];
  }
}
