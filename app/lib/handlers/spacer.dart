part of 'handler.dart';

/// Insert space: a drag moves everything beyond the cut (right of it for
/// the horizontal axis, below it for the vertical one) apart or together.
///
/// Elements only ever translate, so floor plan walls and rooms move whole
/// and are never stretched. The whole drag is one undo step.
class SpacerHandler extends Handler<SpacerTool> {
  Offset? _startPosition;
  Offset? _pointerLocal;
  Set<Renderer<PadElement>>? _renderers;
  double _spacing = 0.0;
  double _rotation = 0;

  /// Content bounds in viewport-aligned axes, taken once per drag.
  Rect? _bounds;

  Offset get _movement =>
      (data.axis == .horizontal ? Offset(_spacing, 0) : Offset(0, _spacing))
          .rotate(Offset.zero, -_rotation);

  SpacerHandler(super.data);

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) {
    final start = _startPosition;
    if (start == null) return [];
    final movement = _movement;
    final renderers = _renderers;
    final settings = editorController.settingsCubit.state;
    final scheme = getThemeData(settings.design, false).colorScheme;
    final local = _pointerLocal;
    return [
      SpacerRenderer(start, movement, axis: data.axis, rotation: _rotation),
      if (renderers != null && renderers.isNotEmpty)
        // One translation for everything that moves, no rebuilt elements.
        SelectionPreviewRenderer(
          renderers.toList(),
          Matrix4.translationValues(movement.dx, movement.dy, 0),
        ),
      if (local != null && _spacing != 0)
        MeasureBubble((
          position: local,
          text: formatLength(_spacing, measureUnitsOf(page)),
        ), scheme),
    ];
  }

  @override
  Map<String, RendererState> get rendererStates => Map.fromEntries(
    _renderers?.map((e) => MapEntry(e.id, RendererState.hidden)) ?? [],
  );

  Rect? _lastRect;

  Future<void>? _pendingRefresh;

  Future<void> _refreshRenderers(EventContext context) {
    final rect = _getRect(context);
    // The moving side depends only on where the cut is, so the ray cast
    // runs once per drag, not on every move.
    if (rect == _lastRect) return _pendingRefresh ?? Future.value();
    _lastRect = rect;
    if (rect == null) {
      _renderers = null;
      return Future.value();
    }
    final locks = context.getViewState().locks;
    return _pendingRefresh = context
        .getDocumentBloc()
        .rayCastRect(
          rect,
          rotation: -_rotation * 180 / pi,
          useCollection: locks.lockCollection,
          useLayer: locks.lockLayer,
        )
        .then((renderers) {
          if (rect == _lastRect) _renderers = renderers;
        });
  }

  @override
  bool onScaleStart(ScaleStartDetails details, EventContext context) {
    final transform = context.getCameraTransform();
    _startPosition = transform.localToGlobal(details.localFocalPoint);
    _pointerLocal = details.localFocalPoint;
    _rotation = transform.rotation;
    _spacing = 0;
    _renderers = null;
    _lastRect = null;
    _pendingRefresh = null;
    _bounds = null;
    context.refresh();
    return true;
  }

  @override
  void onScaleUpdate(ScaleUpdateDetails details, EventContext context) {
    if (details.pointerCount > 1) return;
    final transform = context.getCameraTransform();
    final globalPos = transform.localToGlobal(details.localFocalPoint);
    final start = _startPosition;
    if (start == null) return;
    _pointerLocal = details.localFocalPoint;
    final delta = (globalPos - start).rotate(Offset.zero, _rotation);
    _spacing = data.axis == .horizontal ? delta.dx : delta.dy;
    _refreshRenderers(context).whenComplete(context.refreshForegrounds);
    context.refreshForegrounds();
  }

  @override
  Future<void> onScaleEnd(ScaleEndDetails details, EventContext context) async {
    if (_startPosition == null) return;
    await _refreshRenderers(context);

    final movement = _movement;
    final elements = Map<String, List<PadElement>>.fromEntries(
      _renderers
              ?.map((e) {
                final id = e.element.id;
                if (id == null) return null;
                return MapEntry(id, [
                  e.transform(position: movement)?.element ?? e.element,
                ]);
              })
              .nonNulls
              .toList() ??
          [],
    );
    _startPosition = null;
    _pointerLocal = null;
    _spacing = 0.0;
    _renderers = null;
    _lastRect = null;
    _pendingRefresh = null;
    _bounds = null;
    await context.refresh();
    if (elements.isEmpty) return;
    context.getDocumentBloc().add(
      ElementsChanged(elements, pageName: context.getState()?.pageName),
    );
  }

  Rect? _contentBounds(EventContext context, Offset start) {
    final cached = _bounds;
    if (cached != null) return cached;
    // Bound the half-plane in viewport-aligned axes before rotating it back.
    // This keeps distant content eligible without rotating infinite corners.
    Rect? bounds;
    for (final renderer
        in context.getEditorController().rendererCubit.renderers) {
      final rect = renderer.expandedRect;
      if (rect == null) continue;
      if (_rotation == 0) {
        bounds = bounds?.expandToInclude(rect) ?? rect;
        continue;
      }
      for (final point in rect.toPolygon()) {
        final aligned = point.rotate(start, _rotation);
        final pointRect = Rect.fromPoints(aligned, aligned);
        bounds = bounds?.expandToInclude(pointRect) ?? pointRect;
      }
    }
    return _bounds = bounds;
  }

  Rect? _getRect(EventContext context) {
    final start = _startPosition;
    if (start == null || _spacing == 0) return null;
    final bounds = _contentBounds(context, start);
    if (bounds == null) return null;
    final halfPlane = data.axis == .horizontal
        ? Rect.fromLTRB(
            start.dx,
            -double.infinity,
            double.infinity,
            double.infinity,
          )
        : Rect.fromLTRB(
            -double.infinity,
            start.dy,
            double.infinity,
            double.infinity,
          );
    final rect = bounds.inflate(1).intersect(halfPlane);
    if (rect.isEmpty) return null;
    return rect.shift(rect.center.rotate(start, -_rotation) - rect.center);
  }
}

/// The cut of the spacer as a guide line across the view, the line where
/// it moves to, and the drag between them.
class SpacerRenderer extends Renderer {
  final Offset startPosition;
  final Offset movement;
  final Axis2D axis;

  /// The view rotation the drag started at.
  final double viewRotation;

  SpacerRenderer(
    this.startPosition,
    this.movement, {
    this.axis = Axis2D.horizontal,
    double rotation = 0,
  }) : viewRotation = rotation,
       super(null);

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
    final color = colorScheme?.primary ?? Colors.black;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4 / zoom
      ..style = PaintingStyle.stroke;
    canvas.drawLine(startPosition, startPosition + movement, paint);
    // The guide runs across the view, perpendicular to the axis.
    final along =
        (axis == Axis2D.horizontal ? const Offset(0, 1) : const Offset(1, 0))
            .rotate(Offset.zero, -viewRotation);
    final reach = (size.longestSide > 0 ? size.longestSide : 4000) / zoom * 2;
    final guide = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.5 / zoom
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      startPosition - along * reach,
      startPosition + along * reach,
      guide,
    );
    if (movement != Offset.zero) {
      final moved = startPosition + movement;
      final dashed = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..strokeWidth = 1.5 / zoom
        ..style = PaintingStyle.stroke;
      final dash = 8 / zoom, gap = 6 / zoom;
      for (var t = -reach; t < reach; t += dash + gap) {
        canvas.drawLine(moved + along * t, moved + along * (t + dash), dashed);
      }
    }
  }
}
