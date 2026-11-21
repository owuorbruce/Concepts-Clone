import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:butterfly_api/butterfly_api.dart';

import 'brush_registry.dart';
import 'dynamics.dart';

/// Shader matrix of a pattern: maps texture pixels to the stroke's local
/// space so the pattern is anchored to the canvas, not to the stroke.
/// [origin] is the canvas position of the local origin.
Float64List patternMatrix(
  Offset origin,
  double scale,
  double angleDeg,
  int textureSize,
) {
  final s = scale.isFinite && scale > 0 ? scale : 1.0;
  final angle = angleDeg.isFinite ? angleDeg * pi / 180 : 0.0;
  final c = cos(angle) * s, n = sin(angle) * s;
  // The origin in texture pixels, reduced to one tile: whole tiles don't
  // change the pattern and this keeps precision far from the canvas origin.
  final ox = (origin.dx * c + origin.dy * n) / (s * s);
  final oy = (-origin.dx * n + origin.dy * c) / (s * s);
  final rx = ox % textureSize, ry = oy % textureSize;
  final tx = -(c * rx - n * ry);
  final ty = -(n * rx + c * ry);
  return Float64List.fromList([
    c, n, 0, 0, //
    -n, c, 0, 0, //
    0, 0, 1, 0, //
    tx, ty, 0, 1,
  ]);
}

/// The paint of an outline stroke of [def] in [color], or [base] when the
/// brush has neither a pattern nor a mask. [origin] is the canvas position
/// the stroke is drawn relative to.
Paint outlinePaint(
  BrushDefinition def,
  Color color,
  Paint base, {
  required Offset origin,
  List<PathPoint> points = const [],
}) {
  if (def.mask) return maskPaint(color.a);
  final pattern = def.pattern;
  if (pattern.texture.isEmpty) return base;
  final texture = brushTexture(pattern.texture);
  if (texture == null) return base;
  return Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true
    ..blendMode = base.blendMode
    ..filterQuality = FilterQuality.low
    // The shader keeps the paint's alpha, so the stroke opacity applies.
    ..color = Color.fromRGBO(
      0,
      0,
      0,
      (color.a * patternOpacity(def, points)).clamp(0.0, 1.0),
    )
    ..colorFilter = ColorFilter.mode(
      color.withValues(alpha: 1),
      BlendMode.srcIn,
    )
    ..shader = ImageShader(
      texture,
      TileMode.repeated,
      TileMode.repeated,
      patternMatrix(origin, pattern.scale, pattern.angleDeg, texture.width),
    );
}

/// Opacity factor of a pattern stroke: an outline is one path, so its
/// pressure response to opacity uses the stroke's mean.
double patternOpacity(BrushDefinition def, List<PathPoint> points) {
  final usesPressure = def.opacity.pressureGamma != 0;
  final usesDynamics = hasDynamics(def.dynamics, BrushOutput.opacity);
  if (points.isEmpty || (!usesPressure && !usesDynamics)) return 1;
  var sum = 0.0;
  for (final point in points) {
    final pressure = point.pressure.clamp(0.0, 1.0);
    var value = opacityFactor(def.opacity, pressure);
    if (usesDynamics) {
      value = applyDynamics(
        def.dynamics,
        BrushOutput.opacity,
        value,
        BrushInputs(pressure: pressure),
      );
    }
    sum += value;
  }
  return (sum / points.length).clamp(0.0, 1.0);
}

/// A mask removes [strength] (0–1) of the alpha under it.
Paint maskPaint(double strength) => Paint()
  ..style = PaintingStyle.fill
  ..isAntiAlias = true
  ..blendMode = BlendMode.dstOut
  ..color = Color.fromRGBO(0, 0, 0, strength.clamp(0.0, 1.0));

/// Local bounds of the end stamp of [def] at [end], or null.
Rect? endStampBounds(BrushDefinition def, Offset end, double strokeWidth) {
  final stamp = def.endStamp;
  if (stamp == null || stamp.texture.isEmpty) return null;
  final size = max(stamp.size * strokeWidth, 0.0);
  if (size <= 0) return null;
  return Rect.fromCenter(center: end, width: size, height: size);
}

/// Draws the end stamp of [def] once at [end], in [color].
void drawEndStamp(
  Canvas canvas,
  BrushDefinition def,
  Offset end,
  double strokeWidth,
  Color color,
) {
  final bounds = endStampBounds(def, end, strokeWidth);
  final stamp = def.endStamp;
  if (bounds == null || stamp == null) return;
  final texture = brushTexture(stamp.texture);
  if (texture == null) return;
  final size = texture.width.toDouble();
  canvas.drawImageRect(
    texture,
    Rect.fromLTWH(0, 0, size, size),
    bounds,
    Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = ColorFilter.mode(color, BlendMode.modulate),
  );
}

/// Whether the brush [id] at [version] is a mask.
bool isMaskBrush(String id, [int? version]) =>
    brushById(id, version)?.mask ?? false;

/// Whether [element] is a mask stroke.
bool isMaskElement(PadElement element) =>
    element is PenElement &&
    isMaskBrush(element.property.brush, element.property.brushVersion);
