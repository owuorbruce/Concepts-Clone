part of 'handler.dart';

class TextureHandler extends PastingHandler<TextureTool> {
  TextureHandler(super.data);

  Offset? _pointerLocal;

  @override
  void _updateElement(
    Offset localPosition,
    EventContext context, [
    bool first = false,
  ]) {
    _pointerLocal = localPosition;
    super._updateElement(localPosition, context, first);
  }

  @override
  void onScaleEnd(ScaleEndDetails details, EventContext context) {
    _pointerLocal = null;
    super.onScaleEnd(details, context);
  }

  /// The pattern previews as it is dragged, with its size beside the pen.
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
    final local = _pointerLocal, first = _firstPos, second = _secondPos;
    if (local == null || first == null || second == null) return foregrounds;
    final settings = editorController.settingsCubit.state;
    return [
      ...foregrounds,
      MeasureBubble((
        position: local,
        text: formatSize(
          (second - first).dx.abs(),
          (second - first).dy.abs(),
          measureUnitsOf(page),
        ),
      ), getThemeData(settings.design, false).colorScheme),
    ];
  }

  @override
  List<PadElement> transformElements(
    Rect rect,
    String collection,
    EditorController cubit,
  ) {
    if (rect.isEmpty) return [];

    return [
      TextureElement(
        firstPosition: rect.topLeft.toPoint(),
        secondPosition: rect.bottomRight.toPoint(),
        texture: data.texture,
        collection: collection,
      ),
    ];
  }

  @override
  double get constraintedAspectRatio => data.constrainedAspectRatio;
  @override
  double get constraintedHeight => data.constrainedHeight;
  @override
  double get constraintedWidth => data.constrainedWidth;
}
