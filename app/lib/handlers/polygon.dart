part of 'handler.dart';

enum _PolygonDragTarget { point, handleIn, handleOut, newHandle }

/// The dashed preview of the next side of a polygon being drawn.
class PolygonNextSideRenderer extends Renderer<({Offset from, Offset to})> {
  PolygonNextSideRenderer(super.element, this.color);

  final Color color;

  @override
  Rect get rect => Rect.fromPoints(element.from, element.to);

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
    final zoom = transform.size > 0 ? transform.size : 1.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    final delta = element.to - element.from;
    final length = delta.distance;
    if (length == 0) return;
    final dash = 6 / zoom, gap = 5 / zoom;
    final direction = delta / length;
    for (var t = 0.0; t < length; t += dash + gap) {
      canvas.drawLine(
        element.from + direction * t,
        element.from + direction * min(t + dash, length),
        paint,
      );
    }
  }
}

/// Longest pause between the two taps that finish a polygon open.
const kPolygonDoubleTapTimeout = Duration(milliseconds: 300);

class PolygonSelectionRenderer extends Renderer<PolygonElement> {
  @override
  final Rect rect;
  final int? selectedPointIndex;

  PolygonSelectionRenderer(super.element, this.rect, this.selectedPointIndex);

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
    if (element.points.isEmpty) return;
    final strokeWidth = element.property.strokeWidth;

    for (var i = 0; i < element.points.length; i++) {
      final point = element.points[i];
      final isSelected = selectedPointIndex == i;
      final paint = Paint()
        ..color = colorScheme?.primary ?? Colors.blue
        ..style = isSelected ? PaintingStyle.fill : .stroke
        ..strokeWidth = strokeWidth / 2 / transform.size;
      final handlePaint = Paint()
        ..color = colorScheme?.secondary ?? Colors.green
        ..style = PaintingStyle.fill;
      final linePaint = Paint()
        ..color = colorScheme?.onSurface ?? Colors.grey
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth / transform.size;
      final handleIn = point.handleIn?.toPoint().toOffset();
      final handleOut = point.handleOut?.toPoint().toOffset();

      if (isSelected) {
        if (handleIn != null && handleOut != null) {
          canvas.drawLine(handleIn, handleOut, linePaint);
        }

        if (handleIn != null) {
          canvas.drawCircle(
            handleIn,
            strokeWidth / transform.size,
            handlePaint,
          );
        }
        if (handleOut != null) {
          canvas.drawCircle(
            handleOut,
            strokeWidth / transform.size,
            handlePaint,
          );
        }
      }

      final position = point.toPoint().toOffset();
      canvas.drawCircle(position, strokeWidth + 1.5 / transform.size, paint);
    }
  }
}

class PolygonHandler extends Handler<PolygonTool> with ColoredHandler {
  PolygonElement? _element;
  String? _elementId;
  int? _selectedPointIndex;
  _PolygonDragTarget _dragTarget = _PolygonDragTarget.newHandle;
  final _haptics = SnapHaptics();

  /// Where the next corner would go: snapped, in document space.
  Offset? _nextCorner;
  Offset? _pointerLocal;

  DateTime? _lastTapTime;
  Offset? _lastTapLocal;
  bool _lastTapAddedPoint = false;

  PolygonHandler(super.data);

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) {
    final element = _element;
    if (element == null) return [];
    final settings = editorController.settingsCubit.state;
    final scheme = getThemeData(settings.design, false).colorScheme;
    final points = element.points;
    final last = points.lastOrNull?.toPoint().toOffset();
    final next = _nextCorner;
    final transform = editorController.transformCubit.state;
    final units = measureUnitsOf(page);
    MeasureBubble? bubble;
    if (last != null && next != null && _elementId == null) {
      bubble = MeasureBubble((
        position: _pointerLocal ?? transform.globalToLocal(next),
        text: formatLengthAngle(next - last, units),
      ), scheme);
    } else if (points.length >= 2 && _elementId == null) {
      final previous = points[points.length - 2].toPoint().toOffset();
      bubble = MeasureBubble((
        position: transform.globalToLocal(last!),
        text: formatLengthAngle(last - previous, units),
      ), scheme);
    }
    return [
      PolygonRenderer(element),
      if (last != null && next != null && _elementId == null)
        PolygonNextSideRenderer((from: last, to: next), scheme.primary),
      if (_selectedPointIndex != null)
        PolygonSelectionRenderer(
          element,
          getSelectionRect(),
          _selectedPointIndex,
        ),
      ?bubble,
    ];
  }

  /// Corners a new corner snaps to: this polygon's and those of the other
  /// polygons on screen.
  Iterable<Offset> _snapCorners(EventContext context) sync* {
    final element = _element;
    if (element != null) {
      for (final point in element.points) {
        yield point.toPoint().toOffset();
      }
    }
    final controller = context.getEditorController();
    final transform = context.getCameraTransform();
    final screen = Offset.zero & context.viewportSize;
    final topLeft = transform.localToGlobal(screen.topLeft);
    final bottomRight = transform.localToGlobal(screen.bottomRight);
    final visible = Rect.fromPoints(topLeft, bottomRight);
    for (final renderer in controller.rendererCubit.visibleRenderers(visible)) {
      final other = renderer.element;
      if (other is! PolygonElement || other.id == element?.id) continue;
      for (final point in other.points) {
        yield point.toPoint().toOffset();
      }
    }
  }

  /// [globalPos] snapped to an existing corner within 12 screen px, or its
  /// side to a 15° step from the last corner.
  @visibleForTesting
  ({Offset point, bool snapped}) snapCorner(
    EventContext context,
    Offset globalPos,
  ) {
    final zoom = context.getCameraTransform().size;
    final points = _element?.points ?? const <PolygonPoint>[];
    final corner = snapToPoint(
      globalPos,
      _snapCorners(context).take(2000),
      tolerance: kSnapPointTolerance / (zoom > 0 ? zoom : 1),
    );
    if (corner.snapped) return corner;
    final last = points.lastOrNull?.toPoint().toOffset();
    if (last == null) return (point: globalPos, snapped: false);
    final side = snapSegment(last, globalPos);
    return (point: side.point, snapped: side.snapped);
  }

  @override
  void onPointerHover(PointerHoverEvent event, EventContext context) {
    final element = _element;
    if (element == null || element.points.isEmpty || _elementId != null) {
      return;
    }
    final globalPos = context.getCameraTransform().localToGlobal(
      event.localPosition,
    );
    final snapped = snapCorner(context, globalPos);
    _haptics.enabled = context.getSettings().snapHaptics;
    _haptics.update(snapped.snapped);
    _nextCorner = snapped.point;
    _pointerLocal = event.localPosition;
    context.refreshForegrounds();
  }

  @override
  bool onUndo(DocumentBloc bloc) {
    final element = _element;
    // Only while drawing a new polygon; edits of an existing one go
    // through the document's history.
    if (element == null || _elementId != null) return false;
    final points = element.points;
    if (points.length <= 1) {
      _resetTool();
    } else {
      _element = element.copyWith(points: points.sublist(0, points.length - 1));
      _selectedPointIndex = points.length - 2;
    }
    _nextCorner = null;
    unawaited(bloc.refreshForegrounds());
    bloc.refreshToolbar();
    return true;
  }

  Rect getSelectionRect() {
    return _element?.points.isEmpty ?? true
        ? Rect.zero
        : calculatePolygonRect(_element!.points);
  }

  @override
  SRGBColor getColor() => data.property.paint.previewColor;

  @override
  PolygonTool setColor(SRGBColor color) => data.copyWith(
    property: data.property.copyWith(
      paint: ElementPaint.solid(color: color, blur: data.property.paint.blur),
    ),
  );

  @override
  double getStrokeWidth() => data.property.strokeWidth;

  @override
  PolygonTool setStrokeWidth(double width) =>
      data.copyWith(property: data.property.copyWith(strokeWidth: width));

  void _changeTool(DocumentBloc bloc, PolygonTool tool) {
    final element = _element;
    if (element != null) {
      _element = element.copyWith(property: tool.property);
      unawaited(
        bloc.editorController.toolCubit.updateHandler(
          bloc,
          bloc.editorController.rendererCubit,
          this,
        ),
      );
      unawaited(bloc.refreshForegrounds());
      return;
    }
    changeTool(bloc, tool);
  }

  void _resetTool() {
    _elementId = null;
    _element = null;
    _selectedPointIndex = null;
    _nextCorner = null;
    _pointerLocal = null;
    _haptics.reset();
  }

  void addPoint(EventContext context, Offset localPos) {
    var globalPos = context.getCameraTransform().localToGlobal(localPos);
    if (_elementId == null) {
      final snapped = snapCorner(context, globalPos);
      globalPos = snapped.point;
      _haptics.enabled = context.getSettings().snapHaptics;
      if (snapped.snapped) _haptics.tick();
    }
    _nextCorner = null;
    var element =
        _element ??
        PolygonElement(
          points: [],
          property: data.property,
          id: createUniqueId(),
        );

    element = element.copyWith(
      points: [...element.points, PolygonPoint(globalPos.dx, globalPos.dy)],
    );
    _element = element;
    _selectedPointIndex = element.points.length - 1;
    context.refreshForegrounds();
    context.getDocumentBloc().refreshToolbar();
  }

  @override
  void onTapUp(TapUpDetails details, EventContext context) async {
    changeStartedDrawing(context);
    final localPos = details.localPosition;
    final transform = context.getCameraTransform();
    final globalPos = transform.localToGlobal(localPos);
    final bloc = context.getDocumentBloc();
    final now = DateTime.now();
    final lastTime = _lastTapTime, lastLocal = _lastTapLocal;
    final doubleTap =
        lastTime != null &&
        lastLocal != null &&
        now.difference(lastTime) <= kPolygonDoubleTapTimeout &&
        (localPos - lastLocal).distance <= 40;
    final element = _element;
    if (element != null && _elementId == null) {
      final points = element.points;
      // A double-tap finishes the polygon open at the corner its first
      // tap placed.
      if (doubleTap) {
        _lastTapTime = null;
        _lastTapLocal = null;
        if (!_lastTapAddedPoint) addPoint(context, localPos);
        _lastTapAddedPoint = false;
        await _finalizeElement(bloc);
        return;
      }
      // A tap on the first corner closes the polygon.
      if (points.length >= 3) {
        final first = points.first.toPoint().toOffset();
        if ((transform.globalToLocal(first) - localPos).distance <=
            kSnapPointTolerance) {
          _lastTapTime = null;
          _lastTapAddedPoint = false;
          await _finalizeElement(bloc, closeShape: true);
          return;
        }
      }
    }
    _lastTapTime = now;
    _lastTapLocal = localPos;
    _lastTapAddedPoint = false;
    if (_elementId == null && element != null && element.points.isNotEmpty) {
      // While drawing, a tap places the next corner, even on an old one.
      addPoint(context, localPos);
      _lastTapAddedPoint = true;
      return;
    }
    if (!_editPoint(globalPos, context)) {
      addPoint(context, localPos);
      _lastTapAddedPoint = true;
    }
  }

  @override
  bool canChange(PointerDownEvent event, EventContext context) {
    return false;
  }

  @override
  void onSecondaryTapUp(TapUpDetails details, EventContext context) async {
    changeStartedDrawing(context);
    final localPos = details.localPosition;
    final transform = context.getCameraTransform();
    final globalPos = transform.localToGlobal(localPos);
    if (!getSelectionRect()
        .inflate(2 * data.property.strokeWidth)
        .contains(globalPos)) {
      _submitElement(context.getDocumentBloc());
      return;
    }
    if (!_editPoint(globalPos, context)) {
      addPoint(context, localPos);
    }
  }

  bool _editPoint(Offset globalPos, EventContext context) {
    final element = _element;
    if (element == null || element.points.isEmpty) return false;
    final points = element.points;
    final zoomedStrokeWidth =
        data.property.strokeWidth / context.getCameraTransform().size;
    final touchSlop = max(
      20.0 / context.getCameraTransform().size,
      zoomedStrokeWidth * 2,
    );
    final closestIndex = points.indexWhere((point) {
      final offset = point.toPoint().toOffset();
      final distance = (offset - globalPos).distance;
      return distance <= touchSlop;
    });
    if (closestIndex == -1) return false;
    _selectedPointIndex = closestIndex;
    context.refreshForegrounds();
    return true;
  }

  @override
  bool onScaleStart(ScaleStartDetails details, EventContext context) {
    if (_selectedPointIndex == null || _element == null) return true;
    final point = _element!.points[_selectedPointIndex!];
    final globalPos = context.getCameraTransform().localToGlobal(
      details.localFocalPoint,
    );
    final zoomedStrokeWidth =
        data.property.strokeWidth / context.getCameraTransform().size;
    final touchSlop = max(
      20.0 / context.getCameraTransform().size,
      zoomedStrokeWidth * 2,
    );

    if (point.handleIn != null) {
      final hInOffset = point.handleIn!.toPoint().toOffset();
      if ((hInOffset - globalPos).distance <= touchSlop) {
        _dragTarget = _PolygonDragTarget.handleIn;
        return true;
      }
    }

    if (point.handleOut != null) {
      final hOutOffset = point.handleOut!.toPoint().toOffset();
      if ((hOutOffset - globalPos).distance <= touchSlop) {
        _dragTarget = _PolygonDragTarget.handleOut;
        return true;
      }
    }

    final pOffset = point.toPoint().toOffset();
    if ((pOffset - globalPos).distance <= touchSlop) {
      _dragTarget = _PolygonDragTarget.point;
      return true;
    }

    _dragTarget = _PolygonDragTarget.newHandle;
    return true;
  }

  @override
  void onScaleUpdate(ScaleUpdateDetails details, EventContext context) {
    super.onScaleUpdate(details, context);
    changeStartedDrawing(context);
    final selectedIndex = _selectedPointIndex;
    final element = _element;
    if (selectedIndex == null || element == null) return;

    final point = element.points[selectedIndex];
    final offset = point.toPoint().toOffset();
    final localPos = details.localFocalPoint;
    final globalPos = context.getCameraTransform().localToGlobal(localPos);

    PolygonPoint updatedPoint = point;

    if (_dragTarget == _PolygonDragTarget.point) {
      final diff = globalPos - offset;
      updatedPoint = point.copyWith(
        x: globalPos.dx,
        y: globalPos.dy,
        handleIn: point.handleIn != null
            ? SimplePoint(
                point.handleIn!.x + diff.dx,
                point.handleIn!.y + diff.dy,
              )
            : null,
        handleOut: point.handleOut != null
            ? SimplePoint(
                point.handleOut!.x + diff.dx,
                point.handleOut!.y + diff.dy,
              )
            : null,
      );
    } else if (_dragTarget == _PolygonDragTarget.handleIn) {
      final opposite = offset - (globalPos - offset);
      updatedPoint = point.copyWith(
        handleIn: SimplePoint(globalPos.dx, globalPos.dy),
        handleOut: SimplePoint(opposite.dx, opposite.dy),
      );
    } else if (_dragTarget == _PolygonDragTarget.handleOut) {
      final opposite = offset - (globalPos - offset);
      updatedPoint = point.copyWith(
        handleOut: SimplePoint(globalPos.dx, globalPos.dy),
        handleIn: SimplePoint(opposite.dx, opposite.dy),
      );
    } else {
      final opposite = offset - (globalPos - offset);
      updatedPoint = point.copyWith(
        handleIn: SimplePoint(globalPos.dx, globalPos.dy),
        handleOut: SimplePoint(opposite.dx, opposite.dy),
      );
    }

    final updatedPoints = List<PolygonPoint>.from(element.points)
      ..[selectedIndex] = updatedPoint;

    _element = element.copyWith(points: updatedPoints);
    context.refreshForegrounds();
  }

  @override
  void onLongPressEnd(LongPressEndDetails details, EventContext context) async {
    changeStartedDrawing(context);
    final localPos = details.localPosition;
    final transform = context.getCameraTransform();
    final globalPos = transform.localToGlobal(localPos);

    if (_element == null) {
      final locks = context.getViewState().locks;
      final hit = await context.getDocumentBloc().rayCast(
        globalPos,
        max(
          10.0 / context.getCameraTransform().size,
          data.property.strokeWidth / context.getCameraTransform().size * 2,
        ),
        useCollection: locks.lockCollection,
        useLayer: locks.lockLayer,
      );
      final polygonRenderer = hit.whereType<PolygonRenderer>().firstOrNull;
      if (polygonRenderer != null) {
        editElement(polygonRenderer.element);
        context.refreshForegrounds();
        context.getDocumentBloc().refreshToolbar();
        return;
      }
      addPoint(context, localPos);
      return;
    }

    if (!getSelectionRect()
        .inflate(2 * data.property.strokeWidth)
        .contains(globalPos)) {
      _submitElement(context.getDocumentBloc());
      return;
    }
    if (_editPoint(globalPos, context)) {
      final selectedIndex = _selectedPointIndex;
      final element = _element;
      if (selectedIndex == null || element == null) return;
      final point = element.points[selectedIndex];
      final updatedPoint = point.copyWith(handleIn: null, handleOut: null);
      final updatedPoints = List<PolygonPoint>.from(element.points)
        ..[selectedIndex] = updatedPoint;
      _element = element.copyWith(points: updatedPoints);
      context.refreshForegrounds();
      context.getDocumentBloc().refreshToolbar();
    } else {
      addPoint(context, localPos);
    }
  }

  @override
  void dispose(DocumentBloc bloc) {
    super.dispose(bloc);
    _submitElement(bloc);
  }

  Future<void> _finalizeElement(
    DocumentBloc bloc, {
    bool closeShape = false,
  }) async {
    final element = _element;
    if (element == null || element.points.isEmpty) {
      _submitElement(bloc);
      return;
    }

    if (closeShape && element.points.length > 2) {
      final first = element.points.first;
      final last = element.points.last;
      if ((first.toPoint().toOffset() - last.toPoint().toOffset()).distance >
          1.0) {
        _element = element.copyWith(points: [...element.points, first]);
      }
    }

    _selectedPointIndex = null;
    _dragTarget = _PolygonDragTarget.newHandle;
    unawaited(bloc.refreshForegrounds());
    _submitElement(bloc);
  }

  void _submitElement(DocumentBloc bloc) {
    final element = _element;
    if (element == null || element.points.isEmpty) {
      _resetTool();
      return;
    }
    final id = _elementId;
    if (id != null) {
      bloc.add(
        ElementsChanged({
          id: [element],
        }, pageName: bloc.state.pageName),
      );
    } else {
      bloc.add(
        ElementsCreated(
          [element],
          pageName: bloc.state.pageName,
          layer: bloc.state.currentLayer,
        ),
      );
    }
    _resetTool();
    bloc.editorController.toolCubit.resetTemporaryHandler(
      bloc,
      true,
      bloc.editorController.rendererCubit,
    );
    bloc.delayedBake();
    bloc.refreshToolbar();
  }

  void _deleteCurrentPoint(DocumentBloc bloc) {
    final element = _element;
    if (element == null) return;
    final selectedIndex = _selectedPointIndex;

    // If no point is selected, or we only have 1 point left, delete the entire element
    if (selectedIndex == null ||
        selectedIndex >= element.points.length ||
        element.points.length <= 1) {
      if (_elementId != null) {
        bloc.add(ElementsRemoved([_elementId!], pageName: bloc.state.pageName));
        bloc.refresh();
      }
      _resetTool();
      bloc.refreshForegrounds();
      bloc.refreshToolbar();
      bloc.editorController.toolCubit.resetTemporaryHandler(
        bloc,
        true,
        bloc.editorController.rendererCubit,
      );
      return;
    }

    final updatedPoints = List<PolygonPoint>.from(element.points)
      ..removeAt(selectedIndex);
    _element = element.copyWith(points: updatedPoints);
    if (_element?.points.isEmpty ?? true) {
      if (_elementId != null) {
        bloc.add(ElementsRemoved([_elementId!], pageName: bloc.state.pageName));
        bloc.refresh();
      }
      _resetTool();
      bloc.editorController.toolCubit.resetTemporaryHandler(
        bloc,
        true,
        bloc.editorController.rendererCubit,
      );
    } else {
      _selectedPointIndex = max(0, selectedIndex - 1);
    }
    bloc.refreshForegrounds();
    bloc.refreshToolbar();
  }

  @override
  PreferredSizeWidget? getToolbar(DocumentBloc bloc) {
    final element = _element;
    return PolygonToolbarView(
      bloc: bloc,
      tool: element == null ? data : data.copyWith(property: element.property),
      hasPoints: (element?.points.length ?? 0) > 0,
      onToolChanged: (tool) => _changeTool(bloc, tool),
      onFinishShape: _element == null
          ? null
          : () async {
              await _finalizeElement(bloc, closeShape: true);
            },
      onSubmit: _element == null
          ? null
          : () async {
              await _finalizeElement(bloc);
            },
      onDelete: () {
        _deleteCurrentPoint(bloc);
      },
    );
  }

  @override
  Map<String, RendererState> get rendererStates => {
    ?_element?.id: RendererState.hidden,
  };

  void editElement(PolygonElement element) {
    _resetTool();
    _element = element;
    _elementId = element.id;
    _selectedPointIndex = max(0, element.points.length - 1);
  }
}
