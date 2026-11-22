part of 'handler.dart';

/// How close, in screen pixels, a wall end must be to snap to another
/// wall's end.
const kWallSnapDistance = 16.0;

/// Wall angles snap to multiples of this, in degrees.
const kWallAngleStep = 15.0;

/// Shows the length of the wall being drawn next to the finger.
class _WallLengthRenderer extends Renderer<PenElement> {
  _WallLengthRenderer(super.element, this.label, this.anchor, this.color);

  final String label;
  final Offset anchor;
  final Color color;

  @override
  Rect get rect => Rect.fromCenter(center: anchor, width: 0, height: 0);

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
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: colorScheme?.onPrimary ?? Colors.white,
          fontSize: 14 / transform.size,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final padding = 6 / transform.size;
    // Up and to the right of the finger, so the finger doesn't cover it.
    final offset = Offset(24, -40) / transform.size;
    final box = Rect.fromLTWH(
      anchor.dx + offset.dx,
      anchor.dy + offset.dy,
      painter.width + 2 * padding,
      painter.height + 2 * padding,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(padding)),
      Paint()..color = colorScheme?.primary ?? color,
    );
    painter.paint(canvas, box.topLeft + Offset(padding, padding));
    painter.dispose();
  }
}

/// Draws floor plan walls, places armed doors and windows on them and
/// makes rooms from tapped enclosed areas.
///
/// A drag draws a wall from the press point to the finger. Both ends snap
/// to the ends of valid walls within [kWallSnapDistance] screen pixels;
/// otherwise the angle snaps to [kWallAngleStep] and the length to whole
/// inches. A tap places the armed door or window on the nearest wall, or,
/// with nothing armed, makes a room of the enclosed area around it.
class WallHandler extends Handler<WallTool> with ColoredHandler {
  WallHandler(super.data);

  Point<double>? _start;
  Point<double>? _end;
  Offset? _finger;

  @override
  SRGBColor getColor() => data.color;

  @override
  WallTool setColor(SRGBColor color) => data.copyWith(color: color);

  @override
  double getStrokeWidth() => data.thicknessIn;

  @override
  WallTool setStrokeWidth(double width) => data.copyWith(thicknessIn: width);

  @override
  PreferredSizeWidget? getToolbar(DocumentBloc bloc) => WallToolbarView(
    bloc: bloc,
    tool: data,
    onToolChanged: (tool) => changeTool(bloc, tool),
  );

  @override
  void dispose(DocumentBloc bloc) {
    // Another tool, or leaving the temporary wall tool, disarms the door.
    disarmOpening();
    super.dispose(bloc);
  }

  /// The current wall from the press point to the finger, if any.
  @visibleForTesting
  PenElement? get previewWall {
    final start = _start, end = _end;
    if (start == null || end == null || start.distanceTo(end) <= 0) {
      return null;
    }
    return makeWall(start, end, data.thicknessIn, data.color);
  }

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) {
    final wall = previewWall;
    final finger = _finger;
    if (wall == null) return [];
    final start = _start!, end = _end!;
    return [
      PenRenderer(wall),
      if (finger != null)
        _WallLengthRenderer(
          wall,
          formatFeetInches(start.distanceTo(end)),
          finger,
          data.color.toColor(),
        ),
    ];
  }

  Iterable<PadElement> _content(EventContext context) =>
      context.getState()?.page.content ?? const [];

  /// The end of a valid wall within [kWallSnapDistance] screen pixels of
  /// [point], if any.
  Point<double>? _snapToEnd(EventContext context, Point<double> point) {
    final reach = kWallSnapDistance / context.getCameraTransform().size;
    Point<double>? best;
    var bestDistance = reach;
    for (final element in _content(context)) {
      if (element is! PenElement) continue;
      final geometry = readWall(element);
      if (geometry == null) continue;
      for (final end in [geometry.a, geometry.b]) {
        final distance = end.distanceTo(point);
        if (distance <= bestDistance) {
          best = end;
          bestDistance = distance;
        }
      }
    }
    return best;
  }

  /// [raw] snapped for a wall starting at [start]: to a wall end nearby,
  /// else to the angle step and a whole number of inches.
  @visibleForTesting
  Point<double> snapEnd(
    EventContext context,
    Point<double> start,
    Point<double> raw,
  ) {
    final toEnd = _snapToEnd(context, raw);
    if (toEnd != null && toEnd != start) return toEnd;
    final delta = raw - start;
    if (delta.magnitude == 0) return start;
    final step = kWallAngleStep * pi / 180;
    final angle = (atan2(delta.y, delta.x) / step).round() * step;
    final length =
        (delta.magnitude / kCanvasUnitsPerInch).round() * kCanvasUnitsPerInch;
    return start + Point(cos(angle), sin(angle)) * length;
  }

  Point<double> _world(EventContext context, Offset local) {
    final global = context.getCameraTransform().localToGlobal(local);
    return Point(global.dx, global.dy);
  }

  @override
  bool onScaleStart(ScaleStartDetails details, EventContext context) {
    if (details.pointerCount > 1) return true;
    final point = _world(context, details.localFocalPoint);
    _start = _snapToEnd(context, point) ?? point;
    _end = null;
    _finger = null;
    changeStartedDrawing(context);
    return true;
  }

  @override
  void onScaleUpdate(ScaleUpdateDetails details, EventContext context) {
    final start = _start;
    if (start == null || details.pointerCount > 1) return;
    final raw = _world(context, details.localFocalPoint);
    _end = snapEnd(context, start, raw);
    final finger = context.getCameraTransform().localToGlobal(
      details.localFocalPoint,
    );
    _finger = finger;
    context.refreshForegrounds();
  }

  @override
  void onScaleEnd(ScaleEndDetails details, EventContext context) {
    final wall = previewWall;
    _start = null;
    _end = null;
    _finger = null;
    if (wall == null) {
      context.refreshForegrounds();
      return;
    }
    final bloc = context.getDocumentBloc();
    final state = bloc.state;
    bloc.add(
      ElementsCreated(
        [
          wall.copyWith(
            id: createUniqueId(),
            collection: state is DocumentLoadSuccess
                ? state.currentCollection
                : '',
          ),
        ],
        pageName: state.pageName,
        layer: state.currentLayer,
      ),
    );
    context.refresh();
  }

  @override
  void onScaleStartAbort(ScaleStartDetails details, EventContext context) {
    _start = null;
    _end = null;
    _finger = null;
    context.refreshForegrounds();
  }

  @override
  Future<void> onTapUp(TapUpDetails details, EventContext context) async {
    final global = context.getCameraTransform().localToGlobal(
      details.localPosition,
    );
    final armed = armedOpening.value;
    if (armed != null) {
      _placeOpening(context, armed, global);
    } else {
      _makeRoom(context, global);
    }
  }

  void _message(EventContext context, String text) {
    final buildContext = context.buildContext;
    if (!buildContext.mounted) return;
    ScaffoldMessenger.maybeOf(buildContext)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  AppLocalizations? _loc(EventContext context) {
    final buildContext = context.buildContext;
    if (!buildContext.mounted) return null;
    return Localizations.of<AppLocalizations>(buildContext, AppLocalizations);
  }

  void _placeOpening(EventContext context, ObjectEntry entry, Offset point) {
    final opening = openingOf(entry.component);
    if (opening == null) {
      disarmOpening();
      return;
    }
    final state = context.getState();
    if (state == null) return;
    final hit = findWall(state.page.content, point);
    if (hit == null) {
      final loc = _loc(context);
      if (loc != null) _message(context, loc.amazeTapOnWall);
      return;
    }
    final id = hit.wall.id;
    if (id == null) return;
    final replacement = placeOpening(
      entry,
      hit,
      opening.widthIn,
      opening.kind,
    ).map((e) => e.copyWith(collection: hit.wall.collection)).toList();
    context.getDocumentBloc().add(
      ElementsChanged({id: replacement}, pageName: state.pageName),
    );
    disarmOpening();
    final bloc = context.getDocumentBloc();
    bloc.editorController.toolCubit.resetTemporaryHandler(
      bloc,
      true,
      bloc.editorController.rendererCubit,
    );
  }

  void _makeRoom(EventContext context, Offset point) {
    final state = context.getState();
    if (state == null) return;
    final content = state.page.content;
    final loc = _loc(context);
    switch (findRoom(content, point)) {
      case OnWall():
        return;
      case NotEnclosed():
        if (loc != null) _message(context, loc.amazeNotEnclosedArea);
        return;
      case RoomFound(:final polygon):
        final number = roomCount(content) + 1;
        final area = formatSquareFeet(polygonArea(polygon));
        final elements = makeRoom(
          polygon: polygon,
          color: data.color,
          name: loc?.amazeRoomName(number) ?? 'Room $number',
          areaText: loc?.amazeSquareFeet(area) ?? '$area sq ft',
          collection: state.currentCollection,
        );
        context.getDocumentBloc().add(
          ElementsCreated(
            elements,
            pageName: state.pageName,
            layer: state.currentLayer,
          ),
        );
    }
  }
}
