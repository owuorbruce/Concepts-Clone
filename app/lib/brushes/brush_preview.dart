import 'dart:math';
import 'dart:ui' as ui;

import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:flutter/widgets.dart';

import 'brush_registry.dart';

/// Size of the preview stroke's box, in canvas units.
const _kPreviewBox = Size(120, 40);

/// A short S-curve with a pressure ramp of 0.3 → 1 → 0.4 and fake times.
List<PathPoint> brushPreviewPoints() {
  const count = 48;
  return [
    for (var i = 0; i < count; i++)
      () {
        final t = i / (count - 1);
        final pressure = t < 0.5 ? 0.3 + 1.4 * t : 1 - 1.2 * (t - 0.5);
        return PathPoint(
          10 + t * (_kPreviewBox.width - 20),
          _kPreviewBox.height / 2 - sin((2 * t - 1) * pi) * 11,
          pressure,
          null,
          null,
          i * 14,
        );
      }(),
  ];
}

/// The stroke width the preview uses for [definition].
double brushPreviewWidth(BrushDefinition definition) =>
    (definition.defaultSize ?? 6).clamp(2.0, 14.0).toDouble();

final Map<(String, int, int, int), ui.Image> _cache = {};

/// Draws the preview stroke of [definition] in [color] on [canvas], filling
/// [size]. [pixelRatio] sets how finely curves are sampled.
void paintBrushPreview(
  Canvas canvas,
  Size size,
  BrushDefinition definition,
  Color color, {
  double pixelRatio = 1,
}) {
  final scale = min(
    size.width / _kPreviewBox.width,
    size.height / _kPreviewBox.height,
  );
  final element = PenElement(
    id: 'preview:${definition.id}',
    zoom: max(scale * pixelRatio, 1),
    points: brushPreviewPoints(),
    property: PenProperty(
      brush: definition.id,
      brushVersion: definition.version,
      strokeWidth: brushPreviewWidth(definition),
      paint: ElementPaint.solid(color: SRGBColor(color.toARGB32())),
    ),
  );
  final renderer = PenRenderer(element);
  canvas.save();
  canvas.translate(
    (size.width - _kPreviewBox.width * scale) / 2,
    (size.height - _kPreviewBox.height * scale) / 2,
  );
  canvas.scale(scale);
  final origin = renderer.localOrigin;
  canvas.translate(origin.dx, origin.dy);
  renderer.buildLocal(canvas);
  canvas.restore();
  renderer.dispose();
}

/// The preview of [definition] as an image, cached per brush, color and
/// size. Null while stamp textures are still loading.
ui.Image? brushPreviewImage(
  BrushDefinition definition,
  Color color,
  Size size,
  double pixelRatio,
) {
  if (definition.engine == BrushEngine.stamp && !brushTexturesReady) {
    return null;
  }
  final width = max(1, (size.width * pixelRatio).round());
  final height = max(1, (size.height * pixelRatio).round());
  final key = (
    '${definition.id}@${definition.version}',
    color.toARGB32(),
    width,
    height,
  );
  final cached = _cache[key];
  if (cached != null) return cached;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  paintBrushPreview(canvas, size, definition, color, pixelRatio: pixelRatio);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return _cache[key] = image;
}

/// The preview stroke of the brush [brushId], drawn by its own engine.
class BrushEnginePreview extends StatelessWidget {
  const BrushEnginePreview(this.definition, {super.key, required this.color});

  final BrushDefinition definition;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox();
        final image = brushPreviewImage(definition, color, size, pixelRatio);
        if (image == null) return const SizedBox.expand();
        return RawImage(
          image: image,
          width: size.width,
          height: size.height,
          fit: BoxFit.fill,
        );
      },
    );
  }
}

/// An S-curve across a [size] strip with a pressure ramp of 0.3 → 1 → 0.4,
/// [inset] from the ends, in the strip's own units.
List<PathPoint> brushStripPoints(Size size, {double inset = 16}) {
  const count = 64;
  final amplitude = size.height * .22;
  return [
    for (var i = 0; i < count; i++)
      () {
        final t = i / (count - 1);
        final pressure = t < 0.5 ? 0.3 + 1.4 * t : 1 - 1.2 * (t - 0.5);
        return PathPoint(
          inset + t * (size.width - 2 * inset),
          size.height / 2 - sin((2 * t - 1) * pi) * amplitude,
          pressure,
          null,
          null,
          i * 14,
        );
      }(),
  ];
}

void _paintStroke(Canvas canvas, PenElement element) {
  final renderer = PenRenderer(element);
  canvas.save();
  final origin = renderer.localOrigin;
  canvas.translate(origin.dx, origin.dy);
  renderer.buildLocal(canvas);
  canvas.restore();
  renderer.dispose();
}

/// Draws [definition] in action across a [size] strip by its own engine: an
/// S-curve in [color] at [strokeWidth], or for a mask, a colored stroke
/// that the mask's stroke hides (hard) or fades (soft) in the middle.
void paintBrushStrip(
  Canvas canvas,
  Size size,
  BrushDefinition definition,
  Color color, {
  required double strokeWidth,
  double pixelRatio = 1,
}) {
  final zoom = max(pixelRatio, 1.0);
  final width = strokeWidth.clamp(1.0, size.height * .4).toDouble();
  final paint = ElementPaint.solid(color: SRGBColor(color.toARGB32()));
  if (!definition.mask) {
    _paintStroke(
      canvas,
      PenElement(
        id: 'strip:${definition.id}',
        zoom: zoom,
        points: brushStripPoints(size),
        property: PenProperty(
          brush: definition.id,
          brushVersion: definition.version,
          strokeWidth: width,
          paint: paint,
        ),
      ),
    );
    return;
  }
  final y = size.height / 2;
  _paintStroke(
    canvas,
    PenElement(
      id: 'strip:base',
      zoom: zoom,
      points: [
        for (var i = 0; i <= 16; i++)
          PathPoint(size.width * (.12 + .76 * i / 16), y, 1),
      ],
      property: PenProperty(
        strokeWidth: size.height * .42,
        thinning: 0,
        paint: paint,
      ),
    ),
  );
  // The mask crosses the middle of the colored stroke.
  final maskWidth = min(width, size.height * .35);
  _paintStroke(
    canvas,
    PenElement(
      id: 'strip:${definition.id}',
      zoom: zoom,
      points: [
        for (var i = 0; i <= 24; i++)
          () {
            final t = i / 24;
            return PathPoint(
              size.width * (.42 + .16 * t),
              size.height * (.08 + .84 * t),
              0.3 + 0.7 * sin(t * pi),
              null,
              null,
              i * 14,
            );
          }(),
      ],
      property: PenProperty(
        brush: definition.id,
        brushVersion: definition.version,
        strokeWidth: maskWidth,
        paint: const ElementPaint.solid(color: SRGBColor(0xFF000000)),
      ),
    ),
  );
}

final Map<Object, ui.Image> _stripCache = {};

/// [paint] recorded at [size] × [pixelRatio] and cached under [key] with the
/// size, so each library item, size and theme is drawn once.
ui.Image cachedPreviewImage(
  Object key,
  Size size,
  double pixelRatio,
  void Function(Canvas canvas) paint,
) {
  final width = max(1, (size.width * pixelRatio).round());
  final height = max(1, (size.height * pixelRatio).round());
  final fullKey = (key, width, height);
  final cached = _stripCache[fullKey];
  if (cached != null) return cached;
  // A long session resizing the library keeps a bounded cache. Images may
  // still be on screen, so they are dropped, not disposed.
  if (_stripCache.length > 64) _stripCache.clear();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return _stripCache[fullKey] = image;
}

/// A cached image of [paint] that fills its box, redrawn only for a new
/// [cacheKey] or size.
class CachedPreview extends StatelessWidget {
  const CachedPreview({
    super.key,
    required this.cacheKey,
    required this.painter,
    this.ready = true,
  });

  final Object cacheKey;
  final void Function(Canvas canvas, Size size, double pixelRatio) painter;

  /// False while what the preview needs (stamp textures) is still loading.
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!ready || !size.isFinite || size.isEmpty) {
          return const SizedBox.expand();
        }
        final image = cachedPreviewImage(
          cacheKey,
          size,
          pixelRatio,
          (canvas) => painter(canvas, size, pixelRatio),
        );
        return RawImage(
          image: image,
          width: size.width,
          height: size.height,
          fit: BoxFit.fill,
        );
      },
    );
  }
}

/// [definition] in action across the library's preview strip.
class BrushStripPreview extends StatelessWidget {
  const BrushStripPreview(
    this.definition, {
    super.key,
    required this.color,
    required this.strokeWidth,
  });

  final BrushDefinition definition;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => CachedPreview(
    cacheKey: (
      'brush',
      definition.id,
      definition.version,
      color.toARGB32(),
      strokeWidth,
    ),
    ready: definition.engine != BrushEngine.stamp || brushTexturesReady,
    painter: (canvas, size, pixelRatio) => paintBrushStrip(
      canvas,
      size,
      definition,
      color,
      strokeWidth: strokeWidth,
      pixelRatio: pixelRatio,
    ),
  );
}

/// Draws a classic pen with [property] across a [size] strip by the classic
/// engine: the S-curve, or a closed loop when the pen fills ([closed]).
void paintPenStrip(
  Canvas canvas,
  Size size,
  PenProperty property, {
  bool closed = false,
  double pixelRatio = 1,
}) {
  final List<PathPoint> points;
  if (closed) {
    const count = 48;
    final center = size.center(Offset.zero);
    points = [
      for (var i = 0; i <= count; i++)
        () {
          final a = i / count * 2 * pi;
          return PathPoint(
            center.dx + cos(a) * size.width * .3,
            center.dy + sin(a) * size.height * .32,
          );
        }(),
    ];
  } else {
    points = brushStripPoints(size);
  }
  _paintStroke(
    canvas,
    PenElement(
      id: 'strip:pen',
      zoom: max(pixelRatio, 1.0),
      points: points,
      property: property.copyWith(
        strokeWidth: property.strokeWidth.clamp(1.0, size.height * .4),
      ),
    ),
  );
}
