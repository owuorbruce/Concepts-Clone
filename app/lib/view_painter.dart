import 'dart:math';

import 'package:butterfly/brushes/brush_paint.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/helpers/rect.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly/views/navigator/constants.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_leap/material_leap.dart';

import 'cubits/transform.dart';
import 'selections/selection.dart';

/// Elements smaller than this on screen (longest side, in pixels) are not
/// drawn while zoomed out.
const kSkipElementScreenSize = 0.5;

/// Elements smaller than this on screen are drawn as one filled rectangle in
/// their main color instead of their full geometry.
const kDotElementScreenSize = 2.0;

/// How a renderer is drawn at the current zoom.
enum ElementDetail { full, dot, skip }

/// Picks the detail for [renderer] at [zoom]. Only applies while zoomed out;
/// renderers without bounds, or whose bounds are not computed yet, are always
/// drawn in full.
@visibleForTesting
ElementDetail elementDetail(Renderer renderer, double zoom) {
  if (!(zoom < 1)) return ElementDetail.full;
  final bounds = renderer.expandedRect;
  if (bounds == null || bounds == Rect.zero || !bounds.isFinite) {
    return ElementDetail.full;
  }
  final screen = max(bounds.width, bounds.height) * zoom;
  if (screen < kSkipElementScreenSize) return ElementDetail.skip;
  if (screen < kDotElementScreenSize) return ElementDetail.dot;
  return ElementDetail.full;
}

Color _mainColor(PadElement element) {
  SRGBColor? pick(ElementPaint stroke, [ElementPaint? fill]) {
    final color = stroke.previewColor;
    if (color.a > 0) return color;
    final fillColor = fill?.previewColor;
    return fillColor != null && fillColor.a > 0 ? fillColor : null;
  }

  final color = switch (element) {
    PenElement(:final property) => pick(property.paint, property.fillPaint),
    ShapeElement(:final property) => pick(
      property.paint,
      switch (property.shape) {
        CircleShape(:final fillPaint) => fillPaint,
        RectangleShape(:final fillPaint) => fillPaint,
        TriangleShape(:final fillPaint) => fillPaint,
        LineShape() => null,
      },
    ),
    PolygonElement(:final property) => pick(property.paint, property.fillPaint),
    _ => null,
  };
  return color?.toColor() ?? const Color(0x99808080);
}

void _paintRenderer(
  Canvas canvas,
  Size size,
  NoteData document,
  DocumentPage page,
  DocumentInfo info,
  CameraTransform transform,
  ColorScheme? colorScheme,
  Renderer renderer, {
  bool foreground = false,
  bool combined = false,
  bool reduceDetail = false,
}) {
  if (reduceDetail) {
    switch (elementDetail(renderer, transform.size)) {
      case ElementDetail.skip:
        return;
      case ElementDetail.dot:
        final bounds = renderer.expandedRect!;
        final minimum = 1 / transform.size;
        canvas.drawRect(
          Rect.fromCenter(
            center: bounds.center,
            width: max(bounds.width, minimum),
            height: max(bounds.height, minimum),
          ),
          Paint()..color = _mainColor(renderer.element),
        );
        return;
      case ElementDetail.full:
        break;
    }
  }
  // Pens and shapes far from the canvas origin lose precision in the 32-bit
  // canvas matrix: at (1e6, 1e6) and 1000x they are off by tens of pixels.
  // Move the origin to the element in double precision instead, then apply
  // the element's own rotation and shear around its center relative to it.
  final Offset? origin = switch (renderer) {
    PenRenderer() => renderer.localOrigin,
    ShapeRenderer() => renderer.localOrigin,
    _ => null,
  };
  if (origin != null) {
    final position = transform.position;
    canvas.save();
    // Cancels the camera translation exactly, leaving rotation and scale.
    canvas.translate(position.dx, position.dy);
    canvas.translate(origin.dx - position.dx, origin.dy - position.dy);
    final elementTransformed = renderer.transformCanvas(canvas, origin);
    switch (renderer) {
      case PenRenderer():
        renderer.buildLocal(canvas, combined: combined);
      case ShapeRenderer():
        renderer.buildLocal(canvas);
      default:
    }
    if (elementTransformed) canvas.restore();
    canvas.restore();
    return;
  }
  final transformed = renderer.transformCanvas(canvas);
  if (combined && renderer is PenRenderer) {
    renderer.buildCombined(canvas);
  } else {
    renderer.build(
      canvas,
      size,
      document,
      page,
      info,
      transform,
      colorScheme,
      foreground,
    );
  }
  if (transformed) canvas.restore();
}

Rect? _rendererBounds(Renderer renderer) => renderer.expandedRect;

Rect? _groupBounds(Iterable<Renderer> renderers) {
  Rect? bounds;
  for (final renderer in renderers) {
    final rect = _rendererBounds(renderer);
    if (rect == null) return null;
    bounds = bounds?.expandToInclude(rect) ?? rect;
  }
  return bounds;
}

/// Paints element [renderers] as the canvas and the bake do, masks included.
@visibleForTesting
void paintElementRenderers(
  Canvas canvas,
  Size size,
  NoteData document,
  DocumentPage page,
  DocumentInfo info,
  CameraTransform transform,
  Iterable<Renderer> renderers,
) => _paintRenderers(
  canvas,
  size,
  document,
  page,
  info,
  transform,
  null,
  renderers,
);

/// The layers of [renderers] that contain a mask stroke.
Set<String?> maskedLayersOf(Iterable<Renderer> renderers) => {
  for (final renderer in renderers)
    if (renderer is PenRenderer && isMaskElement(renderer.element))
      renderer.layer,
};

/// Paints [renderers] in order. A layer with a mask is painted inside one
/// layer of its own, so the mask's dstOut only removes that layer's earlier
/// strokes, never other layers or the background. Layers without masks are
/// painted directly.
void _paintRenderers(
  Canvas canvas,
  Size size,
  NoteData document,
  DocumentPage page,
  DocumentInfo info,
  CameraTransform transform,
  ColorScheme? colorScheme,
  Iterable<Renderer> renderers, {
  bool foreground = false,
  bool reduceDetail = false,
}) {
  final rendererList = renderers is List<Renderer>
      ? renderers
      : renderers.toList();
  final masked = maskedLayersOf(rendererList);
  void paint(List<Renderer> list) => _paintRendererList(
    canvas,
    size,
    document,
    page,
    info,
    transform,
    colorScheme,
    list,
    foreground: foreground,
    reduceDetail: reduceDetail,
  );
  if (masked.isEmpty) {
    paint(rendererList);
    return;
  }
  final painted = <String?>{};
  final run = <Renderer>[];
  void flush() {
    if (run.isEmpty) return;
    paint(List.of(run));
    run.clear();
  }

  for (final renderer in rendererList) {
    final layer = renderer.layer;
    if (!masked.contains(layer)) {
      run.add(renderer);
      continue;
    }
    if (!painted.add(layer)) continue;
    flush();
    final layerRenderers = [
      for (final other in rendererList)
        if (other.layer == layer) other,
    ];
    canvas.saveLayer(_groupBounds(layerRenderers), Paint());
    paint(layerRenderers);
    canvas.restore();
  }
  flush();
}

void _paintRendererList(
  Canvas canvas,
  Size size,
  NoteData document,
  DocumentPage page,
  DocumentInfo info,
  CameraTransform transform,
  ColorScheme? colorScheme,
  List<Renderer> rendererList, {
  bool foreground = false,
  bool reduceDetail = false,
}) {
  Map<String, List<PenRenderer>>? groups;
  for (final renderer in rendererList.whereType<PenRenderer>()) {
    final combineId = renderer.element.combineId;
    if (combineId != null) {
      (groups ??= {}).putIfAbsent(combineId, () => []).add(renderer);
    }
  }
  if (groups == null) {
    for (final renderer in rendererList) {
      _paintRenderer(
        canvas,
        size,
        document,
        page,
        info,
        transform,
        colorScheme,
        renderer,
        foreground: foreground,
        reduceDetail: reduceDetail,
      );
    }
    return;
  }
  final paintedGroups = <String>{};
  for (final renderer in rendererList) {
    final combineId = renderer is PenRenderer
        ? renderer.element.combineId
        : null;
    if (combineId == null) {
      _paintRenderer(
        canvas,
        size,
        document,
        page,
        info,
        transform,
        colorScheme,
        renderer,
        foreground: foreground,
        reduceDetail: reduceDetail,
      );
      continue;
    }
    if (!paintedGroups.add(combineId)) continue;
    final group = groups[combineId]!;
    if (group.length == 1) {
      _paintRenderer(
        canvas,
        size,
        document,
        page,
        info,
        transform,
        colorScheme,
        group.first,
        foreground: foreground,
        reduceDetail: reduceDetail,
        combined: true,
      );
      continue;
    }
    canvas.saveLayer(_groupBounds(group), Paint());
    for (final groupedRenderer in group) {
      _paintRenderer(
        canvas,
        size,
        document,
        page,
        info,
        transform,
        colorScheme,
        groupedRenderer,
        foreground: foreground,
        reduceDetail: reduceDetail,
        combined: true,
      );
    }
    canvas.restore();
  }
}

class ForegroundPainter extends CustomPainter {
  final ColorScheme colorScheme;
  final NoteData document;
  final DocumentPage page;
  final DocumentInfo info;
  final List<Renderer> renderers;
  final CameraTransform transform;
  final Selection? selection;
  final NavigatorPosition navigatorPosition;

  ForegroundPainter(
    this.renderers,
    this.document,
    this.page,
    this.info,
    this.colorScheme, [
    this.transform = const CameraTransform(),
    this.selection,
    this.navigatorPosition = .left,
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    final sel = selection;
    if (renderers.isEmpty && sel == null) return;
    transform.applyToCanvas(canvas);
    _paintRenderers(
      canvas,
      size,
      document,
      page,
      info,
      transform,
      colorScheme,
      renderers,
      foreground: true,
      reduceDetail: true,
    );
    if (sel is ElementSelection) {
      _drawSelection(canvas, size, sel);
    }
  }

  void _drawSelection(Canvas canvas, Size size, ElementSelection selection) {
    final rect = selection.expandedRect;
    if (rect == null) return;
    // Don't allow drawing outside the bounds of the viewport.
    var viewport =
        Offset.zero & Size(size.width - kNavigationRailWidth, size.height);
    if (navigatorPosition == .left) {
      viewport = viewport.translate(kNavigationRailWidth, 0);
    }
    final bounds = transform.localToGlobalRect(viewport);
    final intersection = rect.intersect(bounds);
    if (intersection.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(intersection, const Radius.circular(2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = colorScheme.primary
        ..strokeWidth = 5 / transform.size,
    );
  }

  @override
  bool shouldRepaint(ForegroundPainter oldDelegate) =>
      oldDelegate.renderers != renderers ||
      oldDelegate.transform != transform ||
      oldDelegate.selection != selection ||
      oldDelegate.colorScheme != colorScheme;
}

class ViewPainter extends CustomPainter {
  final NoteData document;
  final DocumentPage page;
  final DocumentInfo info;
  final Area? currentArea;
  final bool renderBackground, renderBaked, renderBakedLayers;
  final CameraViewport cameraViewport;
  final CameraTransform transform;
  final ColorScheme? colorScheme;
  final Set<String>? invisibleLayers;

  /// Skips elements too small to see and draws barely visible ones as a dot.
  /// Exports turn this off so they always contain every element.
  final bool reduceDetail;

  const ViewPainter(
    this.document,
    this.page,
    this.info, {
    super.repaint,
    this.currentArea,
    this.invisibleLayers,
    this.renderBackground = true,
    this.renderBaked = true,
    this.renderBakedLayers = true,
    required this.cameraViewport,
    this.colorScheme,
    this.transform = const CameraTransform(),
    this.reduceDetail = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (renderBackground) {
      canvas.drawColor(Colors.white, BlendMode.src);
    }
    canvas.save();
    transform.applyToCanvas(canvas);
    if (renderBackground) {
      for (final e in cameraViewport.backgrounds) {
        e.build(canvas, size, document, page, info, transform, colorScheme);
      }
    }
    final belowLayerImage = cameraViewport.belowLayerImage;
    final bakedRect = cameraViewport.toRect();
    // Cached rasters need interpolation when rotated or rescaled on screen.
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;
    if (renderBakedLayers && belowLayerImage != null) {
      canvas.drawImageRect(
        belowLayerImage,
        cameraViewport.toImageSourceRect(
          Size(
            belowLayerImage.width.toDouble(),
            belowLayerImage.height.toDouble(),
          ),
        ),
        bakedRect,
        imagePaint,
      );
    }
    final areaRect = currentArea?.rect;
    final areaSelectionWidth = 5 / transform.size;
    if (areaRect != null) {
      final visibleRect = transform.localToGlobalRect(Offset.zero & size);
      final currentAreaColor = currentArea?.color?.toColor();
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..color = currentAreaColor ?? colorScheme?.primary ?? Colors.green
        ..strokeWidth = areaSelectionWidth;
      canvas.drawRect(areaRect.inflate(areaSelectionWidth / 2), paint);
      for (final area in page.areas) {
        if (area == currentArea || !area.rect.overlaps(visibleRect)) continue;
        if (areaRect.overlaps(area.rect)) continue;
        final areaPaint = Paint()
          ..style = PaintingStyle.stroke
          ..color =
              area.color?.toColor() ?? colorScheme?.secondary ?? Colors.grey
          ..strokeWidth = areaSelectionWidth;
        canvas.drawRect(area.rect.inflate(areaSelectionWidth / 2), areaPaint);
      }
      canvas.clipRect(areaRect);
    }
    final image = cameraViewport.image;
    if (image != null &&
        renderBaked &&
        (cameraViewport.bakedElements.isNotEmpty ||
            cameraViewport.visibleUnbakedElements.isNotEmpty)) {
      // Draw our baked image, scaling it down with drawImageRect.
      try {
        canvas.drawImageRect(
          image,
          cameraViewport.toImageSourceRect(
            Size(image.width.toDouble(), image.height.toDouble()),
          ),
          bakedRect,
          imagePaint,
        );
      } catch (_) {}
    }
    final renderers = cameraViewport.visibleUnbakedElements.where((renderer) {
      final state = cameraViewport.rendererStates[renderer.id];
      return !(invisibleLayers?.contains(renderer.layer) ?? false) &&
          state != .hidden;
    });
    _paintRenderers(
      canvas,
      size,
      document,
      page,
      info,
      transform,
      colorScheme,
      renderers,
      reduceDetail: reduceDetail,
    );
    final aboveLayerImage = cameraViewport.aboveLayerImage;
    if (renderBakedLayers && aboveLayerImage != null) {
      canvas.drawImageRect(
        aboveLayerImage,
        cameraViewport.toImageSourceRect(
          Size(
            aboveLayerImage.width.toDouble(),
            aboveLayerImage.height.toDouble(),
          ),
        ),
        bakedRect,
        imagePaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ViewPainter oldDelegate) {
    final shouldRepaint =
        !identical(document, oldDelegate.document) ||
        !identical(page, oldDelegate.page) ||
        !identical(info, oldDelegate.info) ||
        renderBackground != oldDelegate.renderBackground ||
        renderBaked != oldDelegate.renderBaked ||
        renderBakedLayers != oldDelegate.renderBakedLayers ||
        transform != oldDelegate.transform ||
        !identical(cameraViewport, oldDelegate.cameraViewport) ||
        (!identical(invisibleLayers, oldDelegate.invisibleLayers) &&
            !setEquals(invisibleLayers, oldDelegate.invisibleLayers)) ||
        !identical(currentArea, oldDelegate.currentArea) ||
        colorScheme != oldDelegate.colorScheme ||
        reduceDetail != oldDelegate.reduceDetail;
    return shouldRepaint;
  }
}
