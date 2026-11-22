part of 'handler.dart';

class BarcodeHandler extends PastingHandler<BarcodeTool>
    with ColoredHandler<BarcodeTool> {
  SvgElement? _element;

  BarcodeHandler(super.data);

  /// The smallest side of a new barcode on screen, so it scans.
  static const minScreenSize = 200.0;

  /// A barcode of [value] sized for [zoom]: its type's size, or larger so
  /// its shorter side is at least [minScreenSize] pixels on screen.
  @visibleForTesting
  static SvgElement buildBarcode(
    BarcodeTool tool,
    String value, {
    double zoom = 1,
  }) {
    final barcode = switch (tool.barcodeType) {
      .dataMatrix => Barcode.dataMatrix(),
      .qrCode => Barcode.qrCode(),
      .code128 => Barcode.code128(),
    };
    final baseWidth = tool.barcodeType.width;
    final baseHeight = tool.barcodeType.height;
    final safeZoom = zoom.isFinite && zoom > 0 ? zoom : 1.0;
    final factor = max(
      1.0,
      minScreenSize / (min(baseWidth, baseHeight) * safeZoom),
    );
    final width = baseWidth * factor, height = baseHeight * factor;
    final svg = barcode.toSvg(
      value,
      width: width,
      height: height,
      color: tool.color.value,
    );
    return SvgElement(
      source: Uri.dataFromString(svg, mimeType: 'image/svg+xml').toString(),
      width: width,
      height: height,
    );
  }

  /// Asks for the barcode's content with the field focused.
  Future<String?> _askContent(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.enterText),
        content: TextField(
          key: const ValueKey('amaze-barcode-content'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: loc.text),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const ValueKey('amaze-barcode-ok'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  /// A tap asks for the content and places the barcode centered there, in
  /// one undo step.
  @override
  Future<void> onTapUp(TapUpDetails details, EventContext context) async {
    final buildContext = context.buildContext;
    final value = await _askContent(buildContext);
    if (value == null || value.isEmpty) return;
    final transform = context.getCameraTransform();
    _element = buildBarcode(data, value, zoom: transform.size);
    await super.onTapUp(details, context);
    _element = null;
  }

  @override
  SRGBColor getColor() => data.color;

  @override
  BarcodeTool setColor(SRGBColor color) => data.copyWith(color: color);

  @override
  bool get shouldNormalize => false;

  @visibleForTesting
  static SvgElement transformBarcodeElement(SvgElement element, Rect rect) {
    if (rect.width.abs() < precisionErrorTolerance &&
        rect.height.abs() < precisionErrorTolerance) {
      return element.copyWith(
        position:
            rect.topLeft.toPoint() -
            Point(element.width / 2, element.height / 2),
      );
    }
    return element.copyWith(
      position: rect.topLeft.toPoint(),
      width: rect.width,
      height: rect.height,
    );
  }

  @override
  List<PadElement> transformElements(
    Rect rect,
    String collection,
    EditorController cubit,
  ) {
    final element = _element;
    if (element == null) return [];
    return [transformBarcodeElement(element, rect)];
  }

  @override
  double get constraintedAspectRatio =>
      (_element?.width ?? 1) / (_element?.height ?? 1);

  @override
  ToolStatus getStatus(DocumentBloc bloc) =>
      _element == null ? ToolStatus.normal : ToolStatus.selected;
}
