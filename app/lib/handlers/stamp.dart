part of 'handler.dart';

/// The stamp tool waiting for an object from the Objects panel. The panel
/// opens while it is set, and picking an object there sets the stamp's
/// component instead of placing it.
final pendingStampTool = ValueNotifier<StampTool?>(null);

/// Gives [tool] the object [entry] as its component, in place of placing
/// it, and stops waiting. Returns whether a stamp was waiting.
bool completeStampPick(DocumentBloc bloc, ObjectEntry entry) {
  final tool = pendingStampTool.value;
  if (tool == null) return false;
  pendingStampTool.value = null;
  bloc.add(
    ToolsChanged([
      tool.copyWith(
        component: NamedItem(name: entry.name, item: entry.component),
      ),
    ]),
  );
  return true;
}

class StampHandler extends PastingHandler<StampTool> {
  Rect rect = .zero;
  List<Renderer<PadElement>>? _elements;
  StampHandler(super.data);

  @override
  FutureOr<SelectState> onSelected(
    BuildContext context, [
    bool wasAdded = true,
  ]) {
    // Without an object, there is nothing to stamp: open the Objects panel
    // to pick one.
    if (getComponent() == null) pendingStampTool.value = data;
    return super.onSelected(context, wasAdded);
  }

  @override
  void dispose(DocumentBloc bloc) {
    if (pendingStampTool.value?.id == data.id) pendingStampTool.value = null;
    super.dispose(bloc);
  }

  @override
  Future<void> preparePaste(EventContext context) async {
    final state = context.getState();
    if (state == null) return;
    await _loadComponent(
      context.getEditorController().transformCubit,
      state.data,
      state.assetService,
      state.page,
    );
  }

  ButterflyComponent? getComponent() => data.component?.item;

  /// A tap places the object the way the Objects panel does: real size,
  /// centered on the tap, SVG objects as strokes, in one undo step.
  @override
  // ignore: must_call_super
  Future<void> onTapUp(TapUpDetails details, EventContext context) async {
    final component = getComponent();
    if (component == null) {
      pendingStampTool.value = data;
      return;
    }
    final state = context.getState();
    if (state == null) return;
    final transform = context.getCameraTransform();
    final world = transform.localToGlobal(
      PointerManipulationHandler.calculatePointerPosition(
        context.getToolState(),
        details.localPosition,
        context.viewportSize,
        transform,
      ),
    );
    final elements = placeComponentAt(component, world);
    if (elements.isEmpty) return;
    context.getDocumentBloc().add(
      ElementsCreated(
        elements,
        pageName: state.pageName,
        layer: state.currentLayer,
      ),
    );
    await context.refresh();
  }

  Future<void> _loadComponent(
    TransformCubit transformCubit,
    NoteData document,
    AssetService assetService,
    DocumentPage page,
  ) async {
    final component = getComponent();
    if (component == null) return;
    final elements = _elements = await Future.wait(
      component.elements.map(Renderer.fromInstance).map((e) async {
        await e.setup(transformCubit, document, assetService, page);
        return e;
      }),
    );
    rect =
        elements
            .map((e) => e.expandedRect ?? e.rect)
            .nonNulls
            .fold<Rect?>(
              null,
              (value, element) => value?.expandToInclude(element) ?? element,
            ) ??
        Rect.zero;
  }

  @override
  PreferredSizeWidget getToolbar(DocumentBloc bloc) => ComponentsToolbarView(
    component: data.component,
    onChanged: (value) {
      final state = bloc.state;
      if (state is! DocumentLoaded) return;
      bloc.add(ToolsChanged([data.copyWith(component: value)]));
    },
  );
  @override
  MouseCursor get cursor => SystemMouseCursors.click;

  /// The ghost under the pointer before the tap.
  @override
  bool get showHoverPreview => true;
  @override
  bool get shouldNormalize => false;

  @visibleForTesting
  static (double, double) calculateScale(Rect sourceRect, Rect targetRect) =>
      calculateComponentScale(sourceRect, targetRect);

  @override
  List<PadElement> transformElements(
    Rect rect,
    String collection,
    EditorController cubit,
  ) {
    final elements = _elements;
    if (elements == null || elements.isEmpty) return [];
    return transformComponentElements(elements, this.rect, rect);
  }
}
