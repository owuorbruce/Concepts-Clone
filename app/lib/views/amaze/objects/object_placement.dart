import 'dart:math' show Point, Rectangle;

import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../floor_plan/floor_plan.dart';
import 'object_store.dart';

/// The scale that fits [sourceRect] into [targetRect].
///
/// An empty source or a zero-size target gives 1:1.
(double, double) calculateComponentScale(Rect sourceRect, Rect targetRect) {
  if (sourceRect.isEmpty ||
      (targetRect.width.abs() < precisionErrorTolerance &&
          targetRect.height.abs() < precisionErrorTolerance)) {
    return (1, 1);
  }
  return (
    targetRect.width / sourceRect.width,
    targetRect.height / sourceRect.height,
  );
}

/// Scales and moves [elements], which together fill [sourceRect], into
/// [targetRect]. Every element gets a new id.
///
/// This is the stamp tool's placement math.
List<PadElement> transformComponentElements(
  Iterable<Renderer<PadElement>> elements,
  Rect sourceRect,
  Rect targetRect,
) {
  final (scaleX, scaleY) = calculateComponentScale(sourceRect, targetRect);

  Offset applyScaleAndTranslate(Offset original) {
    final relative = original - sourceRect.topLeft;
    return Offset(relative.dx * scaleX, relative.dy * scaleY) +
        targetRect.topLeft;
  }

  return regenerateElementIds(
    elements.map((renderer) {
      // Map every element's pivot through the same group transform. Stroke
      // padding and existing rotation must not shift individual elements.
      final center = (renderer.rect ?? Rect.zero).center;
      return renderer
              .transform(
                center: applyScaleAndTranslate(center),
                scaleX: scaleX,
                scaleY: scaleY,
                relative: true,
              )
              ?.element ??
          renderer.element;
    }),
    createUniqueId,
  );
}

/// The elements of [component] at real size, centered on [worldCenter].
///
/// Stored components are relative to their center, so every element moves
/// by [worldCenter]. Every element gets a new id. SVG objects become pen
/// strokes (see [svgObjectToStrokes]), so they can be erased and recolored.
List<PadElement> placeComponentAt(
  ButterflyComponent component,
  Offset worldCenter,
) {
  if (component.elements.isEmpty) return [];
  final placed = transformComponentElements(
    component.elements.map(Renderer.fromInstance),
    Rect.zero,
    Rect.fromLTWH(worldCenter.dx, worldCenter.dy, 0, 0),
  );
  return [
    for (final element in placed)
      if (element is SvgElement)
        ...(svgObjectToStrokes(element) ?? [element])
      else
        element,
  ];
}

/// The SVG of a placed object as pen strokes drawn into its box, each with
/// a new id and the object's `extra` and collection, or null if the SVG
/// can't be converted, so the caller keeps the [SvgElement].
List<PadElement>? svgObjectToStrokes(SvgElement element) {
  final wall = _packWall(element);
  if (wall != null) return [wall];
  const prefix = 'data:image/svg+xml';
  if (!element.source.startsWith(prefix) || element.rotation != 0) {
    return null;
  }
  final String svg;
  try {
    svg = UriData.parse(element.source).contentAsString();
  } on FormatException {
    return null;
  }
  var width = element.width, height = element.height;
  final constraints = element.constraints;
  if (constraints is ScaledElementConstraints) {
    if (constraints.scaleX > 0) width *= constraints.scaleX;
    if (constraints.scaleY > 0) height *= constraints.scaleY;
  } else if (constraints != null) {
    return null;
  }
  final strokes = svgToPenElements(
    svg,
    Rectangle(element.position.x, element.position.y, width, height),
  );
  if (strokes == null) return null;
  return [
    for (final stroke in strokes)
      stroke.copyWith(
        id: createUniqueId(),
        extra: element.extra,
        collection: element.collection,
      ),
  ];
}

/// A pack object tagged as a wall, as a valid floor plan wall on the same
/// rectangle, so snapping, doors and rooms work with it; else null.
PenElement? _packWall(SvgElement element) {
  if (element.extra[kWallExtraKey] is! Map || element.rotation != 0) {
    return null;
  }
  if (element.constraints case final constraints?
      when constraints is! ScaledElementConstraints ||
          constraints.scaleX != 1 ||
          constraints.scaleY != 1) {
    return null;
  }
  final x = element.position.x, y = element.position.y;
  final width = element.width, height = element.height;
  if (width <= 0 || height <= 0) return null;
  // The wall runs along the longer side; its rectangle reaches half the
  // thickness past each end of the centerline.
  final horizontal = width >= height;
  final thickness = horizontal ? height : width;
  final half = thickness / 2;
  final (a, b) = horizontal
      ? (Point(x + half, y + half), Point(x + width - half, y + half))
      : (Point(x + half, y + half), Point(x + half, y + height - half));
  final wall = makeWall(
    a,
    b,
    thickness / kCanvasUnitsPerInch,
    kDefaultWallColor,
  );
  return wall.copyWith(
    id: createUniqueId(),
    collection: element.collection,
    extra: {...element.extra, ...wall.extra},
  );
}

/// Adds [entry] to the current page and layer, centered on [worldCenter].
///
/// This is one undo step.
void addObjectToCanvas(
  BuildContext context,
  ObjectEntry entry,
  Offset worldCenter,
) {
  final bloc = context.read<DocumentBloc>();
  final state = bloc.state;
  if (state is! DocumentLoadSuccess) return;
  final elements = placeComponentAt(entry.component, worldCenter);
  if (elements.isEmpty) return;
  bloc.add(
    ElementsCreated(
      elements,
      pageName: state.pageName,
      layer: state.currentLayer,
    ),
  );
}

/// Waits for a tap on a wall to place the door or window [entry]: switches
/// to a temporary wall tool, arms [entry] and shows a hint. Another tool
/// or leaving the temporary tool disarms it.
Future<void> armOpeningPlacement(
  BuildContext context,
  ObjectEntry entry,
) async {
  final bloc = context.read<DocumentBloc>();
  final controller = context.read<EditorController>();
  final hint = AppLocalizations.of(context).amazeTapWallToPlace;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final handler = await controller.toolCubit.changeTemporaryHandler(
    context,
    controller,
    WallTool(),
    bloc: bloc,
    temporaryState: TemporaryState.allowClick,
  );
  // Arm after the switch: replacing a wall tool disposes it, which disarms.
  if (handler == null) return;
  armOpening(entry);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(hint)));
}

/// The world position at the middle of the visible canvas.
Offset visibleCanvasCenter(BuildContext context) {
  final transform = context.read<TransformCubit>().state;
  final viewport = context
      .read<EditorController>()
      .rendererCubit
      .state
      .cameraViewport;
  var size = viewport.viewportSize ?? viewport.toRealSize();
  if (size.isEmpty) size = MediaQuery.sizeOf(context);
  return transform.localToGlobal(size.center(Offset.zero));
}
