part of '../handler.dart';

/// The changes of one slice along [cut]: every editable stroke of
/// [candidates] that the cut crosses, mapped to its pieces. Pieces keep the
/// stroke's property, extra and collection and get new ids from [newId].
/// Empty when nothing was crossed.
@visibleForTesting
Map<String, List<PadElement>> sliceElements(
  Iterable<PadElement> candidates,
  List<Offset> cut, {
  String Function()? newId,
}) {
  final changes = <String, List<PadElement>>{};
  final createId = newId ?? createUniqueId;
  for (final element in candidates) {
    if (!isEditablePenStroke(element)) continue;
    element as PenElement;
    final pieces = splitPenPointsAtCut(element.points, cut);
    if (pieces == null) continue;
    final kept = pieces.where((piece) => piece.length >= 2).toList();
    if (kept.length < 2) continue;
    changes[element.id!] = [
      for (final piece in kept)
        element.copyWith(
          points: piece,
          id: createId(),
          extra: brushPieceExtra(element, piece),
        ),
    ];
  }
  return changes;
}

/// A thin dashed line along the path of the Slice tool.
class DashedCutRenderer extends Renderer<List<Offset>> {
  DashedCutRenderer(super.element, this.scheme);

  final ColorScheme scheme;

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
    if (element.length < 2) return;
    final scale = transform.size;
    final dash = 6 / scale;
    final gap = 4 / scale;
    final path = Path();
    var drawing = true;
    var left = dash;
    for (var i = 1; i < element.length; i++) {
      var start = element[i - 1];
      final end = element[i];
      var length = (end - start).distance;
      if (length <= 0) continue;
      final direction = (end - start) / length;
      if (drawing) path.moveTo(start.dx, start.dy);
      while (length > 0) {
        final step = min(left, length);
        final next = start + direction * step;
        if (drawing) path.lineTo(next.dx, next.dy);
        start = next;
        length -= step;
        left -= step;
        if (left <= 1e-9) {
          drawing = !drawing;
          left = drawing ? dash : gap;
          if (drawing) path.moveTo(start.dx, start.dy);
        }
      }
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    // A light halo keeps the line readable on dark strokes.
    canvas.drawPath(
      path,
      paint
        ..color = scheme.surface.withValues(alpha: 0.8)
        ..strokeWidth = 3 / scale,
    );
    canvas.drawPath(
      path,
      paint
        ..color = scheme.primary
        ..strokeWidth = 1.25 / scale,
    );
  }
}

class CanvasSliceHandler extends Handler<CanvasActionTool> {
  CanvasSliceHandler(super.data);

  _SliceGesture _gesture = _SliceGesture(null);
  bool _disposed = false;

  void _record(Offset localPosition, EventContext context) {
    final transform = context.getTransformCubit().state;
    _gesture.cut.add(transform.localToGlobal(localPosition));
    context.refreshForegrounds();
  }

  @override
  void onPointerDown(PointerDownEvent event, EventContext context) {
    if (_disposed) return;
    if (_gesture.pointer != null &&
        !_gesture.cancelled &&
        _gesture.pointer != event.pointer) {
      _gesture.cancel();
      context.refreshForegrounds();
      return;
    }
    _gesture.cancel();
    _gesture = _SliceGesture(event.pointer);
    _record(event.localPosition, context);
  }

  @override
  void onPointerMove(PointerMoveEvent event, EventContext context) {
    if (_disposed || _gesture.cancelled || event.pointer != _gesture.pointer) {
      return;
    }
    _record(event.localPosition, context);
  }

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) {
    if (_gesture.cancelled || _gesture.cut.length < 2) return [];
    final scheme = getThemeData(
      editorController.settingsCubit.state.design,
      false,
    ).colorScheme;
    return [DashedCutRenderer(List<Offset>.of(_gesture.cut), scheme)];
  }

  @override
  Future<void> onPointerUp(PointerUpEvent event, EventContext context) async {
    if (_disposed || _gesture.cancelled || event.pointer != _gesture.pointer) {
      return;
    }
    final gesture = _gesture;
    _record(event.localPosition, context);
    final cut = List<Offset>.of(gesture.cut);

    try {
      if (cut.length < 2 || context.getPage() == null) return;
      final bloc = context.getDocumentBloc();
      final locks = context.getEditorController().viewCubit.state.locks;
      final candidates = <String, PadElement>{};
      final reach = 8 / context.getTransformCubit().state.size;

      for (var i = 1; i < cut.length; i++) {
        final start = cut[i - 1];
        final end = cut[i];
        final steps = max(1, ((end - start).distance / reach).ceil());
        for (var step = 0; step <= steps; step++) {
          final position = Offset.lerp(start, end, step / steps)!;
          final hits = await bloc.rayCast(
            position,
            reach,
            useCollection: locks.lockCollection,
            useLayer: locks.lockLayer,
          );
          if (_disposed || gesture.cancelled) return;
          for (final hit in hits) {
            final id = hit.element.id;
            if (id != null) candidates[id] = hit.element;
          }
        }
      }

      if (_disposed || gesture.cancelled) return;
      final changes = sliceElements(candidates.values, cut);
      if (changes.isNotEmpty) {
        bloc.add(
          ElementsChanged(changes, pageName: context.getState()?.pageName),
        );
      }
    } finally {
      gesture.cut.clear();
      if (!_disposed && identical(_gesture, gesture)) {
        context.refreshForegrounds();
      }
    }
  }

  @override
  void resetInput(DocumentBloc bloc) {
    _gesture.cancel();
    _gesture = _SliceGesture(null);
  }

  @override
  void dispose(DocumentBloc bloc) {
    _disposed = true;
    resetInput(bloc);
  }
}
