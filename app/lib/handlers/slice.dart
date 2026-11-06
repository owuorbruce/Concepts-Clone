part of 'handler.dart';

const kSliceDisplayIcon = 'amaze.slice';

/// Splits a pen path wherever it crosses an open cut polyline.
///
/// Returns null if there are no crossings. Both sides of each split share
/// the same interpolated point, so no part of the stroke is erased.
@visibleForTesting
List<List<PathPoint>>? splitPenPointsAtCut(
  List<PathPoint> points,
  List<Offset> cut,
) {
  if (points.length < 2 || cut.length < 2) return null;
  if (points.any(
        (point) =>
            !point.x.isFinite || !point.y.isFinite || !point.pressure.isFinite,
      ) ||
      cut.any((point) => !point.dx.isFinite || !point.dy.isFinite)) {
    return null;
  }

  final pieces = <List<PathPoint>>[];
  var current = <PathPoint>[points.first];
  double? lastSplitPosition;

  for (var i = 1; i < points.length; i++) {
    final start = points[i - 1];
    final end = points[i];
    final origin = Offset(start.x, start.y);
    final stroke = Offset(end.x - start.x, end.y - start.y);
    final crossings = <({double fraction, PathPoint point})>[];

    for (var j = 1; j < cut.length; j++) {
      final cutStart = cut[j - 1];
      final direction = cut[j] - cutStart;
      final denominator = stroke.dx * direction.dy - stroke.dy * direction.dx;
      if (denominator == 0) continue; // Parallel or collinear.

      final delta = cutStart - origin;
      final fraction =
          (delta.dx * direction.dy - delta.dy * direction.dx) / denominator;
      final cutFraction =
          (delta.dx * stroke.dy - delta.dy * stroke.dx) / denominator;
      if (!fraction.isFinite ||
          !cutFraction.isFinite ||
          fraction < 0 ||
          fraction > 1 ||
          cutFraction < 0 ||
          cutFraction > 1) {
        continue;
      }
      // A cut at either end of the entire stroke cannot create two pieces.
      if ((i == 1 && fraction == 0) ||
          (i == points.length - 1 && fraction == 1)) {
        continue;
      }

      crossings.add((
        fraction: fraction,
        point: PathPoint(
          start.x + stroke.dx * fraction,
          start.y + stroke.dy * fraction,
          start.pressure + (end.pressure - start.pressure) * fraction,
        ),
      ));
    }

    crossings.sort((a, b) => a.fraction.compareTo(b.fraction));
    for (final crossing in crossings) {
      final position = (i - 1).toDouble() + crossing.fraction;
      // Adjacent cut segments can meet at the same intersection.
      if (lastSplitPosition != null &&
          (position - lastSplitPosition).abs() < 1e-9) {
        continue;
      }

      final point = crossing.point;
      final previous = current.last;
      if (previous.x != point.x ||
          previous.y != point.y ||
          previous.pressure != point.pressure) {
        current.add(point);
      }
      if (current.length < 2) continue;
      pieces.add(current);
      current = [point];
      lastSplitPosition = position;
    }

    final previous = current.last;
    if (previous.x != end.x ||
        previous.y != end.y ||
        previous.pressure != end.pressure) {
      current.add(end);
    }
  }

  if (pieces.isEmpty || current.length < 2) return null;
  pieces.add(current);
  return pieces;
}

class _SliceGesture {
  _SliceGesture(this.pointer);

  final int? pointer;
  final List<Offset> cut = [];
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    cut.clear();
  }
}

class SliceHandler extends Handler<EraserTool> {
  _SliceGesture _gesture = _SliceGesture(null);
  bool _disposed = false;

  SliceHandler(super.data);

  void _record(Offset localPosition, EventContext context) {
    final transform = context.getEditorController().transformCubit.state;
    _gesture.cut.add(transform.localToGlobal(localPosition));
    context.refreshForegrounds();
  }

  @override
  void onPointerDown(PointerDownEvent event, EventContext context) {
    if (_disposed) return;
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
    return [SliceForegroundRenderer(List<Offset>.of(_gesture.cut), scheme)];
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
      final candidates = <String, PenElement>{};

      for (var i = 1; i < cut.length; i++) {
        final start = cut[i - 1];
        final end = cut[i];
        final steps = max(1, ((end - start).distance / 8).ceil());
        for (var step = 0; step <= steps; step++) {
          final position = Offset.lerp(start, end, step / steps)!;
          final hits = await bloc.rayCast(
            position,
            8,
            useCollection: locks.lockCollection,
            useLayer: locks.lockLayer,
            hitElementMode: data.hitElementMode,
          );
          if (_disposed || gesture.cancelled) return;
          for (final hit in hits) {
            final element = hit.element;
            if (element is PenElement && element.id != null) {
              candidates[element.id!] = element;
            }
          }
        }
      }

      if (_disposed || gesture.cancelled) return;
      final changes = <String, List<PadElement>>{};
      for (final entry in candidates.entries) {
        final element = entry.value;
        final pieces = splitPenPointsAtCut(element.points, cut);
        if (pieces == null) continue;
        changes[entry.key] = [
          for (final piece in pieces)
            element.copyWith(points: piece, id: createUniqueId()),
        ];
      }
      if (changes.isNotEmpty && !gesture.cancelled && !_disposed) {
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
