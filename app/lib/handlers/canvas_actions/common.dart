part of '../handler.dart';

/// How long the view takes to animate back after a double-tap.
const kViewResetDuration = Duration(milliseconds: 200);

/// Longest press that still counts as a tap.
const _kTapTimeout = Duration(milliseconds: 300);

/// Longest pause between the two taps of a double-tap.
const _kDoubleTapTimeout = Duration(milliseconds: 300);

/// Farthest a pointer may move during a tap, in screen pixels.
const _kTapSlop = 18.0;

/// Farthest the second tap of a double-tap may be from the first.
const _kDoubleTapSlop = 40.0;

/// Recognizes a double-tap from raw pointer events, so a view tool can
/// still treat every other one-pointer drag as its gesture.
@visibleForTesting
class DoubleTapTracker {
  Duration? _downTime;
  Offset? _downPosition;
  Duration? _lastTapTime;
  Offset? _lastTapPosition;

  void down(Offset position, Duration time) {
    _downTime = time;
    _downPosition = position;
  }

  /// Whether this up completes a double-tap.
  bool up(Offset position, Duration time) {
    final downTime = _downTime;
    final downPosition = _downPosition;
    _downTime = null;
    _downPosition = null;
    if (downTime == null ||
        downPosition == null ||
        time - downTime > _kTapTimeout ||
        (position - downPosition).distance > _kTapSlop) {
      _lastTapTime = null;
      _lastTapPosition = null;
      return false;
    }
    final lastTime = _lastTapTime;
    final lastPosition = _lastTapPosition;
    if (lastTime != null &&
        lastPosition != null &&
        downTime - lastTime <= _kDoubleTapTimeout &&
        (position - lastPosition).distance <= _kDoubleTapSlop) {
      _lastTapTime = null;
      _lastTapPosition = null;
      return true;
    }
    _lastTapTime = time;
    _lastTapPosition = position;
    return false;
  }

  void reset() {
    _downTime = null;
    _downPosition = null;
    _lastTapTime = null;
    _lastTapPosition = null;
  }
}

double _easeInOut(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// A small label with the view's angle or zoom next to the pointer. Drawn in
/// screen space, so it keeps its size and stays upright at any view.
class ViewValueBubble extends Renderer<({Offset position, String text})> {
  ViewValueBubble(super.element, this.scheme);

  final ColorScheme scheme;

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
        text: element.text,
        style: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    // Undo the camera so the bubble is drawn in screen pixels.
    canvas.translate(transform.position.dx, transform.position.dy);
    canvas.scale(1 / transform.size);
    canvas.rotate(-transform.rotation);
    final anchor = element.position + const Offset(18, -44);
    final rect = Rect.fromLTWH(
      anchor.dx,
      anchor.dy,
      painter.width + 16,
      painter.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()..color = scheme.inverseSurface.withValues(alpha: 0.9),
    );
    painter.paint(canvas, rect.topLeft + const Offset(8, 4));
    canvas.restore();
    painter.dispose();
  }
}

/// Shared gesture of the rotate and zoom tools: a one-pointer drag changes
/// the view from where it was when the drag started, and a double-tap
/// animates it back. Two-finger gestures are left to the viewport.
abstract class ViewActionHandler extends Handler<CanvasActionTool> {
  ViewActionHandler(super.data);

  final DoubleTapTracker _taps = DoubleTapTracker();
  int? _pointer;
  bool _cancelled = false;
  Offset? _startLocal;
  Offset? _localPosition;
  CameraTransform? _start;
  Timer? _animation;
  double _referenceZoom = 1;
  bool _disposed = false;

  /// The view for a drag from [startLocal] to [local].
  CameraTransform dragTransform(
    CameraTransform start,
    Offset startLocal,
    Offset local,
    Size viewport,
  );

  /// The view [t] (0–1) of the way back after a double-tap at [local].
  CameraTransform resetFrame(
    CameraTransform from,
    Offset local,
    Size viewport,
    double reference,
    double t,
  );

  /// The value shown next to the pointer.
  String formatValue(CameraTransform transform, double reference);

  bool isLocked(PersistentLockState locks);

  double _reference(EventContext context) {
    final reference = displayZoom(context.buildContext);
    return reference.isFinite && reference > 0 ? reference : 1;
  }

  @override
  void onPointerDown(PointerDownEvent event, EventContext context) {
    if (_disposed) return;
    if (_pointer != null && _pointer != event.pointer) {
      // A second finger: the viewport's pinch takes over.
      _cancelled = true;
      _localPosition = null;
      _taps.reset();
      context.refreshForegrounds();
      return;
    }
    _stopAnimation();
    _pointer = event.pointer;
    _cancelled = false;
    _startLocal = event.localPosition;
    _localPosition = null;
    _start = context.getTransformCubit().state;
    _referenceZoom = _reference(context);
    _taps.down(event.localPosition, event.timeStamp);
  }

  @override
  void onPointerMove(PointerMoveEvent event, EventContext context) {
    final start = _start;
    final startLocal = _startLocal;
    if (_disposed ||
        _cancelled ||
        event.pointer != _pointer ||
        start == null ||
        startLocal == null) {
      return;
    }
    if (_localPosition == null &&
        (event.localPosition - startLocal).distance < _kTapSlop / 3) {
      return;
    }
    if (isLocked(context.getViewState().locks)) return;
    _localPosition = event.localPosition;
    final cubit = context.getTransformCubit();
    final next = dragTransform(
      start,
      startLocal,
      event.localPosition,
      context.viewportSize,
    );
    cubit.teleport(next.position, next.size, next.rotation);
    context.refreshForegrounds();
    context.delayedBake();
  }

  @override
  void onPointerUp(PointerUpEvent event, EventContext context) {
    if (_disposed || event.pointer != _pointer) return;
    final cancelled = _cancelled;
    _pointer = null;
    _cancelled = false;
    _start = null;
    _startLocal = null;
    _localPosition = null;
    if (cancelled) {
      _taps.reset();
    } else if (_taps.up(event.localPosition, event.timeStamp) &&
        !isLocked(context.getViewState().locks)) {
      _animateBack(event.localPosition, context);
    }
    context.refreshForegrounds();
  }

  void _animateBack(Offset local, EventContext context) {
    _stopAnimation();
    final cubit = context.getTransformCubit();
    final bloc = context.getDocumentBloc();
    final from = cubit.state;
    final viewport = context.viewportSize;
    final reference = _reference(context);
    final clock = Stopwatch()..start();
    void step() {
      final t = clock.elapsedMicroseconds / kViewResetDuration.inMicroseconds;
      final frame = resetFrame(from, local, viewport, reference, min(t, 1));
      cubit.teleport(frame.position, frame.size, frame.rotation);
      if (t >= 1) {
        _stopAnimation();
        bloc.delayedBake();
      }
    }

    _animation = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_disposed) {
        _stopAnimation();
        return;
      }
      step();
    });
  }

  void _stopAnimation() {
    _animation?.cancel();
    _animation = null;
  }

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) {
    final local = _localPosition;
    if (local == null || _cancelled) return [];
    final settings = editorController.settingsCubit.state;
    final scheme = getThemeData(settings.design, false).colorScheme;
    final reference = _referenceZoom;
    return [
      ViewValueBubble((
        position: local,
        text: formatValue(editorController.transformCubit.state, reference),
      ), scheme),
    ];
  }

  @override
  void resetInput(DocumentBloc bloc) {
    _pointer = null;
    _cancelled = false;
    _start = null;
    _startLocal = null;
    _localPosition = null;
    _taps.reset();
  }

  @override
  void dispose(DocumentBloc bloc) {
    _disposed = true;
    _stopAnimation();
    resetInput(bloc);
  }
}
