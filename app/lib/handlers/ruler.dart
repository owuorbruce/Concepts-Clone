part of 'handler.dart';

/// Angles, in degrees, the ruler snaps to. Their mirrors (180° minus the
/// angle) and the opposite directions snap too.
const kRulerSnapAngles = [0.0, 15.0, 30.0, 45.0, 60.0, 90.0];
const _rulerRotationSnapThreshold = 4.0;

/// How far outside the ruler, in screen pixels, a stroke still runs along
/// its edge.
const kRulerEdgeReach = 24.0;

final _rulerSnapTargets = <double>{
  for (final angle in kRulerSnapAngles) ...[angle, (180 - angle) % 180],
}.toList();

Rect _getRulerRect(
  RulerTool ruler,
  Size size,
  Offset position, [
  CameraTransform transform = const .new(),
]) {
  return transform.localToGlobalRect(
    Rect.fromLTWH(
      position.dx - size.width / 2,
      size.height / 2 - ruler.size / 2 + position.dy,
      size.width * 2,
      ruler.size.toDouble(),
    ),
  );
}

double snapRulerRotation(double rotation) =>
    snapRulerRotationResult(rotation).rotation;

/// [rotation] in degrees snapped to [kRulerSnapAngles], their mirrors and
/// opposites within 4°. Returns whether it snapped.
({double rotation, bool snapped}) snapRulerRotationResult(double rotation) {
  final normalized = (rotation % 360 + 360) % 360;
  final result = snapAngleTo(normalized * pi / 180, [
    for (final target in _rulerSnapTargets) target * pi / 180,
  ], tolerance: _rulerRotationSnapThreshold * pi / 180);
  if (!result.snapped) return (rotation: normalized, snapped: false);
  var degrees = (result.angle * 180 / pi) % 360;
  if (degrees < 0) degrees += 360;
  // Avoid 359.999… from rounding.
  degrees = (degrees * 1e6).round() / 1e6 % 360;
  return (rotation: degrees, snapped: true);
}

Color resolveRulerForegroundColor(RulerTool ruler, Color background) {
  final configured = ruler.foreground?.toColor();
  if (configured != null) return configured;
  final luminance = background.computeLuminance();
  final blackContrast = (luminance + 0.05) / 0.05;
  final whiteContrast = 1.05 / (luminance + 0.05);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

class RulerHandler extends Handler<RulerTool> with PointerManipulationHandler {
  Offset _position = .zero;
  double _rotation = 0;
  bool _snapRotation = false;
  double _previousGestureRotation = 0;
  Offset _transformStartPosition = .zero;
  Offset _transformStartPointer = .zero;
  final _haptics = SnapHaptics();

  /// Whether the ruler is being twisted, so its angle shows.
  bool _rotating = false;
  Size _viewportSize = Size.zero;

  /// Whether the angle shows next to the ruler.
  @visibleForTesting
  bool get showsAngle => _rotating;

  Offset get position => _position;
  double get rotation => _snapRotation
      ? snapRulerRotation(_rotation)
      : (_rotation % 360 + 360) % 360;

  RulerHandler(super.data);

  void setPosition(Offset position) {
    _position = position;
  }

  void setRotation(double rotation) {
    _rotation = (rotation % 360 + 360) % 360;
    _snapRotation = false;
  }

  @override
  List<Widget> getRuntimeProperties(BuildContext context) => [
    ExactSlider(
      header: Text(AppLocalizations.of(context).angle),
      value: rotation,
      min: 0,
      max: 360,
      sliderStep: 1,
      defaultValue: 0,
      fractionDigits: 1,
      onChangeEnd: (value) async {
        setRotation(value);
        await context.read<DocumentBloc>().refresh(allowBake: false);
      },
    ),
  ];

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) {
    final settings = editorController.settingsCubit.state;
    return [
      RulerRenderer(data, position: _position, rulerRotation: rotation),
      if (_rotating && !_viewportSize.isEmpty)
        MeasureBubble((
          position: getRect(_viewportSize).center,
          text: formatAngle(-rotation * pi / 180),
        ), getThemeData(settings.design, false).colorScheme),
    ];
  }

  @override
  SelectState onSelected(BuildContext context, [bool wasAdded = true]) {
    return SelectState.toggle;
  }

  void transform(EventContext context, {Offset? position, double? rotation}) {
    if (position != null) {
      _position += position;
    }
    if (rotation != null) {
      _rotation += rotation;
      _snapRotation = true;
      _rotating = true;
      _viewportSize = context.viewportSize;
      _haptics.enabled = context.getSettings().snapHaptics;
      _haptics.update(snapRulerRotationResult(_rotation).snapped);
    }
    context.refresh();
  }

  void beginTransform(Offset pointer) {
    _previousGestureRotation = 0;
    _transformStartPosition = _position;
    _transformStartPointer = pointer;
  }

  void endTransform() {
    _previousGestureRotation = 0;
    _rotating = false;
    _haptics.reset();
  }

  Offset _getDragPosition(Offset pointer) =>
      _transformStartPosition + pointer - _transformStartPointer;

  void transformWithScaleUpdate(
    EventContext context,
    ScaleUpdateDetails details,
  ) {
    final deltaRotation =
        (details.rotation - _previousGestureRotation) * 180 / pi;
    _previousGestureRotation = details.rotation;
    _position = _getDragPosition(details.localFocalPoint);
    transform(context, rotation: deltaRotation);
  }

  void transformWithPointerMove(EventContext context, PointerMoveEvent event) {
    if ((event.buttons & kSecondaryMouseButton) != 0) {
      final rulerCenter = getRect(context.viewportSize).center;
      final previousPosition = event.localPosition - event.delta;
      transform(
        context,
        rotation:
            (event.localPosition - rulerCenter).direction * 180 / pi -
            (previousPosition - rulerCenter).direction * 180 / pi,
      );
    } else {
      _position = _getDragPosition(event.localPosition);
      transform(context);
    }
  }

  Rect getRect(Size size, [CameraTransform transform = const .new()]) {
    return _getRulerRect(data, size, _position, transform);
  }

  bool isPointerInside(Offset position, Size viewportSize) {
    final rect = getRect(viewportSize);
    // Check if the position is inside the ruler rect, consider rotation
    final rotatedPosition = position.rotate(rect.center, -rotation * pi / 180);
    return rect.contains(rotatedPosition);
  }

  /// Moves [position] onto the nearer edge of the ruler when it is on the
  /// ruler or within [kRulerEdgeReach] screen pixels outside an edge, so
  /// pen and brush strokes run straight along it.
  @override
  Offset getPointerPosition(
    Offset position,
    Size viewportSize, [
    CameraTransform transform = const .new(),
  ]) {
    final rulerRect = getRect(viewportSize);
    final pivot = rulerRect.center;
    final angle = rotation * pi / 180;
    final rotatedPosition = position.rotate(pivot, -angle);
    if (rotatedPosition.dx < rulerRect.left ||
        rotatedPosition.dx > rulerRect.right ||
        rotatedPosition.dy < rulerRect.top - kRulerEdgeReach ||
        rotatedPosition.dy > rulerRect.bottom + kRulerEdgeReach) {
      return position;
    }
    final toTop = (rotatedPosition.dy - rulerRect.top).abs();
    final toBottom = (rotatedPosition.dy - rulerRect.bottom).abs();
    final edge = toTop <= toBottom ? rulerRect.top : rulerRect.bottom;
    return Offset(rotatedPosition.dx, edge).rotate(pivot, angle);
  }

  static RulerHandler? getFirstRuler(
    ToolRuntimeState index,
    Offset position,
    Size viewportSize,
  ) {
    return index.toggleableHandlers.values
        .whereType<RulerHandler>()
        .firstWhereOrNull((e) => e.isPointerInside(position, viewportSize));
  }

  static RulerHandler? getInteractiveRuler(
    ToolRuntimeState index,
    Handler handler,
    Offset position,
    Size viewportSize,
  ) {
    if (handler is! SelectHandler && handler is! GeneralHandHandler) {
      return null;
    }
    return getFirstRuler(index, position, viewportSize);
  }
}

class RulerRenderer extends Renderer<RulerTool> {
  final Offset position;
  final double rulerRotation;

  RulerRenderer(super.element, {this.position = .zero, this.rulerRotation = 0});

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
    canvas.save();
    canvas.translate(transform.position.dx, transform.position.dy);
    canvas.scale(1 / transform.size, 1 / transform.size);
    canvas.rotate(-transform.rotation);
    var rulerRect = _getRulerRect(element, size, position);
    final rulerCenter = rulerRect.center;
    canvas.translate(rulerCenter.dx, rulerCenter.dy);
    canvas.rotate(rulerRotation * pi / 180);
    rulerRect = rulerRect.translate(-rulerCenter.dx, -rulerCenter.dy);
    final rulerColor = colorScheme?.primary ?? Colors.grey;
    final rulerBackgroundColor =
        element.color?.toColor() ??
        (colorScheme?.primaryContainer ?? Colors.grey).withAlpha(200);
    final rulerForegroundColor = resolveRulerForegroundColor(
      element,
      rulerBackgroundColor,
    );
    final rulerPaint = Paint()
      ..color = rulerColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final rulerBackgroundPaint = Paint()
      ..color = rulerBackgroundColor
      ..style = PaintingStyle.fill;
    final rulerForegroundPaint = Paint()..color = rulerForegroundColor;

    // Calculate steps based on zoom level. Ticks closer than 8 px are
    // unreadable, and the tick count must not grow with the zoom: coarsen
    // until both hold. Floor plans tick in inches, then feet.
    final imperial = measureUnitsOf(page) == MeasureUnits.feetInches;
    var steps = imperial ? kCanvasUnitsPerInch.round() : 50;
    var factor = imperial ? 12 : 5;
    final rulerExtent = size.width * transform.size * 2;
    while (steps < 1e15 &&
        (steps / transform.size < 8 || rulerExtent / steps > 400)) {
      steps *= factor;
      if (imperial) factor = 10;
    }

    // Paint ruler background
    canvas.drawRect(rulerRect, rulerBackgroundPaint);
    canvas.drawRect(rulerRect, rulerPaint);

    // Draw center dot
    canvas.drawCircle(rulerRect.center, 4, rulerForegroundPaint);

    // Paint ruler lines
    int x = steps;
    final tickSpacing = steps / transform.size;
    final tickIndex = transform.position.dx / tickSpacing;
    var even = !tickIndex.isFinite || tickIndex.floor() % 2 == 0;
    while (x <= rulerExtent) {
      final posX =
          x / transform.size -
          (transform.position.dx % (steps / transform.size)) -
          size.width / 2 -
          rulerRect.width / 4;
      canvas.drawLine(
        Offset(posX, rulerRect.top),
        Offset(
          posX,
          rulerRect.top + (even ? rulerRect.height / 8 : rulerRect.height / 4),
        ),
        rulerForegroundPaint,
      );
      even = !even;
      x += steps;
    }

    canvas.restore();
  }
}
