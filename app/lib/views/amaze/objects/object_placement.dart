import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

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
/// by [worldCenter]. Every element gets a new id.
List<PadElement> placeComponentAt(
  ButterflyComponent component,
  Offset worldCenter,
) {
  if (component.elements.isEmpty) return [];
  return transformComponentElements(
    component.elements.map(Renderer.fromInstance),
    Rect.zero,
    Rect.fromLTWH(worldCenter.dx, worldCenter.dy, 0, 0),
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
