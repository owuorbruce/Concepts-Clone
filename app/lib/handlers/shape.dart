part of 'handler.dart';

Offset snapLineEndPosition(Offset start, Offset end) {
  final delta = end - start;
  final length = delta.distance;
  if (length == 0) return end;

  final direction = (delta.direction / (pi / 4)).round() % 8;
  final diagonal = length / sqrt2;
  final snappedDelta = switch (direction) {
    0 => Offset(length, 0),
    1 => Offset(diagonal, diagonal),
    2 => Offset(0, length),
    3 => Offset(-diagonal, diagonal),
    4 => Offset(-length, 0),
    5 => Offset(-diagonal, -diagonal),
    6 => Offset(0, -length),
    7 => Offset(diagonal, -diagonal),
    _ => Offset(length, 0),
  };
  return start + snappedDelta;
}

/// Relative difference of width and height below which a rectangle or
/// circle becomes a square or a round circle.
const kShapeSquareTolerance = 0.04;

/// The second corner of a shape drag from [first] to [second], snapped:
/// lines to 15° steps, rectangles and circles to square and round when
/// their sides are within 4 % of each other. With [perfect] (after a hold)
/// a line always takes the nearest 15° step, a rectangle or circle becomes
/// square and a triangle equilateral.
({Offset second, bool snapped}) snapShapeDrag(
  PathShape shape,
  Offset first,
  Offset second, {
  bool perfect = false,
}) {
  final delta = second - first;
  switch (shape) {
    case LineShape():
      final result = snapSegment(
        first,
        second,
        tolerance: perfect ? kSnapAngleStep / 2 : kSnapAngleTolerance,
      );
      return (second: result.point, snapped: result.snapped);
    case RectangleShape() || CircleShape():
      final width = delta.dx.abs(), height = delta.dy.abs();
      final largest = max(width, height);
      if (largest == 0) return (second: second, snapped: false);
      if (!perfect &&
          (width - height).abs() > largest * kShapeSquareTolerance) {
        return (second: second, snapped: false);
      }
      final sx = delta.dx < 0 ? -1.0 : 1.0, sy = delta.dy < 0 ? -1.0 : 1.0;
      return (
        second: first + Offset(largest * sx, largest * sy),
        snapped: true,
      );
    case TriangleShape():
      if (!perfect || delta.dx == 0) return (second: second, snapped: false);
      final sy = delta.dy < 0 ? -1.0 : 1.0;
      final height = delta.dx.abs() * sqrt(3) / 2;
      return (second: Offset(second.dx, first.dy + height * sy), snapped: true);
  }
}

/// What the measure bubble shows for a [shape] from [first] to [second].
String shapeMeasureText(
  PathShape shape,
  Offset first,
  Offset second, [
  MeasureUnits units = MeasureUnits.pixels,
  bool fromCenter = false,
]) {
  final delta = second - first;
  final scale = fromCenter ? 2.0 : 1.0;
  final width = delta.dx.abs() * scale, height = delta.dy.abs() * scale;
  return switch (shape) {
    LineShape() => formatLengthAngle(delta * scale, units),
    CircleShape() when (width - height).abs() < 1e-6 =>
      '⌀ ${formatLength(width, units)}',
    RectangleShape() || CircleShape() => formatSize(width, height, units),
    TriangleShape() => formatSize(width, height, units),
  };
}

class ShapeHandler extends PastingHandler<ShapeTool> with ColoredHandler {
  ShapeHandler(super.data);

  final _haptics = SnapHaptics();
  HoldToPerfect? _hold;
  bool _perfect = false;
  bool _snapped = false;
  Offset? _pointerLocal;
  int? _drawPointer;

  /// Whether a hold made the current shape perfect.
  @visibleForTesting
  bool get perfect => _perfect;

  @override
  void _updateElement(
    Offset localPosition,
    EventContext context, [
    bool first = false,
  ]) {
    changeStartedDrawing(context);
    _haptics.enabled = context.getSettings().snapHaptics;
    if (first) {
      _perfect = false;
      _haptics.reset();
      _hold?.cancel();
      _hold = HoldToPerfect(
        onHold: () {
          if (!currentlyPasting || _perfect) return;
          _perfect = true;
          _haptics.tick();
          context.refreshForegrounds();
        },
      );
    }
    _pointerLocal = localPosition;
    super._updateElement(localPosition, context, first);
    if (!first) _hold?.move(localPosition);
    final firstPos = _firstPos, secondPos = _secondPos;
    if (firstPos != null && secondPos != null) {
      constrainPosition(firstPos, secondPos, _aspectRatio);
      _haptics.update(_snapped);
    }
  }

  @override
  void onPointerDown(PointerDownEvent event, EventContext context) {
    final drawing = _drawPointer;
    if (drawing == null) {
      _drawPointer = event.pointer;
    } else if (drawing != event.pointer && currentlyPasting) {
      // A second finger while drawing cancels the shape.
      _endGesture();
      cancelPaste(context);
    }
    super.onPointerDown(event, context);
  }

  @override
  void onPointerUp(PointerUpEvent event, EventContext context) {
    if (event.pointer == _drawPointer) _drawPointer = null;
    super.onPointerUp(event, context);
  }

  void _endGesture() {
    _hold?.cancel();
    _hold = null;
    _pointerLocal = null;
    _snapped = false;
    _haptics.reset();
  }

  @override
  void onScaleEnd(ScaleEndDetails details, EventContext context) {
    _endGesture();
    super.onScaleEnd(details, context);
    _perfect = false;
  }

  @override
  void onScaleStartAbort(ScaleStartDetails details, EventContext context) {
    _endGesture();
    _perfect = false;
    super.onScaleStartAbort(details, context);
  }

  @override
  Future<void> resetInput(DocumentBloc bloc) async {
    _endGesture();
    _perfect = false;
    _drawPointer = null;
  }

  @override
  void dispose(DocumentBloc bloc) {
    _endGesture();
    super.dispose(bloc);
  }

  @override
  bool get selectAfterCreate => true;

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) {
    final foregrounds = super.createForegrounds(
      editorController,
      document,
      page,
      info,
      currentArea,
    );
    final local = _pointerLocal;
    final first = _firstPos, second = _secondPos;
    if (local == null || first == null || second == null) return foregrounds;
    final settings = editorController.settingsCubit.state;
    final scheme = getThemeData(settings.design, false).colorScheme;
    final constrained = constrainPosition(first, second, _aspectRatio);
    return [
      ...foregrounds,
      MeasureBubble((
        position: local,
        text: shapeMeasureText(
          data.property.shape,
          first,
          constrained,
          measureUnitsOf(page),
          _center,
        ),
      ), scheme),
    ];
  }

  @override
  List<PadElement> transformElements(
    Rect rect,
    String collection,
    EditorController cubit,
  ) {
    if (rect.topLeft == rect.bottomRight) return [];

    return [
      ShapeElement(
        firstPosition: rect.topLeft.toPoint(),
        secondPosition: rect.bottomRight.toPoint(),
        property: data.property.copyWith(
          strokeWidth:
              data.property.strokeWidth /
              (data.zoomDependent
                  ? cubit.rendererCubit.state.cameraViewport.scale
                  : 1),
        ),
        collection: collection,
      ),
    ];
  }

  @override
  bool get shouldNormalize => false;

  bool get _isLine => data.property.shape is LineShape;

  bool _shouldConstrain(bool modifierActive) =>
      data.constrain != modifierActive;

  @override
  Offset constrainPosition(Offset first, Offset second, bool modifierActive) {
    if (_isLine && _shouldConstrain(modifierActive)) {
      _snapped = true;
      return snapLineEndPosition(first, second);
    }
    if (!_isLine && _shouldConstrain(modifierActive)) {
      // The aspect ratio lock already makes it square.
      _snapped = false;
      return second;
    }
    final result = snapShapeDrag(
      data.property.shape,
      first,
      second,
      perfect: _perfect,
    );
    _snapped = result.snapped;
    return result.second;
  }

  @override
  double getAspectRatio(bool modifierActive) {
    final constrained = _shouldConstrain(modifierActive);
    if (_isLine) return constrained ? 0 : super.getAspectRatio(false);
    return super.getAspectRatio(constrained);
  }

  @override
  List<Widget> getToolbarActions(DocumentBloc bloc) => [
    Builder(
      builder: (context) => IconButton(
        tooltip: AppLocalizations.of(context).center,
        icon: const PhosphorIcon(PhosphorIconsLight.target),
        selectedIcon: const PhosphorIcon(PhosphorIconsFill.target),
        isSelected: data.drawFromCenter,
        onPressed: () => changeTool(
          bloc,
          data.copyWith(drawFromCenter: !data.drawFromCenter),
        ),
      ),
    ),
    Builder(
      builder: (context) => IconButton(
        tooltip: AppLocalizations.of(context).constraint,
        icon: const PhosphorIcon(PhosphorIconsLight.angle),
        selectedIcon: const PhosphorIcon(PhosphorIconsFill.angle),
        isSelected: data.constrain,
        onPressed: () =>
            changeTool(bloc, data.copyWith(constrain: !data.constrain)),
      ),
    ),
  ];

  @override
  double get constraintedAspectRatio => data.constrainedAspectRatio;
  @override
  double get constraintedHeight => data.constrainedHeight;
  @override
  double get constraintedWidth => data.constrainedWidth;
  @override
  bool get drawFromCenter => data.drawFromCenter;

  @override
  SRGBColor getColor() => data.property.paint.previewColor;

  @override
  ShapeTool setColor(SRGBColor color) => data.copyWith(
    property: data.property.copyWith(
      paint: ElementPaint.solid(
        color: color.withValues(a: getColor().a),
        blur: data.property.paint.blur,
      ),
    ),
  );

  @override
  double getStrokeWidth() => data.property.strokeWidth;

  @override
  ShapeTool setStrokeWidth(double width) =>
      data.copyWith(property: data.property.copyWith(strokeWidth: width));
}
