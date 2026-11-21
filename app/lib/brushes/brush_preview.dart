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
