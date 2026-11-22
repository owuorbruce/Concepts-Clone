part of 'handler.dart';

class SelectHandler extends Handler<SelectTool> {
  final _selectionManager = RectSelectionForegroundManager();
  List<Renderer<PadElement>> _selected = [];
  bool _duplicate = false;
  Offset? _rectangleFreeSelectionStart;
  RectSelectionForegroundRenderer? _rectangleFreeSelection;
  double _rectangleSelectionRotation = 0;
  List<Offset>? _lassoFreeSelection;
  ({Offset position, SelectionTransformCorner? corner})? _pendingTransform;
  final _haptics = SnapHaptics();
  Offset? _pointerGlobal;

  /// The pointer drawing the lasso, and its kind.
  int? _lassoPointer;
  PointerDeviceKind? _lassoKind;

  /// Finger touches that landed while a pen draws the lasso.
  final Set<int> _strayTouches = {};

  /// Elements the lasso would select now, for the live highlight.
  Set<Renderer<PadElement>> _lassoPreview = const {};
  bool _previewBusy = false, _previewDirty = false;
  DateTime _lastPreview = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether a lasso is being drawn.
  @visibleForTesting
  bool get isLassoActive => _lassoFreeSelection != null;

  /// The points of the lasso being drawn.
  @visibleForTesting
  List<Offset>? get lassoPoints => _lassoFreeSelection;

  /// The selected renderers, for tests.
  @visibleForTesting
  List<Renderer<PadElement>> get selected => List.unmodifiable(_selected);

  /// Renderer transforms made for previews, for tests: a move or rotation
  /// of many elements must not make new ones every frame.
  @visibleForTesting
  static int previewTransforms = 0;

  SelectHandler(super.data) {
    _selectionManager
      ..proportionalCorners = true
      ..rotationSnapStep = 15;
  }

  @override
  PreferredSizeWidget getToolbar(DocumentBloc bloc) => SelectToolbarView(
    tool: data,
    onToolChanged: (tool) => changeTool(bloc, tool),
  );

  /// Whether a drag from [globalPos] moves or transforms the selection: it
  /// starts on a handle or on a selected element. Anywhere else, even inside
  /// the selection's box, it draws a new lasso or rectangle.
  bool _startsTransform(
    Offset globalPos,
    CameraTransform transform,
    double sensitivity,
  ) {
    if (!_selectionManager.isValid) return false;
    final corner = _selectionManager.getCornerHit(
      globalPos,
      transform.size,
      sensitivity,
    );
    if (corner != null) return true;
    if (!_selectionManager.shouldTransform(
      globalPos,
      transform.size,
      sensitivity,
    )) {
      return false;
    }
    return _hitsSelectedElement(globalPos, transform.size);
  }

  /// Whether [globalPos] is on the visible shape of a selected element.
  bool _hitsSelectedElement(Offset globalPos, double zoom) {
    final scale = zoom.isFinite && zoom > 0 ? zoom : 1.0;
    final probe = Rect.fromCircle(
      center: globalPos,
      radius: kMinStrokeHitScreenPixels / scale,
    ).toPolygon();
    return _selected.any(
      (renderer) =>
          renderer.getHitCalculator().hitPolygonAt(probe, zoom: scale),
    );
  }

  @override
  void onPointerDown(PointerDownEvent event, EventContext context) {
    final lassoPointer = _lassoPointer;
    if (lassoPointer != null && event.pointer != lassoPointer) {
      // Finger touches never extend a pen's lasso; two of them pan and
      // zoom and cancel it. Any other second pointer cancels it.
      if (_lassoKind == PointerDeviceKind.stylus &&
          event.kind == PointerDeviceKind.touch) {
        _strayTouches.add(event.pointer);
        if (_strayTouches.length >= 2) cancelLasso(context);
      } else {
        cancelLasso(context);
      }
      return;
    }
    if (data.mode != .lasso || _selectionManager.isTransforming) return;
    if (context.getInputState().buttons == kSecondaryMouseButton) return;
    final transform = context.getCameraTransform();
    _syncSelectionRotation(transform);
    final globalPos = transform.localToGlobal(event.localPosition);
    if (_startsTransform(
      globalPos,
      transform,
      context.getSettings().touchSensitivity,
    )) {
      return;
    }
    // The pen-down point is the lasso's first point.
    _lassoPointer = event.pointer;
    _lassoKind = event.kind;
    _strayTouches.clear();
    _lassoPreview = const {};
    _lassoFreeSelection = [globalPos];
  }

  @override
  void onPointerMove(PointerMoveEvent event, EventContext context) {
    if (event.pointer != _lassoPointer) return;
    final points = _lassoFreeSelection;
    if (points == null) return;
    final globalPos = context.getCameraTransform().localToGlobal(
      event.localPosition,
    );
    if (points.last != globalPos) points.add(globalPos);
    _schedulePreview(context);
    context.refreshForegrounds();
  }

  /// Drops the lasso being drawn without changing the selection.
  void cancelLasso(EventContext context) {
    if (_lassoFreeSelection == null && _lassoPointer == null) return;
    _lassoFreeSelection = null;
    _lassoPointer = null;
    _lassoKind = null;
    _strayTouches.clear();
    _lassoPreview = const {};
    _previewDirty = false;
    context.refreshForegrounds();
  }

  /// [points] without the ones closer than [epsilon] to the line between
  /// their neighbours (Ramer–Douglas–Peucker).
  @visibleForTesting
  static List<Offset> simplifyLasso(List<Offset> points, double epsilon) {
    if (points.length < 3 || epsilon <= 0) return List.of(points);
    final keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;
    final stack = <(int, int)>[(0, points.length - 1)];
    while (stack.isNotEmpty) {
      final (first, last) = stack.removeLast();
      final a = points[first], b = points[last];
      final ab = b - a;
      final length = ab.distance;
      var maxDistance = 0.0;
      var index = -1;
      for (var i = first + 1; i < last; i++) {
        final p = points[i] - a;
        final distance = length == 0
            ? p.distance
            : (p.dx * ab.dy - p.dy * ab.dx).abs() / length;
        if (distance > maxDistance) {
          maxDistance = distance;
          index = i;
        }
      }
      if (index >= 0 && maxDistance > epsilon) {
        keep[index] = true;
        stack
          ..add((first, index))
          ..add((index, last));
      }
    }
    return [
      for (var i = 0; i < points.length; i++)
        if (keep[i]) points[i],
    ];
  }

  /// The lasso ready for hit testing at [zoom], or null when it is too
  /// small to mean anything: fewer than 3 points or under 16 screen px².
  @visibleForTesting
  static List<Offset>? prepareLasso(List<Offset> points, double zoom) {
    final scale = zoom.isFinite && zoom > 0 ? zoom : 1.0;
    final simplified = simplifyLasso(points, 1 / scale);
    if (simplified.length < 3) return null;
    var area = 0.0;
    for (var i = 0; i < simplified.length; i++) {
      final a = simplified[i], b = simplified[(i + 1) % simplified.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    if ((area / 2).abs() * scale * scale < 16) return null;
    return simplified;
  }

  Future<Set<Renderer<PadElement>>> _lassoHits(
    EventContext context,
    List<Offset> polygon,
  ) {
    final locks = context.getViewState().locks;
    return context.getDocumentBloc().rayCastPolygon(
      polygon,
      useCollection: locks.lockCollection,
      useLayer: locks.lockLayer,
      hitElementMode: data.hitElementMode,
    );
  }

  /// Updates the live highlight at most once per frame.
  void _schedulePreview(EventContext context) {
    if (_previewBusy) {
      _previewDirty = true;
      return;
    }
    _previewBusy = true;
    final wait =
        const Duration(milliseconds: 16) -
        DateTime.now().difference(_lastPreview);
    Future<void>.delayed(wait.isNegative ? Duration.zero : wait, () async {
      final points = _lassoFreeSelection;
      final polygon = points == null
          ? null
          : prepareLasso(points, context.getCameraTransform().size);
      if (polygon != null) {
        final hits = await _lassoHits(context, polygon);
        if (_lassoFreeSelection != null) _lassoPreview = hits;
      }
      _lastPreview = DateTime.now();
      _previewBusy = false;
      if (_lassoFreeSelection == null) return;
      context.refreshForegrounds();
      if (_previewDirty) {
        _previewDirty = false;
        _schedulePreview(context);
      }
    });
  }

  /// Selects what the lasso drew. Adding (Ctrl, Shift) keeps the old
  /// selection and never adds an element twice.
  Future<void> _finishLasso(EventContext context) async {
    final points = _lassoFreeSelection;
    _lassoFreeSelection = null;
    _lassoPointer = null;
    _lassoKind = null;
    _strayTouches.clear();
    _lassoPreview = const {};
    if (points == null) return;
    final polygon = prepareLasso(points, context.getCameraTransform().size);
    if (polygon == null) {
      context.refreshForegrounds();
      return;
    }
    final hits = await _lassoHits(context, polygon);
    _addToSelection(hits, add: context.isCtrlPressed || context.isShiftPressed);
    _updateSelectionRect();
    context.refresh();
  }

  void _addToSelection(
    Iterable<Renderer<PadElement>> hits, {
    bool add = false,
  }) {
    if (!add) _selected.clear();
    final ids = {for (final renderer in _selected) renderer.element.id};
    for (final hit in hits) {
      final id = hit.element.id;
      if (_selected.contains(hit) || (id != null && ids.contains(id))) {
        continue;
      }
      _selected.add(hit);
      ids.add(id);
    }
  }

  /// Where a move or rotation preview puts a point of the selection, or
  /// null while it scales (scaling keeps stroke widths, so it is previewed
  /// per element).
  @visibleForTesting
  Matrix4? previewMatrix() {
    final transform = _selectionManager.getTransform();
    if (transform == null || transform.scaleX != 1 || transform.scaleY != 1) {
      return null;
    }
    final angle = _selectionManager.rotation;
    final position = transform.position;
    final pivot = transform.scalePoint(
      _selectionManager.pivot,
      _selectionManager.selection,
    );
    final turn = transform.rotation * pi / 180;
    // p → R(angle) · Rotate(pivot, turn) · (R(-angle) · p + position),
    // the same as the per-element transform for moves and rotations.
    return Matrix4.identity()
      ..rotateZ(angle)
      ..translateByDouble(pivot.dx, pivot.dy, 0, 1)
      ..rotateZ(turn)
      ..translateByDouble(
        -pivot.dx + position.dx,
        -pivot.dy + position.dy,
        0,
        1,
      )
      ..rotateZ(-angle);
  }

  void transform(
    DocumentBloc bloc,
    SelectionTransformCorner? corner, {
    List<Renderer<PadElement>>? next,
    bool duplicate = false,
    Offset? position,
  }) {
    _clearFreeSelection();
    _selected = next ?? _selected;
    _submitTransform(bloc);
    _updateSelectionRect(-bloc.editorController.transformCubit.state.rotation);
    _selectionManager.startTransformWithCorner(corner, position);
    _duplicate = duplicate;
    bloc.refresh();
  }

  @override
  Map<String, RendererState> get rendererStates =>
      _selectionManager.isTransforming && !_duplicate
      ? Map.fromEntries(
          _selected.map((e) => MapEntry(e.id, RendererState.hidden)),
        )
      : {};

  Future<void> _resetSelectInput(DocumentBloc bloc) async {
    _submitTransform(bloc);
    _rectangleFreeSelectionStart = null;
    _rectangleFreeSelection = null;
    _lassoFreeSelection = null;
    _pendingTransform = null;
    _selectionManager.reset();
    await bloc.refresh(allowBake: false);
  }

  @override
  bool onRenderersCreated(DocumentPage page, List<Renderer> renderers) {
    var changed = false;
    _selected = _selected
        .map((e) {
          final renderer = renderers.firstWhereOrNull(
            (element) => element.element == e.element,
          );
          if (renderer is! Renderer<PadElement>) return e;
          changed = true;
          return renderer;
        })
        .nonNulls
        .toList();
    _updateSelectionRect();
    return changed;
  }

  @override
  void onRenderersReloaded(
    DocumentPage page,
    List<Renderer<PadElement>> renderers,
  ) {
    final renderersById = <String, Renderer<PadElement>>{};
    for (final renderer in renderers) {
      final id = renderer.element.id;
      if (id != null) renderersById[id] = renderer;
    }
    _selected = _selected
        .map((renderer) => renderersById[renderer.element.id])
        .nonNulls
        .toList();
    _updateSelectionRect();
  }

  @override
  bool onRendererUpdated(
    DocumentPage page,
    Renderer old,
    List<Renderer> updated,
  ) {
    bool changed = false;
    if (old is Renderer<PadElement> &&
        _selected.any((e) => e.id == old.id) &&
        updated is List<Renderer<PadElement>>) {
      _selected.removeWhere((e) => e.id == old.id);
      _selected.addAll(updated);
      changed = true;
      _updateSelectionRect();
    }
    return changed;
  }

  Rect? getSelectionRect() {
    Rect? rect;
    for (final element in _selected) {
      final current = element.expandedRect;
      if (current != null && !current.isEmpty) {
        rect = rect?.expandToInclude(current) ?? current;
      }
    }
    return rect;
  }

  void _updateSelectionRect([double? rotation]) {
    final angle = rotation ?? _selectionManager.rotation;
    Rect? bounds;
    for (final renderer in _selected) {
      final rect = renderer.rect;
      if (rect == null) continue;
      // Lines need non-zero selection dimensions for handles and resizing.
      // Pad local bounds before applying element and viewport transforms.
      final selectionRect = rect.isEmpty
          ? Rect.fromCenter(
              center: rect.center,
              width: max(rect.width, 2),
              height: max(rect.height, 2),
            )
          : rect;
      for (final corner in selectionRect.toPolygon()) {
        final point = renderer
            .transformPoint(corner)
            .rotate(Offset.zero, -angle);
        final pointRect = Rect.fromPoints(point, point);
        bounds = bounds?.expandToInclude(pointRect) ?? pointRect;
      }
    }

    if (_selected.isEmpty) {
      _selectionManager.reset();
    }

    _selectionManager.select(bounds, rotation: angle);
  }

  void _clearFreeSelection() {
    _rectangleFreeSelectionStart = null;
    _rectangleFreeSelection = null;
    _lassoFreeSelection = null;
  }

  void _syncSelectionRotation(CameraTransform camera) {
    if (!_selectionManager.isTransforming &&
        _selectionManager.rotation != -camera.rotation) {
      _updateSelectionRect(-camera.rotation);
    }
  }

  bool _isSelectionHit(
    Offset position,
    CameraTransform transform,
    double sensitivity,
  ) =>
      _selectionManager.isValid &&
      _selectionManager.shouldTransform(position, transform.size, sensitivity);

  List<Renderer<PadElement>>? _getTransformed() {
    final selectionRect = _selectionManager.selection;
    final pivot = _selectionManager.pivot;
    final transform = _selectionManager.getTransform();
    if (transform == null) return null;

    final angle = _selectionManager.rotation;
    final transformedPivot = transform.scalePoint(pivot, selectionRect);
    return _selected.map((renderer) {
      previewTransforms++;
      final center = (renderer.rect?.center ?? Offset.zero).rotate(
        Offset.zero,
        -angle,
      );
      final target = transform
          .scalePoint(center, selectionRect)
          .rotate(transformedPivot, transform.rotation * pi / 180)
          .rotate(Offset.zero, angle);
      return renderer.transform(
            center: target,
            scaleX: transform.scaleX,
            scaleY: transform.scaleY,
            scaleRotation: angle,
            rotation: transform.rotation,
            scaleStrokeWidth: data.proportionalResizing,
          ) ??
          renderer;
    }).toList();
  }

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) {
    _selectionManager.setForceProportional(data.proportionalResizing);

    _syncSelectionRotation(editorController.transformCubit.state);
    final foregrounds = <Renderer>[];
    // When transform just started but the pointer hasn't moved yet,
    // _getTransformed() returns null. Show originals as foregrounds
    // since rendererStates already hides them from the main layer.
    final matrix = _selectionManager.isTransforming ? previewMatrix() : null;
    if (matrix != null) {
      // Moves and rotations draw the selection under one transform.
      foregrounds.add(SelectionPreviewRenderer(_selected, matrix));
      foregrounds.addAll(
        maskTints(_selected.map((renderer) => renderer.element)),
      );
    } else {
      foregrounds.addAll(
        _getTransformed() ??
            (_selectionManager.isTransforming && !_duplicate ? _selected : []),
      );
      // Selected masks show as a faint gray, moved ones where they go.
      final shown = foregrounds.isNotEmpty
          ? foregrounds.map((renderer) => renderer.element)
          : _selected.map((renderer) => renderer.element);
      foregrounds.addAll(maskTints(shown.whereType<PadElement>()));
    }
    final selectionRect = getSelectionRect();
    final settings = editorController.settingsCubit.state;
    final scheme = getThemeData(settings.design, false).colorScheme;
    if (selectionRect != null) {
      foregrounds.add(_selectionManager.renderer);
    }
    if (_rectangleFreeSelection != null) {
      foregrounds.add(_rectangleFreeSelection!);
    }
    if (_lassoFreeSelection != null) {
      foregrounds.add(
        LassoSelectionForegroundRenderer(
          _lassoFreeSelection!,
          scheme,
          highlighted: _lassoPreview.toList(),
        ),
      );
    }
    final text = _measureText(page);
    final pointer = _pointerGlobal;
    if (text != null && pointer != null) {
      foregrounds.add(
        MeasureBubble((
          position: editorController.transformCubit.state.globalToLocal(
            pointer,
          ),
          text: text,
        ), scheme),
      );
    }
    return foregrounds;
  }

  /// The size while scaling and the angle while rotating, for the bubble.
  String? _measureText(DocumentPage page) {
    if (!_selectionManager.isScaling) return null;
    final transform = _selectionManager.getTransform();
    if (transform == null) return null;
    if (_selectionManager.corner == SelectionTransformCorner.center) {
      final total = _selectionManager.rotation + transform.rotation * pi / 180;
      return formatAngle(-total);
    }
    final rect = _selectionManager.getTransformedSelection();
    return formatSize(rect.width, rect.height, measureUnitsOf(page));
  }

  List<Renderer<PadElement>>? _submitTransform(DocumentBloc bloc) {
    if (!_selectionManager.isTransforming) return null;
    final state = bloc.state;
    if (state is! DocumentLoadSuccess) return null;
    final current = _getTransformed();
    _selectionManager.deselect();
    if (current == null) return null;
    if (_duplicate) {
      final elements = regenerateElementIds(
        current.map((e) => e.element),
        createUniqueId,
      );
      bloc.add(
        ElementsCreated(
          elements,
          pageName: bloc.state.pageName,
          layer: bloc.state.currentLayer,
        ),
      );
      return [];
    }

    if (state.settingsCubit.state.bringMovedElementsToFront) {
      bloc.add(
        ElementsArranged(
          Arrangement.front,
          current.map((e) => e.id).toList(),
          pageName: bloc.state.pageName,
        ),
      );
    }
    bloc.add(
      ElementsChanged(
        Map.fromEntries(
          current.mapIndexed((i, e) {
            final id = _selected[i].element.id;
            if (id == null) return null;
            return MapEntry(id, [e.element]);
          }).nonNulls,
        ),
        pageName: bloc.state.pageName,
      ),
    );
    return current;
  }

  @override
  void onTapUp(TapUpDetails details, EventContext context) async {
    final transform = context.getCameraTransform();
    _syncSelectionRotation(transform);
    final globalPos = transform.localToGlobal(details.localPosition);
    if (_selectionManager.isTransforming) {
      _updateTransformPosition(globalPos, context);
      _selected = _submitTransform(context.getDocumentBloc()) ?? _selected;
      return;
    }
    await _onSelectionAdd(context, details.localPosition, false);
  }

  @override
  void onLongPressEnd(LongPressEndDetails details, EventContext context) async {
    final transform = context.getCameraTransform();
    _syncSelectionRotation(transform);
    final globalPos = transform.localToGlobal(details.localPosition);
    final hitSelection = _isSelectionHit(
      globalPos,
      transform,
      context.getSettings().touchSensitivity,
    );
    if (!hitSelection) {
      await _onSelectionAdd(context, details.localPosition, true);
    }
    _onSelectionContext(context, details.localPosition);
  }

  Future<void> _onSelectionAdd(
    EventContext context,
    Offset localPosition, [
    bool forceAdd = false,
  ]) async {
    if (_selectionManager.isTransforming) {
      return;
    }
    final locks = context.getViewState().locks;
    final transform = context.getCameraTransform();
    _syncSelectionRotation(transform);
    final globalPos = transform.localToGlobal(localPosition);
    if (_selectionManager.contains(globalPos) &&
        _hitsSelectedElement(globalPos, transform.size)) {
      _selectionManager.toggleTransformMode();
      context.refresh();
      return;
    }
    _selectionManager.resetTransform();
    final settings = context.getSettings();
    final radius = settings.selectSensitivity / transform.size;
    final hits = await context.getDocumentBloc().rayCast(
      globalPos,
      radius,
      useCollection: locks.lockCollection,
      useLayer: locks.lockLayer,
    );
    if (hits.isEmpty) {
      if (!context.isCtrlPressed) {
        _selected.clear();
        _updateSelectionRect();
        context.refresh();
      }
      return;
    }
    final hit = hits.first;
    if (context.isCtrlPressed || forceAdd) {
      if (_selected.contains(hit)) {
        _selected.remove(hit);
      } else {
        _selected.add(hit);
      }
    } else {
      _selected.clear();
      _selected.add(hit);
    }
    _updateSelectionRect();
    context.refresh();
  }

  @override
  void onSecondaryTapUp(TapUpDetails details, EventContext context) async {
    _onSelectionContext(context, details.localPosition);
  }

  @override
  void onContextMenu(Offset localPosition, EventContext context) {
    final selectionRect = getSelectionRect();
    final position = selectionRect == null
        ? localPosition
        : context.getCameraTransform().globalToLocal(selectionRect.center);
    _onSelectionContext(context, position);
  }

  Future<void> _onSelectionContext(
    EventContext context,
    Offset localPosition,
  ) async {
    if (_selectionManager.isTransforming) {
      return;
    }
    final position = context.getCameraTransform().localToGlobal(localPosition);
    final bloc = context.getDocumentBloc();
    final state = bloc.state;
    if (state is! DocumentLoadSuccess) return;
    final locks = context.getViewState().locks;
    final hits = await bloc.rayCast(
      position,
      0.0,
      useCollection: locks.lockCollection,
      useLayer: locks.lockLayer,
    );
    final hit = hits.firstOrNull;
    final rect = hit?.expandedRect;
    final hitSelection = _isSelectionHit(
      position,
      context.getCameraTransform(),
      context.getSettings().touchSensitivity,
    );
    if ((rect != null && !hitSelection) && !context.isCtrlPressed) {
      _selected.clear();
      if (hit != null) _selected.add(hit);
    }
    context.refresh();
    final buildContext = context.buildContext;
    if (buildContext.mounted) {
      final result = await showContextMenu<bool>(
        context: buildContext,
        position: localPosition,
        builder: buildElementsContextMenu(
          bloc,
          state,
          context.getImportService(),
          context.getExportService(),
          context.getClipboardManager(),
          localPosition,
          _selected,
          getSelectionRect(),
        ),
      );
      if (result ?? false) {
        _selected.clear();
      }
    }
    context.refresh();
  }

  @override
  bool onScaleStart(ScaleStartDetails details, EventContext context) {
    final pendingTransform = _pendingTransform;
    _pendingTransform = null;
    final toolState = context.getToolState();
    final inputState = context.getInputState();
    if (inputState.buttons == kSecondaryMouseButton &&
        toolState.temporaryHandler == null) {
      return false;
    }
    final cameraTransform = context.getCameraTransform();
    _syncSelectionRotation(cameraTransform);
    final globalPos = cameraTransform.localToGlobal(details.localFocalPoint);
    if (_lassoFreeSelection != null) {
      // The lasso started at pen-down and follows its pointer.
      _rectangleFreeSelectionStart = null;
      return true;
    }
    final shouldTransform = _startsTransform(
      globalPos,
      cameraTransform,
      context.getSettings().touchSensitivity,
    );
    if (pendingTransform != null || shouldTransform) {
      transform(
        context.getDocumentBloc(),
        pendingTransform != null
            ? pendingTransform.corner
            : _selectionManager.getCornerHit(
                globalPos,
                cameraTransform.size,
                context.getSettings().touchSensitivity,
              ),
        position: pendingTransform?.position ?? globalPos,
      );
      return true;
    }
    _rectangleSelectionRotation = cameraTransform.rotation;
    _rectangleFreeSelectionStart = data.mode == .rectangle ? globalPos : null;
    context.refresh();
    return true;
  }

  @override
  bool canChange(PointerDownEvent event, EventContext context) {
    final cameraTransform = context.getCameraTransform();
    _syncSelectionRotation(cameraTransform);
    final globalPos = cameraTransform.localToGlobal(event.localPosition);
    final selectionRect = getSelectionRect();
    final shouldTransform = _startsTransform(
      globalPos,
      cameraTransform,
      context.getSettings().touchSensitivity,
    );
    if (shouldTransform) {
      _pendingTransform = (
        position: globalPos,
        corner: _selectionManager.getCornerHit(
          globalPos,
          cameraTransform.size,
          context.getSettings().touchSensitivity,
        ),
      );
    } else {
      _pendingTransform = null;
    }
    if (selectionRect != null && _selectionManager.contains(globalPos)) {
      return false;
    }
    if (shouldTransform) {
      return false;
    }
    return true;
  }

  void _updateTransformPosition(Offset position, EventContext context) {
    _pointerGlobal = position;
    final camera = context.getCameraTransform();
    _selectionManager.updateModifiers(
      proportional: context.isShiftPressed,
      centered: context.isAltPressed,
    );
    _selectionManager.updateCurrentPosition(
      position,
      snapPosition: (target) => camera.localToGlobal(
        PointerManipulationHandler.calculatePointerPosition(
          context.getToolState(),
          camera.globalToLocal(target),
          context.viewportSize,
          camera,
        ),
      ),
    );
  }

  @override
  void onScaleUpdate(ScaleUpdateDetails details, EventContext context) {
    final globalPos = context.getCameraTransform().localToGlobal(
      details.localFocalPoint,
    );
    if (details.pointerCount > 1) {
      if (_lassoKind != PointerDeviceKind.stylus) cancelLasso(context);
      return;
    }
    if (_selectionManager.isTransforming) {
      _updateTransformPosition(globalPos, context);
      if (_selectionManager.corner == SelectionTransformCorner.center) {
        _selectionManager.getTransform();
        _haptics.enabled = context.getSettings().snapHaptics;
        _haptics.update(_selectionManager.rotationSnapped);
      }
      context.refreshForegrounds();
      return;
    }
    final start = _rectangleFreeSelectionStart ?? globalPos;
    if (data.mode == .rectangle) {
      final angle = _rectangleSelectionRotation;
      final rect = Rect.fromPoints(start, globalPos.rotate(start, angle));
      _rectangleFreeSelection = RectSelectionForegroundRenderer(
        rect.shift(rect.center.rotate(start, -angle) - rect.center),
        rotation: -angle * 180 / pi,
      );
    } else {
      _rectangleFreeSelection = null;
    }
    // The lasso collects its own pointer's moves, see [onPointerMove].
    if (data.mode != .lasso) _lassoFreeSelection = null;
    context.refreshForegrounds();
  }

  @override
  void dispose(DocumentBloc bloc) {
    _submitTransform(bloc);
  }

  @override
  Future<void> onScaleEnd(ScaleEndDetails details, EventContext context) async {
    _pendingTransform = null;
    _pointerGlobal = null;
    _haptics.reset();

    final locks = context.getViewState().locks;

    final rectangleSelection = _rectangleFreeSelection;
    if (_lassoFreeSelection != null) {
      // A lasso ends with its pointer; finish it if that hasn't happened.
      await _finishLasso(context);
      return;
    }

    final transformed = _submitTransform(context.getDocumentBloc());

    _clearFreeSelection();
    context.refreshForegrounds();

    if (transformed != null) {
      _selected.clear();
      _selected.addAll(transformed);
      _updateSelectionRect();
      return;
    }

    if (rectangleSelection != null && !rectangleSelection.rect.isEmpty) {
      final hits = await context.getDocumentBloc().rayCastRect(
        rectangleSelection.rect,
        rotation: rectangleSelection.rotation,
        useCollection: locks.lockCollection,
        useLayer: locks.lockLayer,
        hitElementMode: data.hitElementMode,
      );
      _addToSelection(
        hits,
        add: context.isCtrlPressed || context.isShiftPressed,
      );
    } else {
      _updateSelectionRect();
      return;
    }

    _updateSelectionRect();
    context.refresh();
  }

  @override
  void onPointerHover(PointerHoverEvent event, EventContext context) {
    final transform = context.getCameraTransform();
    _syncSelectionRotation(transform);
    final globalPos = transform.localToGlobal(event.localPosition);
    _selectionManager
      ..updateCurrentPosition(globalPos)
      ..updateCursor(
        transform.size,
        context.getSettings().touchSensitivity,
        transform.rotation,
      );
    context.refreshForegrounds();
  }

  @override
  Future<void> onPointerUp(PointerUpEvent event, EventContext context) async {
    _strayTouches.remove(event.pointer);
    if (event.pointer == _lassoPointer) await _finishLasso(context);
    final focus = Focus.maybeOf(context.buildContext);
    focus?.requestFocus();
  }

  @override
  Future<void> resetInput(DocumentBloc bloc) async {
    // An interrupted gesture drops the lasso without changing anything.
    _lassoFreeSelection = null;
    _lassoPointer = null;
    _lassoKind = null;
    _strayTouches.clear();
    _lassoPreview = const {};
    await _resetSelectInput(bloc);
  }

  @override
  MouseCursor? get cursor => _selectionManager.cursor;

  Future<void> copySelection(
    DocumentBloc bloc,
    ClipboardManager clipboardManager, [
    bool cut = false,
  ]) async {
    final state = bloc.state;
    if (state is! DocumentLoadSuccess) return;
    if (cut) {
      bloc.add(
        ElementsRemoved(
          _selected.map((r) => r.element.id).nonNulls.toList(),
          pageName: bloc.state.pageName,
        ),
      );
    }
    final point = getSelectionRect()?.topLeft;
    if (point == null) return;
    writeClipboardData(
      clipboardManager,
      AssetFileType.page,
      Uint8List.fromList(
        utf8.encode(
          json.encode(
            DocumentPage(
              layers: [
                DocumentLayer(
                  id: createUniqueId(),
                  content: _selected
                      .map(
                        (e) =>
                            (e.transform(position: -point, relative: true) ?? e)
                                .element,
                      )
                      .toList(),
                ),
              ],
            ).toDataJson(state.data),
          ),
        ),
      ),
    );
    _selected.clear();
    bloc.refresh();
  }

  void selectAll(
    DocumentBloc bloc, [
    bool Function(Renderer<PadElement>)? filter,
  ]) {
    final state = bloc.state;
    if (state is! DocumentLoadSuccess) return;
    _selected.clear();
    _selected.addAll(
      bloc.editorController.rendererCubit.renderers.where(
        (e) => filter?.call(e) ?? true,
      ),
    );
    _updateSelectionRect();
    bloc.refreshForegrounds();
  }

  @override
  Map<Type, Action<Intent>> getActions(BuildContext context) {
    final bloc = context.read<DocumentBloc>();
    final clipboardManager = context.read<ClipboardManager>();

    return {
      ...super.getActions(context),
      SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
        onInvoke: (intent) => selectAll(bloc),
      ),
      DeleteCharacterIntent: CallbackAction<DeleteCharacterIntent>(
        onInvoke: (intent) {
          final state = bloc.state;
          if (state is! DocumentLoadSuccess) return null;
          context.read<DocumentBloc>().add(
            ElementsRemoved(
              _selected.map((r) => r.element.id).nonNulls.toList(),
              pageName: bloc.state.pageName,
            ),
          );
          _selected.clear();
          bloc.refreshForegrounds();
          return null;
        },
      ),
      CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
        onInvoke: (intent) {
          copySelection(bloc, clipboardManager, intent.collapseSelection);
          return null;
        },
      ),
    };
  }

  void clearSelection(DocumentBloc bloc) {
    _selected.clear();
    _updateSelectionRect();
    bloc.refreshForegrounds();
  }
}
