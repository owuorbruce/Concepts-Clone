part of 'handler.dart';

/// Half the size, in screen pixels, of the patch of canvas the eyedropper
/// renders around the pointer.
const kEyeDropperSampleRadius = 160.0;

/// How much the magnifier enlarges the canvas.
const kEyeDropperZoom = 5.0;

/// A patch of what the canvas shows, rendered at the device pixel ratio:
/// the bake, the live layers and the backgrounds, so brush textures,
/// watercolor, images and the paper all give the color you see.
class CanvasSample {
  CanvasSample._(this.image, this.pixels, this.localRect, this.pixelRatio);

  final ui.Image image;
  final ByteData pixels;

  /// The patch in screen pixels relative to the canvas.
  final Rect localRect;
  final double pixelRatio;

  bool _disposed = false;

  /// Whether [local] is far enough inside the patch for the magnifier.
  bool covers(Offset local, [double margin = 0]) =>
      localRect.deflate(margin).contains(local);

  /// The color at [local], or null outside the patch.
  SRGBColor? colorAt(Offset local) {
    if (_disposed || !localRect.contains(local)) return null;
    final int x = min(
      max(((local.dx - localRect.left) * pixelRatio).floor(), 0),
      image.width - 1,
    );
    final int y = min(
      max(((local.dy - localRect.top) * pixelRatio).floor(), 0),
      image.height - 1,
    );
    final offset = (y * image.width + x) * 4;
    return SRGBColor.from(
      r: pixels.getUint8(offset),
      g: pixels.getUint8(offset + 1),
      b: pixels.getUint8(offset + 2),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
  }

  /// Renders the canvas around [local] as it is on screen.
  static Future<CanvasSample?> capture(
    EditorController controller,
    DocumentLoadSuccess state,
    Offset local,
    Size viewportSize, {
    double pixelRatio = 1,
    double radius = kEyeDropperSampleRadius,
  }) async {
    final rect = Rect.fromCenter(
      center: local,
      width: radius * 2,
      height: radius * 2,
    );
    final ratio = pixelRatio.isFinite && pixelRatio > 0 ? pixelRatio : 1.0;
    final width = max(1, (rect.width * ratio).ceil());
    final height = max(1, (rect.height * ratio).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(ratio)
      ..translate(-rect.left, -rect.top);
    ViewPainter(
      state.data,
      state.page,
      state.info,
      cameraViewport: controller.rendererCubit.state.cameraViewport,
      transform: controller.transformCubit.state,
      invisibleLayers: state.invisibleLayers,
    ).paint(canvas, viewportSize);
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(width, height);
      final pixels = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (pixels == null) {
        image.dispose();
        return null;
      }
      return CanvasSample._(image, pixels, rect, ratio);
    } catch (_) {
      image?.dispose();
      return null;
    } finally {
      picture.dispose();
    }
  }
}

/// A round magnifier above the pointer with a crosshair and the color
/// under it. Drawn in screen space.
class EyeDropperMagnifier
    extends Renderer<({Offset local, CanvasSample sample, SRGBColor? color})> {
  EyeDropperMagnifier(super.element, this.scheme);

  final ColorScheme scheme;

  static const radius = 56.0;
  static const lift = 96.0;

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
    final sample = element.sample;
    if (sample._disposed) return;
    canvas.save();
    // Undo the camera so the magnifier is drawn in screen pixels.
    canvas.translate(transform.position.dx, transform.position.dy);
    canvas.scale(1 / transform.size);
    canvas.rotate(-transform.rotation);
    final local = element.local;
    var center = local - const Offset(0, lift);
    if (center.dy - radius < 0) center = local + const Offset(0, lift);
    final circle = Rect.fromCircle(center: center, radius: radius);
    final half = radius / kEyeDropperZoom;
    final source = Rect.fromCenter(
      center: (local - sample.localRect.topLeft) * sample.pixelRatio,
      width: half * 2 * sample.pixelRatio,
      height: half * 2 * sample.pixelRatio,
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    canvas.drawColor(Colors.white, BlendMode.srcOver);
    canvas.drawImageRect(
      sample.image,
      source,
      circle,
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.restore();
    final color = element.color?.toColor() ?? Colors.transparent;
    // The ring shows the picked color, the outline keeps it readable.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = color.withAlpha(255),
    );
    canvas.drawCircle(
      center,
      radius + 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = scheme.outline,
    );
    final cross = Paint()
      ..strokeWidth = 1.5
      ..color = scheme.onSurface;
    canvas.drawLine(
      center - const Offset(8, 0),
      center + const Offset(8, 0),
      cross,
    );
    canvas.drawLine(
      center - const Offset(0, 8),
      center + const Offset(0, 8),
      cross,
    );
    canvas.restore();
  }
}

class EyeDropperHandler extends Handler<EyeDropperTool> {
  EyeDropperHandler(super.data);

  CanvasSample? _sample;
  Future<CanvasSample?>? _capturing;
  Offset? _local;
  bool _disposed = false;

  @override
  FutureOr<SelectState> onSelected(
    BuildContext context, [
    bool wasAdded = true,
  ]) {
    if (!wasAdded) {
      final editorController = context.read<EditorController>();
      editorController.toolCubit.changeTemporaryHandler(
        context,
        editorController,
        data,
        temporaryState: TemporaryState.removeAfterRelease,
      );
    }
    return super.onSelected(context);
  }

  double _pixelRatio(EventContext context) {
    try {
      return context.devicePixelRatio;
    } catch (_) {
      return 1;
    }
  }

  /// The patch around [local], rendering a new one when the pointer is
  /// near the edge of the last.
  Future<CanvasSample?> _sampleAt(EventContext context, Offset local) {
    final sample = _sample;
    if (sample != null && sample.covers(local, EyeDropperMagnifier.radius)) {
      return Future.value(sample);
    }
    final pending = _capturing;
    if (pending != null) return pending;
    final state = context.getState();
    if (state == null) return Future.value(null);
    final future = CanvasSample.capture(
      context.getEditorController(),
      state,
      local,
      context.viewportSize,
      pixelRatio: _pixelRatio(context),
    );
    _capturing = future;
    return future.then((next) {
      _capturing = null;
      if (_disposed) {
        next?.dispose();
        return null;
      }
      if (next != null) {
        _sample?.dispose();
        _sample = next;
      }
      return _sample;
    });
  }

  @override
  Future<void> onPointerDown(
    PointerDownEvent event,
    EventContext context,
  ) async {
    _local = event.localPosition;
    await _sampleAt(context, event.localPosition);
    context.refreshForegrounds();
  }

  @override
  Future<void> onPointerMove(
    PointerMoveEvent event,
    EventContext context,
  ) async {
    _local = event.localPosition;
    context.refreshForegrounds();
    final sample = _sample;
    if (sample == null || !sample.covers(event.localPosition, 24)) {
      // Render the next patch without holding up the move; the magnifier
      // updates when it is ready.
      unawaited(
        _sampleAt(
          context,
          event.localPosition,
        ).then((_) => context.refreshForegrounds()),
      );
    }
  }

  @override
  List<Renderer> createForegrounds(
    EditorController editorController,
    NoteData document,
    DocumentPage page,
    DocumentInfo info, [
    Area? currentArea,
  ]) {
    final local = _local, sample = _sample;
    if (local == null || sample == null || !sample.covers(local)) return [];
    final settings = editorController.settingsCubit.state;
    final scheme = getThemeData(settings.design, false).colorScheme;
    return [
      EyeDropperMagnifier((
        local: local,
        sample: sample,
        color: sample.colorAt(local),
      ), scheme),
    ];
  }

  /// The color the canvas shows at [local].
  @visibleForTesting
  Future<SRGBColor?> pick(EventContext context, Offset local) async {
    var sample = await _sampleAt(context, local);
    if (sample != null && !sample.covers(local)) {
      sample = await _sampleAt(context, local);
    }
    return sample?.colorAt(local);
  }

  @override
  void onPointerUp(PointerUpEvent event, EventContext context) async {
    final color = await pick(context, event.localPosition);
    _local = null;
    _sample?.dispose();
    _sample = null;
    context.refreshForegrounds();
    if (color == null) return;
    final controller = context.getEditorController();
    final handler = controller.toolCubit.getHandler(
      editable: controller.saveCubit.state.embedding?.editable != false,
      disableTemporary: true,
    );
    if (handler is ColoredHandler) {
      handler.changeToolColor(context.getDocumentBloc(), color);
      context.getSettingsCubit().addRecentColors(color);
    } else {
      saveToClipboard(
        context.buildContext,
        color.toHexString(alpha: false),
        leading: ColorButton(color: color.toColor().withAlpha(255), size: 32),
      );
    }
  }

  @override
  void dispose(DocumentBloc bloc) {
    _disposed = true;
    _sample?.dispose();
    _sample = null;
    super.dispose(bloc);
  }
}
