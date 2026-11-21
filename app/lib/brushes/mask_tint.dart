import 'dart:ui';

import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:material_ui/material_ui.dart' show ColorScheme;

import 'brush_paint.dart';
import 'brush_registry.dart';
import 'outline_engine.dart';

/// Opacity of the gray that shows where masks are.
const kMaskTintOpacity = 0.25;

/// Shows a mask stroke as a faint gray, so it can be found while the mask
/// tool is active or the mask is selected. Masks are invisible otherwise.
class MaskTintRenderer extends Renderer<PenElement> {
  MaskTintRenderer(super.element);

  Path? _path;
  Offset _origin = Offset.zero;

  Path? _outline() {
    final cached = _path;
    if (cached != null) return cached;
    final property = element.property;
    final definition = brushById(property.brush, property.brushVersion);
    final points = element.points;
    if (definition == null || points.isEmpty) return null;
    _origin = Offset(points.first.x, points.first.y);
    // The outline of the stroke's width response, for stamp masks too.
    return _path = buildOutline(
      points,
      definition,
      property.strokeWidth,
      zoom: element.zoom ?? 1,
      origin: _origin,
    );
  }

  @override
  void build(
    Canvas canvas,
    Size size,
    NoteData document,
    DocumentPage page,
    DocumentInfo info,
    CameraTransform transform, [
    ColorScheme? colorScheme,
    bool foreground = false,
  ]) {
    final path = _outline();
    if (path == null) return;
    canvas.save();
    canvas.translate(_origin.dx, _origin.dy);
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..color = const Color.fromRGBO(128, 128, 128, kMaskTintOpacity),
    );
    canvas.restore();
  }
}

/// Tints for the mask strokes among [elements].
List<Renderer> maskTints(Iterable<PadElement> elements) => [
  for (final element in elements)
    if (element is PenElement && isMaskElement(element))
      MaskTintRenderer(element),
];

/// Tints for every mask stroke of [page].
List<Renderer> pageMaskTints(DocumentPage page) =>
    maskTints(page.layers.expand((layer) => layer.content));
