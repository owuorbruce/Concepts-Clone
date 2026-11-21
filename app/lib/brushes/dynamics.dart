import 'dart:math';

import 'package:butterfly_api/butterfly_api.dart';

/// Speed (in screen px/ms) that normalizes to 1.
const kBrushSpeedNorm = 3.0;

/// The inputs of one brush sample, raw (not normalized).
class BrushInputs {
  const BrushInputs({
    this.pressure = 1,
    this.speed = 0,
    this.tilt = 0,
    this.direction = 0,
    this.random = 0,
    this.progress = 0,
  });

  /// 0–1.
  final double pressure;

  /// Screen px/ms.
  final double speed;

  /// Radians, 0 (upright) – π/2 (flat).
  final double tilt;

  /// Radians.
  final double direction;

  /// 0–1.
  final double random;

  /// 0–1 along the stroke's arc length.
  final double progress;

  double normalized(BrushInput input) => switch (input) {
    BrushInput.pressure => pressure.clamp(0, 1),
    BrushInput.speed => (speed / kBrushSpeedNorm).clamp(0, 1),
    BrushInput.tilt => (tilt / (pi / 2)).clamp(0, 1),
    BrushInput.direction => (direction % (2 * pi)) / (2 * pi),
    BrushInput.random => random.clamp(0, 1),
    BrushInput.strokeProgress => progress.clamp(0, 1),
  };
}

/// Piecewise-linear [curve] at [x]. Outside the points the end values hold.
/// An empty curve is the identity.
double evaluateCurve(List<List<double>> curve, double x) {
  if (curve.isEmpty) return x;
  final first = curve.first;
  if (x <= first[0]) return first[1];
  for (var i = 1; i < curve.length; i++) {
    final a = curve[i - 1];
    final b = curve[i];
    if (x <= b[0]) {
      final span = b[0] - a[0];
      if (span <= 0) return b[1];
      return a[1] + (b[1] - a[1]) * (x - a[0]) / span;
    }
  }
  return curve.last[1];
}

/// Applies every [BrushDynamic] for [output] to [base]: size and opacity
/// multiply, angle and scatter add.
double applyDynamics(
  List<BrushDynamic> dynamics,
  BrushOutput output,
  double base,
  BrushInputs inputs,
) {
  var value = base;
  for (final dynamic in dynamics) {
    if (dynamic.output != output) continue;
    final y = evaluateCurve(dynamic.curve, inputs.normalized(dynamic.input));
    switch (output) {
      case BrushOutput.size:
      case BrushOutput.opacity:
        value *= y;
      case BrushOutput.angle:
      case BrushOutput.scatter:
        value += y;
    }
  }
  return value;
}

/// Whether any dynamic targets [output].
bool hasDynamics(List<BrushDynamic> dynamics, BrushOutput output) =>
    dynamics.any((e) => e.output == output);

/// Opacity factor from the fixed opacity group.
double opacityFactor(BrushOpacity opacity, double pressure) {
  if (opacity.pressureGamma == 0) return 1;
  return max(
    opacity.min,
    pow(pressure.clamp(0, 1), opacity.pressureGamma).toDouble(),
  );
}

/// A stable 32-bit FNV-1a hash, the same on every run and platform.
int stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}
