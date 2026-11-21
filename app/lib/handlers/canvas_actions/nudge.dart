part of '../handler.dart';

/// Whether Nudge and Slice may change [element]: pen strokes only, and not
/// the walls and room outlines of a floor plan.
@visibleForTesting
bool isEditablePenStroke(PadElement element) =>
    element is PenElement &&
    element.id != null &&
    !element.extra.containsKey(kWallExtraKey) &&
    !element.extra.containsKey(kRoomExtraKey);

/// One drag step of Nudge on [points]: each point within [radius] of
/// [pointer] moves by [delta] × [strength] × (1 − d / R)². Returns null when
/// nothing moved.
@visibleForTesting
List<PathPoint>? nudgeStep(
  List<PathPoint> points,
  Offset pointer,
  double radius,
  Offset delta,
  double strength,
) {
  if (!strength.isFinite || strength <= 0) return null;
  return nudgePenPoints(points, pointer, radius, delta * strength.clamp(0, 1));
}

class CanvasNudgeHandler extends Handler<CanvasActionTool> {
  CanvasNudgeHandler(super.data);

  _NudgeGesture _gesture = _NudgeGesture(null);
  final Map<String, PenElement> _pending = {};
  final Map<String, PenElement> _originals = {};
  final Set<String> _moved = {};
  bool _disposed = false;
  Offset? _localPosition;

  double _screenRadius() {
    final radius = data.radius;
    return radius.isFinite && radius > 0 ? radius : 60;
  }

  double _radius(EventContext context) =>
      _screenRadius() / context.getTransformCubit().state.size;

  @override
  void onPointerHover(PointerHoverEvent event, EventContext context) {
    if (_disposed) return;
    _localPosition = event.localPosition;
    context.refreshForegrounds();
  }

  @override
  void onPointerDown(PointerDownEvent event, EventContext context) {
    if (_disposed) return;
    if (_gesture.pointer != null &&
        !_gesture.cancelled &&
        _gesture.pointer != event.pointer) {
      // A second finger: drop the preview, the viewport takes over.
      _gesture.cancel();
      _pending.clear();
      _originals.clear();
      _moved.clear();
      context.refreshForegrounds();
      return;
    }
    _gesture.cancel();
    _pending.clear();
    _originals.clear();
    _moved.clear();
    _gesture = _NudgeGesture(event.pointer);
    _localPosition = event.localPosition;
    final transform = context.getTransformCubit().state;
    final position = transform.localToGlobal(event.localPosition);
    _gesture.previousPosition = position;
    _requestCandidates(position, _radius(context), context, force: true);
    context.refreshForegrounds();
  }

  @override
  void onPointerMove(PointerMoveEvent event, EventContext context) {
    final gesture = _gesture;
    if (_disposed || gesture.cancelled || event.pointer != gesture.pointer) {
      return;
    }
    final transform = context.getTransformCubit().state;
    final position = transform.localToGlobal(event.localPosition);
    final previous = gesture.previousPosition;
    if (previous == null) return;
    final radius = _radius(context);
    final delta = position - previous;
    for (final entry in _pending.entries.toList()) {
      final points = nudgeStep(
        entry.value.points,
        previous,
        radius,
        delta,
        data.strength,
      );
      if (points == null) continue;
      _moved.add(entry.key);
      _pending[entry.key] = entry.value.copyWith(points: points);
    }
    gesture.previousPosition = position;
    _localPosition = event.localPosition;
    _requestCandidates(position, radius, context);
    context.refreshForegrounds();
  }

  void _requestCandidates(
    Offset position,
    double radius,
    EventContext context, {
    bool force = false,
  }) {
    final gesture = _gesture;
    if (gesture.cancelled || _disposed) return;
    final last = gesture.lastRayCast;
    if (!force && last != null && (position - last).distance <= radius / 2) {
      return;
    }
    gesture.lastRayCast = position;
    gesture.queuedRayCast = position;
    gesture.queuedContext = context;
    gesture.runningRayCast ??= Future<void>.microtask(() async {
      try {
        while (!gesture.cancelled && gesture.queuedRayCast != null) {
          final nextPosition = gesture.queuedRayCast!;
          final nextContext = gesture.queuedContext!;
          gesture.queuedRayCast = null;
          gesture.queuedContext = null;
          final locks = nextContext.getEditorController().viewCubit.state.locks;
          final hits = await nextContext.getDocumentBloc().rayCast(
            nextPosition,
            radius,
            useCollection: locks.lockCollection,
            useLayer: locks.lockLayer,
          );
          if (_disposed || gesture.cancelled) return;
          for (final hit in hits) {
            final element = hit.element;
            if (!isEditablePenStroke(element)) continue;
            element as PenElement;
            final id = element.id!;
            if (_pending.containsKey(id)) continue;
            _originals[id] = element;
            // Dense points bend smoothly instead of at one corner.
            _pending[id] = element.copyWith(
              points: densifyPenPoints(element.points, radius / 4),
            );
          }
          nextContext.refreshForegrounds();
        }
      } finally {
        gesture.runningRayCast = null;
        gesture.queuedRayCast = null;
        gesture.queuedContext = null;
      }
    });
  }

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) {
    final localPosition = _localPosition;
    final radius = _screenRadius() / editorController.transformCubit.state.size;
    return [
      ..._pending.values.map(Renderer.fromInstance),
      if (!_gesture.cancelled && localPosition != null)
        EraserCursor(ToolCursorData(EraserInfo(radius), localPosition)),
    ];
  }

  @override
  Map<String, RendererState> get rendererStates => Map.fromEntries(
    _pending.keys.map((id) => MapEntry(id, RendererState.hidden)),
  );

  @override
  void onPointerUp(PointerUpEvent event, EventContext context) {
    final gesture = _gesture;
    if (_disposed || gesture.cancelled || event.pointer != gesture.pointer) {
      return;
    }
    gesture.cancel();
    final changes = <String, List<PadElement>>{};
    for (final entry in _pending.entries) {
      final original = _originals[entry.key];
      if (_moved.contains(entry.key) &&
          original != null &&
          !const ListEquality<PathPoint>().equals(
            original.points,
            entry.value.points,
          )) {
        changes[entry.key] = [entry.value.copyWith(id: entry.key)];
      }
    }
    if (changes.isNotEmpty) {
      context.getDocumentBloc().add(
        ElementsChanged(changes, pageName: context.getState()?.pageName),
      );
    }
    _pending.clear();
    _originals.clear();
    _moved.clear();
    _gesture = _NudgeGesture(null);
    // Keep the circle where the pen is if it hovers next.
    if (event.kind == PointerDeviceKind.touch) _localPosition = null;
    context.refreshForegrounds();
  }

  @override
  void resetInput(DocumentBloc bloc) {
    _gesture.cancel();
    _gesture = _NudgeGesture(null);
    _pending.clear();
    _originals.clear();
    _moved.clear();
    _localPosition = null;
  }

  @override
  void dispose(DocumentBloc bloc) {
    _disposed = true;
    resetInput(bloc);
  }

  @override
  MouseCursor get cursor => SystemMouseCursors.none;
}
