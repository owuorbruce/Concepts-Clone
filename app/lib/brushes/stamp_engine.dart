import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:butterfly_api/butterfly_api.dart';

import 'brush_registry.dart';
import 'dynamics.dart';
import 'outline_engine.dart';

/// Most stamps drawn for one stroke; longer strokes get wider spacing.
const kMaxStampsPerStroke = 20000;

/// The stamps of one stroke, relative to the origin they were built at.
class StampStroke {
  StampStroke._(
    this.x,
    this.y,
    this.size,
    this.angle,
    this.alpha,
    this.bounds,
    this.meanWidth,
  );

  final Float32List x, y, size, angle, alpha;

  /// Local bounds of every stamp.
  final Rect bounds;

  /// Average stamp size, used for the wet-edge blur.
  final double meanWidth;

  int get length => x.length;

  /// Places the stamps of [points] for [def]. [seed] (the element id) makes
  /// the randomness repeatable.
  factory StampStroke.build(
    List<PathPoint> points,
    BrushDefinition def,
    double strokeWidth, {
    required double zoom,
    required Offset origin,
    required String seed,
  }) {
    final g = StrokeGeometry.build(
      points,
      def,
      strokeWidth,
      zoom: zoom,
      origin: origin,
    );
    final random = Random(stableHash(seed));
    final spacing = max(def.spacing, 0.005);
    // Estimate the count first so long strokes stay within the budget.
    var estimate = g.isEmpty ? 0.0 : 1.0;
    for (var i = 1; i < g.length; i++) {
      final ds = g.arc[i] - g.arc[i - 1];
      estimate += ds / max(spacing * g.width[i], 1e-6);
    }
    final spacingScale = estimate > kMaxStampsPerStroke
        ? estimate / kMaxStampsPerStroke
        : 1.0;
    final xs = <double>[], ys = <double>[], sizes = <double>[];
    final angles = <double>[], alphas = <double>[];
    final total = g.arcLength;
    final dynamics = def.dynamics;
    final tiltShading = def.tiltShading;
    final jitter = def.angleJitter * pi / 180;
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    var widthSum = 0.0;

    void place(int i, double t) {
      final j = min(i + 1, g.length - 1);
      double lerp(Float64List l) => l[i] + (l[j] - l[i]) * t;
      final px = lerp(g.x), py = lerp(g.y), w = lerp(g.width);
      final pressure = lerp(g.pressure), tilt = lerp(g.tilt);
      final direction = g.angle[i];
      // Always draw the same number of random values per stamp.
      final rSize = random.nextDouble();
      final rScatter = random.nextDouble();
      final rAngle = random.nextDouble();
      final rJitter = random.nextDouble();
      final rInput = random.nextDouble();
      final inputs = BrushInputs(
        pressure: pressure,
        speed: lerp(g.speed),
        tilt: tilt,
        direction: direction,
        random: rInput,
        progress: total == 0 ? 0 : lerp(g.arc) / total,
      );
      var size = w * (1 + def.sizeJitter * (2 * rSize - 1));
      size = applyDynamics(dynamics, BrushOutput.size, size, inputs);
      var alpha = def.flow * opacityFactor(def.opacity, pressure);
      alpha = applyDynamics(dynamics, BrushOutput.opacity, alpha, inputs);
      if (tiltShading && tilt > 0) {
        final tn = (tilt / (pi / 2)).clamp(0.0, 1.0);
        size *= 1 + 2 * tn;
        alpha *= 1 - 0.5 * tn;
      }
      final scatter = applyDynamics(
        dynamics,
        BrushOutput.scatter,
        def.scatter,
        inputs,
      );
      final offset = (2 * rScatter - 1) * scatter * w;
      final sx = px - sin(direction) * offset;
      final sy = py + cos(direction) * offset;
      var angle = switch (def.angleMode) {
        BrushAngleMode.fixed => 0.0,
        BrushAngleMode.direction => direction,
        BrushAngleMode.random => rAngle * 2 * pi,
      };
      angle += jitter * (2 * rJitter - 1);
      angle = applyDynamics(dynamics, BrushOutput.angle, angle, inputs);
      if (size <= 0) return;
      xs.add(sx);
      ys.add(sy);
      sizes.add(size);
      angles.add(angle);
      alphas.add(alpha.clamp(0.0, 1.0));
      // A rotated square texture reaches √2 × half its size.
      final reach = size * 0.7072;
      left = min(left, sx - reach);
      top = min(top, sy - reach);
      right = max(right, sx + reach);
      bottom = max(bottom, sy + reach);
      widthSum += size;
    }

    if (!g.isEmpty) {
      place(0, 0);
      var next = spacing * g.width[0] * spacingScale;
      var travelled = 0.0;
      for (var i = 1; i < g.length; i++) {
        final ds = g.arc[i] - g.arc[i - 1];
        while (ds > 0 && travelled + ds >= next) {
          final t = (next - travelled) / ds;
          place(i - 1, t);
          final w = g.width[i - 1] + (g.width[i] - g.width[i - 1]) * t;
          next += max(spacing * w * spacingScale, 1e-4);
        }
        travelled += ds;
      }
    }
    final count = xs.length;
    return StampStroke._(
      Float32List.fromList(xs),
      Float32List.fromList(ys),
      Float32List.fromList(sizes),
      Float32List.fromList(angles),
      Float32List.fromList(alphas),
      count == 0 ? Rect.zero : Rect.fromLTRB(left, top, right, bottom),
      count == 0 ? 0 : widthSum / count,
    );
  }

  /// Atlas transforms for a texture [textureSize] pixels wide.
  Float32List transforms(int textureSize) {
    final result = Float32List(length * 4);
    final anchor = textureSize / 2;
    for (var i = 0; i < length; i++) {
      final scale = size[i] / textureSize;
      final scos = scale * cos(angle[i]);
      final ssin = scale * sin(angle[i]);
      result[i * 4] = scos;
      result[i * 4 + 1] = ssin;
      result[i * 4 + 2] = x[i] - scos * anchor + ssin * anchor;
      result[i * 4 + 3] = y[i] - ssin * anchor - scos * anchor;
    }
    return result;
  }

  Float32List rects(int textureSize) {
    final result = Float32List(length * 4);
    for (var i = 0; i < length; i++) {
      result[i * 4 + 2] = textureSize.toDouble();
      result[i * 4 + 3] = textureSize.toDouble();
    }
    return result;
  }

  /// Stamp colors: [color] at each stamp's alpha, times [alphaScale].
  Int32List colors(Color color, double alphaScale) {
    final result = Int32List(length);
    final rgb = color.toARGB32() & 0x00ffffff;
    for (var i = 0; i < length; i++) {
      final a = (alpha[i] * alphaScale * 255).round().clamp(0, 255);
      result[i] = (a << 24) | rgb;
    }
    return result;
  }
}

/// Grain shader matrix: anchors the texture to the canvas, not the stroke.
Float64List grainMatrix(Offset origin, double scale, int textureSize) {
  final period = textureSize * scale;
  // Only the offset within one tile matters; keeps precision far out.
  final tx = -(origin.dx % period);
  final ty = -(origin.dy % period);
  return Float64List.fromList([
    scale, 0, 0, 0, //
    0, scale, 0, 0, //
    0, 0, 1, 0, //
    tx, ty, 0, 1,
  ]);
}

/// Draws [stamps] in [color] with the canvas at the stroke's origin.
void drawStampStroke(
  Canvas canvas,
  StampStroke stamps,
  BrushDefinition def,
  Color color, {
  required Offset origin,
}) {
  if (stamps.length == 0) return;
  final texture = brushTexture(def.texture) ?? brushTexture('round-soft');
  if (texture == null) return;
  final textureSize = texture.width;
  final transforms = stamps.transforms(textureSize);
  final rects = stamps.rects(textureSize);
  final opacity = color.a;
  final blur = def.wetEdges > 0 ? max(stamps.meanWidth * 0.15, 0.01) : 0.0;
  final bounds = stamps.bounds.inflate(blur * 3 + 1);
  final layerPaint = Paint()
    ..color = Color.fromRGBO(0, 0, 0, def.buildUp ? 1 : opacity)
    ..blendMode = def.blend == BrushBlend.multiply
        ? BlendMode.multiply
        : BlendMode.srcOver;
  final colors = stamps.colors(color, def.buildUp ? opacity : 1);
  final atlasPaint = Paint()..filterQuality = FilterQuality.low;

  void atlas() => canvas.drawRawAtlas(
    texture,
    transforms,
    rects,
    colors,
    BlendMode.modulate,
    null,
    atlasPaint,
  );

  final grain = def.grain;
  final paper = grain.strength > 0 ? brushTexture(grain.texture) : null;
  final layered =
      !def.buildUp ||
      def.wetEdges > 0 ||
      paper != null ||
      def.blend != BrushBlend.normal;
  if (!layered) {
    atlas();
    return;
  }
  canvas.saveLayer(bounds, layerPaint);
  atlas();
  if (def.wetEdges > 0) {
    // Wet edges: take a blurred copy of the stroke away from itself. The
    // blurred copy is weaker near the rim, so the middle loses more than the
    // edge, which then reads darker, like pigment pooling at a drying edge.
    canvas.saveLayer(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..color = Color.fromRGBO(0, 0, 0, def.wetEdges.clamp(0.0, 1.0))
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.decal,
        ),
    );
    atlas();
    canvas.restore();
  }
  if (paper != null) {
    final s = grain.strength.clamp(0.0, 1.0);
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..colorFilter = ColorFilter.matrix([
          0, 0, 0, 0, 0, //
          0, 0, 0, 0, 0, //
          0, 0, 0, 0, 0, //
          0, 0, 0, s, (1 - s) * 255,
        ])
        ..shader = ImageShader(
          paper,
          TileMode.repeated,
          TileMode.repeated,
          grainMatrix(origin, max(grain.scale, 0.01), paper.width),
        ),
    );
  }
  canvas.restore();
}

/// Records [stamps] once so they can be replayed every frame.
ui.Picture recordStampStroke(
  StampStroke stamps,
  BrushDefinition def,
  Color color, {
  required Offset origin,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  drawStampStroke(canvas, stamps, def, color, origin: origin);
  return recorder.endRecording();
}

/// Renders [stamps] to a PNG covering [StampStroke.bounds] at
/// [pixelsPerUnit], at most [maxSide] pixels on a side.
Future<Uint8List?> renderStampPng(
  StampStroke stamps,
  BrushDefinition def,
  Color color, {
  required Offset origin,
  double pixelsPerUnit = 1,
  int maxSide = 4096,
}) async {
  final bounds = stamps.bounds;
  if (bounds.isEmpty) return null;
  var scale = pixelsPerUnit;
  final longest = max(bounds.width, bounds.height) * scale;
  if (longest > maxSide) scale *= maxSide / longest;
  final width = max(1, (bounds.width * scale).ceil());
  final height = max(1, (bounds.height * scale).ceil());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(width / bounds.width, height / bounds.height);
  canvas.translate(-bounds.left, -bounds.top);
  drawStampStroke(canvas, stamps, def, color, origin: origin);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
