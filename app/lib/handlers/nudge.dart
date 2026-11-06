part of 'handler.dart';

const kNudgeDisplayIcon = 'amaze.nudge';

bool isNudgeTool(Tool tool) => tool.displayIcon == kNudgeDisplayIcon;

@visibleForTesting
List<PathPoint> densifyPenPoints(List<PathPoint> points, double maxSegment) {
  if (points.length < 2 || !maxSegment.isFinite || maxSegment <= 0) {
    return points;
  }

  final result = <PathPoint>[points.first];
  for (var i = 1; i < points.length; i++) {
    final start = points[i - 1];
    final end = points[i];
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final distance = sqrt(dx * dx + dy * dy);
    final segments = (distance / maxSegment).ceil();
    for (var segment = 1; segment < segments; segment++) {
      final fraction = segment / segments;
      result.add(
        PathPoint(
          start.x + dx * fraction,
          start.y + dy * fraction,
          start.pressure + (end.pressure - start.pressure) * fraction,
        ),
      );
    }
    result.add(end);
  }
  return result;
}

@visibleForTesting
List<PathPoint>? nudgePenPoints(
  List<PathPoint> points,
  Offset center,
  double radius,
  Offset delta,
) {
  if (!radius.isFinite ||
      radius <= 0 ||
      !center.dx.isFinite ||
      !center.dy.isFinite ||
      !delta.dx.isFinite ||
      !delta.dy.isFinite) {
    return null;
  }

  var changed = false;
  final result = <PathPoint>[];
  for (final point in points) {
    final offset = Offset(point.x, point.y);
    final distance = (offset - center).distance;
    if (distance >= radius) {
      result.add(point);
      continue;
    }
    final weight = pow(1 - distance / radius, 2).toDouble();
    result.add(
      PathPoint(
        point.x + delta.dx * weight,
        point.y + delta.dy * weight,
        point.pressure,
      ),
    );
    changed = true;
  }
  return changed ? result : null;
}

class _NudgeGesture {
  _NudgeGesture(this.pointer);

  final int? pointer;
  bool cancelled = false;
  Offset? previousPosition;
  Offset? lastRayCast;
  Offset? queuedRayCast;
  EventContext? queuedContext;
  Future<void>? runningRayCast;

  void cancel() {
    cancelled = true;
    queuedRayCast = null;
    queuedContext = null;
  }
}

class NudgeHandler extends Handler<HandTool> {
  static const double _screenRadius = 48;

  NudgeHandler(super.data);

  _NudgeGesture _gesture = _NudgeGesture(null);
  final Map<String, PenElement> _pending = {};
  final Map<String, PenElement> _originals = {};
  bool _disposed = false;
  Offset? _localPosition;

  double _radius(EventContext context) {
    final transform = context.getEditorController().transformCubit.state;
    return _screenRadius / transform.size;
  }

  @override
  void onPointerDown(PointerDownEvent event, EventContext context) {
    if (_disposed) return;
    _gesture.cancel();
    _pending.clear();
    _originals.clear();
    _gesture = _NudgeGesture(event.pointer);
    _localPosition = event.localPosition;
    final transform = context.getEditorController().transformCubit.state;
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
    final transform = context.getEditorController().transformCubit.state;
    final position = transform.localToGlobal(event.localPosition);
    final previous = gesture.previousPosition;
    if (previous == null) return;
    final radius = _radius(context);
    final delta = position - previous;
    for (final entry in _pending.entries.toList()) {
      final points = nudgePenPoints(
        entry.value.points,
        previous,
        radius,
        delta,
      );
      if (points != null) {
        _pending[entry.key] = entry.value.copyWith(points: points);
      }
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
            final id = element.id;
            if (element is! PenElement ||
                id == null ||
                _pending.containsKey(id)) {
              continue;
            }
            _originals[id] = element;
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
    final radius = _screenRadius / editorController.transformCubit.state.size;
    return [
      if (!_gesture.cancelled && localPosition != null)
        EraserCursor(ToolCursorData(EraserInfo(radius), localPosition)),
      ..._pending.values.map(Renderer.fromInstance),
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
      if (original != null &&
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
    _clear(context);
  }

  void _clear(EventContext context) {
    _pending.clear();
    _originals.clear();
    _localPosition = null;
    _gesture = _NudgeGesture(null);
    context.refreshForegrounds();
  }

  @override
  void resetInput(DocumentBloc bloc) {
    _gesture.cancel();
    _gesture = _NudgeGesture(null);
    _pending.clear();
    _originals.clear();
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
