part of 'handler.dart';

/// Draws [renderer] at [opacity], so a fading trail keeps its outline
/// instead of being rebuilt every frame.
class _FadingRenderer extends Renderer<PenElement> {
  _FadingRenderer(this.renderer, this.opacity) : super(renderer.element);

  final PenRenderer renderer;
  final double opacity;

  @override
  Rect? get rect => renderer.rect;

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
    if (opacity <= 0) return;
    if (opacity >= 1) {
      renderer.build(
        canvas,
        size,
        document,
        page,
        info,
        transform,
        colorScheme,
        foreground,
      );
      return;
    }
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    renderer.build(
      canvas,
      size,
      document,
      page,
      info,
      transform,
      colorScheme,
      foreground,
    );
    canvas.restore();
  }
}

/// How bright a laser trail is [t] (0–1) of the way through its fade:
/// quick at first, then easing out.
double laserFadeOpacity(double t) {
  final x = 1 - t.clamp(0.0, 1.0);
  return x * x;
}

class LaserHandler extends Handler<LaserTool> with ColoredHandler {
  /// One renderer per finished trail, kept while it fades.
  final Map<PenElement, PenRenderer> _fadeRenderers = Map.identity();
  bool _hideCursorWhileDrawing = false;
  final Map<int, PenElement> _elements = {};
  final List<PenElement> _submittedElements = [];
  DateTime? _lastChanged;
  Timer? _timer;

  LaserHandler(super.data);
  Duration _getDuration() =>
      Duration(milliseconds: (data.duration * 1000).round());
  Duration _getHideDuration() =>
      Duration(milliseconds: (data.hideDuration * 1000).round());
  Duration _getFullDuration() => _getDuration() + _getHideDuration();

  void _startTimer(DocumentBloc bloc) {
    _lastChanged = DateTime.now();
    _timer?.cancel();
    // Every frame, so the fade is smooth.
    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final DateTime now = .now();
      // Test if the last change was more than [duration] seconds ago
      final difference = now.difference(_lastChanged!);
      if (difference > _getFullDuration()) {
        _stopTimer();
      }
      // Fade out the elements
      bloc.refreshForegrounds();
    });
  }

  PenElement _updateElement(PenElement element, Duration difference) {
    final duration = _getDuration();
    final hideDuration = _getHideDuration();
    final double delta =
        ((difference - duration).inMilliseconds / hideDuration.inMilliseconds)
            .clamp(0, 1);
    if (data.animation == .path) {
      final points = element.points;
      final subPoints = points.sublist(
        (points.length * delta).round(),
        points.length,
      );
      return element.copyWith(points: subPoints);
    }
    var color = data.color;
    final toolAlpha = color.a;
    final alpha = ((1 - delta) * toolAlpha).clamp(0, 255).round();
    color = color.withValues(a: alpha);
    return element.copyWith(
      property: element.property.copyWith(
        paint: ElementPaint.solid(
          color: color,
          blur: element.property.paint.blur,
        ),
      ),
    );
  }

  List<PenElement> _getSubmitted() {
    final difference = _lastChanged == null
        ? Duration.zero
        : DateTime.now().difference(_lastChanged!);
    return _submittedElements
        .map((e) => _updateElement(e, difference))
        .toList();
  }

  void _stopTimer() {
    _lastChanged = null;
    _submittedElements.clear();
    _fadeRenderers.clear();
    _elements.clear();
    _timer?.cancel();
    _timer = null;
  }

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) => [
    ..._elements.values.map((e) {
      if (e.points.length > 1) return PenRenderer(e);
      return null;
    }).nonNulls,
    ...data.animation == .path
        ? _getSubmitted().map((e) => PenRenderer(e))
        : _fadingSubmitted(),
  ];

  Iterable<Renderer> _fadingSubmitted() {
    final last = _lastChanged;
    final difference = last == null
        ? Duration.zero
        : DateTime.now().difference(last);
    final hide = _getHideDuration().inMilliseconds;
    final t = hide <= 0
        ? (difference > _getDuration() ? 1.0 : 0.0)
        : (difference - _getDuration()).inMilliseconds / hide;
    final opacity = laserFadeOpacity(t);
    return _submittedElements.map(
      (element) => _FadingRenderer(
        _fadeRenderers[element] ??= PenRenderer(element),
        opacity,
      ),
    );
  }

  @override
  void resetInput(DocumentBloc bloc) {
    _submit(bloc, _elements.keys.toList());
    _elements.clear();
    _submittedElements.clear();
    _stopTimer();
  }

  @override
  void dispose(DocumentBloc bloc) {
    _stopTimer();
  }

  void _submit(DocumentBloc bloc, List<int> indexes) {
    final elements = indexes.map((e) => _elements.remove(e)).nonNulls.toList();
    if (elements.isEmpty) return;
    _submittedElements.addAll(elements);
    bloc.refreshForegrounds();
  }

  @override
  void onPointerUp(PointerUpEvent event, EventContext context) {
    addPoint(
      context.buildContext,
      event.pointer,
      event.localPosition,
      context.viewportSize,
      getPressureOfEvent(event),
      event.kind,
    );
    _submit(context.getDocumentBloc(), [event.pointer]);
  }

  void addPoint(
    BuildContext context,
    int pointer,
    Offset localPosition,
    Size viewportSize,
    double pressure,
    PointerDeviceKind kind, {
    bool forceCreate = false,
  }) {
    final bloc = context.read<DocumentBloc>();
    final editorController = context.read<EditorController>();
    final transform = context.read<TransformCubit>().state;
    final state = bloc.state as DocumentLoadSuccess;
    final penOnlyInput = editorController.inputCubit.effectivePenOnlyInput;
    localPosition = PointerManipulationHandler.calculatePointerPosition(
      editorController.toolCubit.state,
      localPosition,
      viewportSize,
      transform,
    );
    if (penOnlyInput && (kind != .stylus && kind != .invertedStylus)) {
      return;
    }
    if (!_elements.containsKey(pointer) && !forceCreate) {
      return;
    }
    final element =
        _elements[pointer] ??
        PenElement(
          collection: state.currentCollection,
          property: PenProperty(
            strokeWidth: data.strokeWidth / transform.size,
            thinning: data.thinning,
            paint: ElementPaint.solid(color: data.color),
            // The outline engine's curves: smooth, without corners.
            brush: brushById(_laserBrush) == null ? '' : _laserBrush,
            brushVersion: brushById(_laserBrush)?.version ?? 1,
          ),
          zoom: transform.size,
        );

    _elements[pointer] = element.copyWith(
      points: List<PathPoint>.from(element.points)
        ..add(
          PathPoint.fromPoint(
            transform.localToGlobal(localPosition).toPoint(),
            pressure,
          ),
        ),
    );
    bloc.refreshForegrounds();
    _startTimer(bloc);
  }

  @override
  void onPointerDown(PointerDownEvent event, EventContext context) {
    changeStartedDrawing(context);
    _hideCursorWhileDrawing = context.getSettings().hideCursorWhileDrawing;
    context.refreshForegrounds();
    final cubit = context.getEditorController();
    if (cubit.inputCubit.moveEnabled && event.kind != .stylus) {
      _elements.clear();
      return;
    }
    addPoint(
      context.buildContext,
      event.pointer,
      event.localPosition,
      context.viewportSize,
      event.pressure,
      event.kind,
      forceCreate: true,
    );
  }

  @override
  Future<void> onPointerMove(
    PointerMoveEvent event,
    EventContext context,
  ) async {
    addPoint(
      context.buildContext,
      event.pointer,
      event.localPosition,
      context.viewportSize,
      event.pressure,
      event.kind,
    );
  }

  @override
  SRGBColor getColor() => data.color;

  @override
  LaserTool setColor(SRGBColor color) => data.copyWith(color: color);

  @override
  double getStrokeWidth() => data.strokeWidth;

  @override
  LaserTool setStrokeWidth(double width) => data.copyWith(strokeWidth: width);

  @override
  MouseCursor get cursor => (_hideCursorWhileDrawing && _elements.isNotEmpty)
      ? SystemMouseCursors.none
      : SystemMouseCursors.precise;
}

const _laserBrush = 'amaze.fixed';
