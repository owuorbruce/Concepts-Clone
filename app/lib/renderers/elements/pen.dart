part of '../renderer.dart';

class PenRenderer extends Renderer<PenElement> {
  @override
  Rect rect;

  PenRenderer(
    super.element, [
    super.layer,
    Rect? rect,
    Rect expandedRect = .zero,
  ]) : rect = rect ?? _calculateRect(element.points),
       expandedRect = expandedRect,
       _localExpandedRect = expandedRect {
    if (rotation != 0 || shear != 0) {
      _localExpandedRect = Renderer._inverseAabbFor(
        expandedRect,
        this.rect.center,
        rotation * pi / 180,
        shear,
      );
    }
  }

  @override
  Rect expandedRect;
  Rect _localExpandedRect;

  // Cached paths are relative to [_pathOrigin] (the stroke's top-left), so
  // they keep full precision far from the canvas origin.
  Path? _cachedFillPath;
  Path? _cachedStrokePath;
  Offset _pathOrigin = Offset.zero;
  PathHitCalculator? _cachedHitCalculator;
  final _strokePaint = ElementPaintRenderer();
  final _fillPaint = ElementPaintRenderer();

  // Brush engine state, only used when `property.brush` names a brush.
  StampStroke? _stamps;
  ui.Picture? _stampPicture;
  Uint8List? _exportPng;
  Rect? _exportPngBounds;
  double _exportPngScale = 0;

  /// Seeds the stamp randomness instead of the element id, so a preview of
  /// a stroke being drawn (which gets a fresh id) looks like the result.
  String? brushSeed;

  /// The brush of this stroke, or null for a classic pen and unknown ids.
  BrushDefinition? get brushDefinition =>
      brushById(element.property.brush, element.property.brushVersion);

  double get _brushZoom => element.zoom ?? 1;

  // Creation and import handlers can transform strokes before asset setup.
  // Their local bounds must already be available to preserve the pivot.
  static Rect _calculateRect(List<PathPoint> points) {
    if (points.isEmpty) return Rect.zero;
    var left = points.first.x;
    var top = points.first.y;
    var right = left;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = min(left, point.x);
      top = min(top, point.y);
      right = max(right, point.x);
      bottom = max(bottom, point.y);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  void _clearCachedPaths() {
    _cachedFillPath = null;
    _cachedStrokePath = null;
    _cachedHitCalculator = null;
    _stamps = null;
    _stampPicture?.dispose();
    _stampPicture = null;
  }

  /// Computes the stroke of a brush. Returns false for classic pens.
  bool _computeBrushPath(Offset origin) {
    final brush = brushDefinition;
    if (brush == null) return false;
    final points = element.points;
    final strokeWidth = element.property.strokeWidth;
    switch (brush.engine) {
      case BrushEngine.outline:
        _cachedStrokePath = brush.hairline
            ? buildCenterline(points, zoom: _brushZoom, origin: origin)
            : buildOutline(
                points,
                brush,
                strokeWidth,
                zoom: _brushZoom,
                origin: origin,
              );
      case BrushEngine.stamp:
        _stamps = StampStroke.build(
          points,
          brush,
          strokeWidth,
          zoom: _brushZoom,
          origin: origin,
          seed: brushSeedOf(element.extra, brushSeed ?? element.id),
          start: StampWalkStart.of(element.extra),
        );
        // Marks the paths as computed; stamps are drawn from [_stamps].
        _cachedStrokePath = Path();
    }
    return true;
  }

  /// World bounds of a brush stroke, or null for classic pens.
  Rect? _brushBounds() {
    final brush = brushDefinition;
    if (brush == null || element.property.paint.previewColor.a == 0) {
      return null;
    }
    _clearCachedPaths();
    _computePaths();
    final origin = _pathOrigin;
    if (brush.engine == BrushEngine.stamp) {
      final bounds = _stamps?.bounds;
      return bounds == null || bounds.isEmpty ? rect : bounds.shift(origin);
    }
    if (brush.hairline) return rect.inflate(2 / _brushZoom);
    final bounds = _cachedStrokePath?.getBounds().shift(origin);
    final last = element.points.last;
    final stamp = endStampBounds(
      brush,
      Offset(last.x, last.y),
      element.property.strokeWidth,
    );
    if (bounds == null || stamp == null) return bounds;
    return bounds.expandToInclude(stamp);
  }

  /// Draws a brush stroke. Returns false when the classic fill draws it.
  bool _buildBrush(Canvas canvas, BlendMode? blendMode) {
    final brush = brushDefinition;
    if (brush == null) return false;
    final property = element.property;
    if (brush.engine == BrushEngine.stamp) {
      final stamps = _stamps;
      if (stamps == null || !brushTexturesReady) return true;
      _stampPicture ??= recordStampStroke(
        stamps,
        brush,
        property.paint.previewColor.toColor(),
        origin: _pathOrigin,
      );
      canvas.drawPicture(_stampPicture!);
      return true;
    }
    if (!brush.hairline) return false;
    final paint =
        _strokePaint.build(
            property.paint,
            expandedRect.shift(-_pathOrigin),
            style: .stroke,
          )
          ..strokeWidth = 0
          ..blendMode = blendMode ?? BlendMode.srcOver;
    canvas.drawPath(_cachedStrokePath!, paint);
    return true;
  }

  /// Whether this stroke is filled with a brush pattern texture, which SVG
  /// cannot express, so it is exported as an image like stamp strokes.
  bool get _isPatternBrush {
    final brush = brushDefinition;
    return brush != null &&
        brush.engine == BrushEngine.outline &&
        !brush.mask &&
        !brush.hairline &&
        brush.pattern.texture.isNotEmpty;
  }

  /// Renders the pattern stroke to a PNG over its bounds, as SVG export
  /// embeds it.
  Future<void> _preparePatternExport(double pixelsPerUnit) async {
    if (_cachedStrokePath == null) _computePaths();
    final path = _cachedStrokePath;
    if (path == null) return;
    await loadBrushTextures();
    final origin = _pathOrigin;
    final bounds = path.getBounds().shift(origin).inflate(1);
    if (bounds.isEmpty) return;
    var scale = pixelsPerUnit;
    final longest = max(bounds.width, bounds.height) * scale;
    if (longest > 4096) scale *= 4096 / longest;
    final width = max(1, (bounds.width * scale).ceil());
    final height = max(1, (bounds.height * scale).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(width / bounds.width, height / bounds.height);
    canvas.translate(origin.dx - bounds.left, origin.dy - bounds.top);
    buildLocal(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      _exportPng = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      _exportPngBounds = bounds;
      _exportPngScale = pixelsPerUnit;
    } finally {
      image.dispose();
    }
  }

  /// Renders a stamp or pattern stroke for SVG export at [pixelsPerUnit].
  /// Other strokes need no preparation.
  Future<void> prepareExport({double pixelsPerUnit = 1}) async {
    final brush = brushDefinition;
    if (brush == null) return;
    if (_exportPng != null && _exportPngScale >= pixelsPerUnit) return;
    if (_isPatternBrush) return _preparePatternExport(pixelsPerUnit);
    if (brush.engine != BrushEngine.stamp) return;
    if (_stamps == null) _computePaths();
    final stamps = _stamps;
    if (stamps == null) return;
    await loadBrushTextures();
    _exportPng = await renderStampPng(
      stamps,
      brush,
      element.property.paint.previewColor.toColor(),
      origin: _pathOrigin,
      pixelsPerUnit: pixelsPerUnit,
    );
    _exportPngBounds = stamps.bounds.shift(_pathOrigin);
    _exportPngScale = pixelsPerUnit;
  }

  void _addSvgCenterline(
    XmlElement? svg,
    String hex,
    String opacity,
    String width, {
    bool nonScaling = false,
  }) {
    final origin = rect.topLeft;
    final sink = SvgOutlineSink(origin);
    writeCenterline(
      sink,
      hairlineGeometry(element.points, zoom: _brushZoom, origin: origin),
    );
    final path = svg?.createElement('path');
    path
      ?..setAttribute('d', sink.toString())
      ..setAttribute('fill', 'none')
      ..setAttribute('stroke', hex)
      ..setAttribute('stroke-opacity', opacity)
      ..setAttribute('stroke-width', width)
      ..setAttribute('stroke-linecap', 'round')
      ..setAttribute('stroke-linejoin', 'round');
    if (nonScaling) path?.setAttribute('vector-effect', 'non-scaling-stroke');
  }

  void _addSvgImage(XmlElement? svg, Uint8List png, Rect bounds) {
    svg?.createElement('image')
      ?..setAttribute('x', '${bounds.left}')
      ..setAttribute('y', '${bounds.top}')
      ..setAttribute('width', '${bounds.width}')
      ..setAttribute('height', '${bounds.height}')
      ..setAttribute('preserveAspectRatio', 'none')
      ..setAttribute('href', 'data:image/png;base64,${base64Encode(png)}');
  }

  /// Writes a brush stroke to SVG. Returns false for classic pens.
  bool _buildBrushSvg(XmlDocument xml, SRGBColor color) {
    final brush = brushDefinition;
    if (brush == null) return false;
    final strokeWidth = element.property.strokeWidth;
    final origin = rect.topLeft;
    final svg = xml.getElement('svg');
    final hex = color.toHexString(alpha: false);
    final opacity = '${color.a / 255}';
    final png = _exportPng;
    final bounds = _exportPngBounds;
    if (_isPatternBrush && png != null && bounds != null) {
      _addSvgImage(svg, png, bounds);
      return true;
    }
    if (brush.engine == BrushEngine.stamp) {
      if (png == null || bounds == null) {
        // Not prepared for export: the centerline at the stroke's width.
        _addSvgCenterline(svg, hex, opacity, '$strokeWidth');
        return true;
      }
      _addSvgImage(svg, png, bounds);
      return true;
    }
    if (brush.hairline) {
      _addSvgCenterline(svg, hex, opacity, '1', nonScaling: true);
      return true;
    }
    final sink = SvgOutlineSink(origin);
    writeOutline(
      sink,
      StrokeGeometry.build(
        element.points,
        brush,
        strokeWidth,
        zoom: _brushZoom,
        origin: origin,
      ),
      brush,
      strokeWidth,
    );
    svg?.createElement('path')
      ?..setAttribute('d', sink.toString())
      ..setAttribute('fill', hex)
      ..setAttribute('fill-opacity', opacity)
      ..setAttribute('stroke', 'none');
    return true;
  }

  void _computePaths() {
    final points = element.points;
    if (points.isEmpty) return;
    final property = element.property;
    final origin = _pathOrigin = rect.topLeft;

    if (property.fillPaint.previewColor.a > 0) {
      _cachedFillPath = Path();
      final first = points.first;
      _cachedFillPath!.moveTo(first.x - origin.dx, first.y - origin.dy);
      for (var i = 1; i < points.length; i++) {
        final point = points[i];
        _cachedFillPath!.lineTo(point.x - origin.dx, point.y - origin.dy);
      }
    }

    if (property.paint.previewColor.a > 0 && !_computeBrushPath(origin)) {
      final outlinePoints = [
        for (final point in _getOutlinePoints()) point - origin,
      ];
      if (outlinePoints.isNotEmpty) {
        final strokePath = Path();
        if (outlinePoints.length < 2) {
          strokePath.addOval(
            Rect.fromCircle(center: outlinePoints[0], radius: 1),
          );
        } else {
          strokePath.moveTo(outlinePoints[0].dx, outlinePoints[0].dy);
          for (int i = 1; i < outlinePoints.length - 1; ++i) {
            final p0 = outlinePoints[i];
            final p1 = outlinePoints[i + 1];
            strokePath.quadraticBezierTo(
              p0.dx,
              p0.dy,
              (p0.dx + p1.dx) / 2,
              (p0.dy + p1.dy) / 2,
            );
          }
        }
        _cachedStrokePath = strokePath;
      }
    }
  }

  bool shouldSimulatePressure() {
    final points = element.points;
    if (points.length < 2) return true;
    final pressure = points[1].pressure;
    for (var i = 2; i < points.length; i++) {
      if (points[i].pressure != pressure) return false;
    }
    return true;
  }

  @override
  Future<void> setup(
    TransformCubit transformCubit,
    NoteData document,
    AssetService assetService,
    DocumentPage page,
  ) async {
    final points = element.points;
    if (points.isEmpty) return;
    final property = element.property;
    rect = _calculateRect(points);
    var topLeftCorner = rect.topLeft;
    var bottomRightCorner = rect.bottomRight;
    for (final element in points) {
      final width = property.strokeWidth + element.pressure * property.thinning;
      topLeftCorner = Offset(
        min(topLeftCorner.dx, element.x - width),
        min(topLeftCorner.dy, element.y - width),
      );
      bottomRightCorner = Offset(
        max(bottomRightCorner.dx, element.x + width),
        max(bottomRightCorner.dy, element.y + width),
      );
    }
    _localExpandedRect = Rect.fromLTRB(
      topLeftCorner.dx,
      topLeftCorner.dy,
      bottomRightCorner.dx,
      bottomRightCorner.dy,
    );
    _localExpandedRect = _brushBounds() ?? _localExpandedRect;
    expandedRect = Renderer._expandedAabbFor(
      _localExpandedRect,
      rotation / 180 * pi,
      shear,
    );
    await Future.wait([
      _strokePaint.setup(property.paint, document, assetService),
      _fillPaint.setup(property.fillPaint, document, assetService),
    ]);
    await super.setup(transformCubit, document, assetService, page);
  }

  @override
  void dispose() {
    _exportPng = null;
    _strokePaint.dispose();
    _fillPaint.dispose();
    _clearCachedPaths();
    super.dispose();
  }

  @override
  bool onAssetUpdate(
    NoteData document,
    AssetService assetService,
    DocumentPage page,
    String path,
  ) => _strokePaint.uses(path) || _fillPaint.uses(path);

  @override
  void onHidden(
    EditorController editorController,
    DocumentLoaded blocState,
    CameraTransform renderTransform,
    ui.Size size,
  ) {
    _clearCachedPaths();
  }

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
    _build(canvas);
  }

  void buildCombined(Canvas canvas) {
    _build(canvas, BlendMode.src);
  }

  /// The point [buildLocal] draws relative to.
  Offset get localOrigin {
    if (_cachedFillPath == null && _cachedStrokePath == null) {
      _computePaths();
    }
    return _pathOrigin;
  }

  /// Draws with the canvas origin already moved to [localOrigin]. The caller
  /// computes that translation in double precision, which keeps strokes far
  /// from the canvas origin sharp and steady when zoomed in.
  void buildLocal(Canvas canvas, {bool combined = false}) =>
      _build(canvas, combined ? BlendMode.src : null, true);

  void _build(Canvas canvas, [BlendMode? blendMode, bool local = false]) {
    final points = element.points;
    if (points.isEmpty) return;
    final property = element.property;

    if (_cachedFillPath == null && _cachedStrokePath == null) {
      _computePaths();
    }
    final origin = _pathOrigin;
    if (!local) {
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
    }

    if (property.fillPaint.previewColor.a > 0 && _cachedFillPath != null) {
      final paint =
          _fillPaint.build(
              property.fillPaint,
              rect.shift(-origin),
              style: .fill,
            )
            ..strokeCap = StrokeCap.round
            ..blendMode = blendMode ?? BlendMode.srcOver;
      canvas.drawPath(_cachedFillPath!, paint);
    }
    if (property.paint.previewColor.a > 0 &&
        _cachedStrokePath != null &&
        !_buildBrush(canvas, blendMode)) {
      var paint =
          _strokePaint.build(
              property.paint,
              expandedRect.shift(-origin),
              style: .fill,
            )
            ..strokeCap = StrokeCap.round
            ..blendMode = blendMode ?? BlendMode.srcOver;
      final brush = brushDefinition;
      final color = property.paint.previewColor.toColor();
      if (brush != null) {
        // Pattern fills and masks; other brushes keep the plain paint.
        paint = outlinePaint(
          brush,
          color,
          paint,
          origin: origin,
          points: points,
        );
      }
      canvas.drawPath(_cachedStrokePath!, paint);
      if (brush != null && brush.endStamp != null && !brush.mask) {
        final last = points.last;
        drawEndStamp(
          canvas,
          brush,
          Offset(last.x - origin.dx, last.y - origin.dy),
          property.strokeWidth,
          color,
        );
      }
    }
    if (!local) canvas.restore();
  }

  List<Offset> _getOutlinePoints() {
    // Strokes saved without a zoom were outlined at the old maximum zoom.
    // Keep that literal so they render unchanged now that kMaxZoom is 1000.
    final currentZoom = element.zoom ?? 10.0;
    final property = element.property;
    final center = rect.center;
    var outlinePoints = freehand.getStroke(
      [
        for (final point in element.points)
          point.scale(currentZoom, center).toFreehandPoint(),
      ],
      options: freehand.StrokeOptions(
        size: property.strokeWidth * currentZoom,
        thinning: property.thinning.clamp(0, 1),
        smoothing: property.smoothing.clamp(0, 1),
        streamline: property.streamline.clamp(.1, 1),
        simulatePressure: shouldSimulatePressure(),
      ),
    );

    return [
      for (final point in outlinePoints)
        point.scaleFromCenter(1 / currentZoom, center),
    ];
  }

  @override
  void buildSvg(
    XmlDocument xml,
    NoteData document,
    DocumentPage page,
    Rect viewportRect,
  ) {
    final points = element.points;
    final property = element.property;
    if (points.isEmpty) return;
    final fill = property.fillPaint.previewColor;
    final color = property.paint.previewColor;
    if (fill.a > 0) {
      final first = points.first;
      final path = StringBuffer('M ${first.x} ${first.y}');
      for (var i = 1; i < points.length; i++) {
        final point = points[i];
        path.write(' L ${point.x} ${point.y}');
      }
      xml.getElement('svg')?.createElement('path')
        ?..setAttribute('d', path.toString())
        ..setAttribute('fill', fill.toHexString(alpha: false))
        ..setAttribute('fill-opacity', '${fill.a / 255}')
        ..setAttribute('stroke', 'none')
        ..setAttribute('stroke-linecap', 'round')
        ..setAttribute('stroke-linejoin', 'round');
    }
    if (color.a > 0 && !_buildBrushSvg(xml, color)) {
      // 1. Get the outline points from the input points
      var outlinePoints = _getOutlinePoints();

      // 2. Render the points as a path
      if (outlinePoints.isEmpty) {
        // If the list is empty, don't do anything.
        return;
      }

      final first = outlinePoints.first;
      final path = StringBuffer('M ${first.roundedX()} ${first.roundedY()}');
      for (var i = 1; i < outlinePoints.length; i++) {
        final point = outlinePoints[i];
        path.write(' L ${point.roundedX()} ${point.roundedY()}');
      }
      path.write(' Z');

      xml.getElement('svg')?.createElement('path')
        ?..setAttribute('d', path.toString())
        ..setAttribute('fill', color.toHexString(alpha: false))
        ..setAttribute('fill-opacity', '${color.a / 255}')
        ..setAttribute('stroke', 'none')
        ..setAttribute('stroke-linecap', 'round')
        ..setAttribute('stroke-linejoin', 'round');
    }
  }

  List<PathPoint> movePoints(Offset position, double scaleX, double scaleY) {
    final points = element.points;
    if (points.isEmpty) return const [];
    var left = points.first.x;
    var top = points.first.y;
    for (var i = 1; i < points.length; i++) {
      left = min(left, points[i].x);
      top = min(top, points[i].y);
    }
    return [
      for (final point in points)
        point.copyWith(
          x: (point.x - left) * scaleX + position.dx,
          y: (point.y - top) * scaleY + position.dy,
        ),
    ];
  }

  Rect moveRect(
    Offset position,
    double scaleX,
    double scaleY, [
    bool expanded = false,
  ]) {
    final rect = expanded ? expandedRect : this.rect;
    return Rect.fromPoints(
      position,
      position + Offset(rect.width * scaleX, rect.height * scaleY),
    );
  }

  @override
  PenRenderer _transform({
    required Offset position,
    required double rotation,
    required double shear,
    double scaleX = 1,
    double scaleY = 1,
    double strokeWidthFactor = 1,
  }) => PenRenderer(
    element.copyWith(
      rotation: rotation,
      shear: shear,
      points: movePoints(position, scaleX, scaleY),
      property: element.property.copyWith(
        strokeWidth: element.property.strokeWidth * strokeWidthFactor,
      ),
    ),
    layer,
    moveRect(position, scaleX, scaleY),
    moveRect(position, scaleX, scaleY, true),
  );

  @override
  PathHitCalculator createHitCalculator() {
    _cachedHitCalculator ??= PathHitCalculator(
      rect,
      element.points,
      0,
      strokeWidth: element.property.strokeWidth,
    );
    return _cachedHitCalculator!;
  }
}

class PathHitCalculator extends HitCalculator {
  final Rect elementRect;
  final List<PathPoint> points;
  final double rotation;

  /// Width of the stroke. A point within half of it from the centerline
  /// hits, so thick and stamp brush strokes are hit where they are drawn.
  final double strokeWidth;
  final double _cos;
  final double _sin;

  PathHitCalculator(
    this.elementRect,
    this.points,
    this.rotation, {
    this.strokeWidth = 0,
  }) : _cos = rotation == 0 ? 1 : cos(rotation),
       _sin = rotation == 0 ? 0 : sin(rotation);

  Offset _rotatePoint(PathPoint point) {
    if (rotation == 0) return point.toOffset();
    final center = elementRect.center;
    final dx = point.x - center.dx;
    final dy = point.y - center.dy;
    return Offset(
      center.dx + dx * _cos - dy * _sin,
      center.dy + dx * _sin + dy * _cos,
    );
  }

  @override
  bool hitPolygon(
    List<ui.Offset> polygon, {
    HitElementMode hitElementMode = .touchAnywhere,
  }) => _hit(polygon, hitElementMode, strokeWidth / 2);

  /// Hits within half the stroke width of the centerline, and never less
  /// than [kMinStrokeHitScreenPixels] on screen at [zoom].
  @override
  bool hitPolygonAt(
    List<ui.Offset> polygon, {
    HitElementMode hitElementMode = .touchAnywhere,
    double zoom = 1,
  }) {
    final scale = zoom.isFinite && zoom > 0 ? zoom : 1.0;
    return _hit(
      polygon,
      hitElementMode,
      max(strokeWidth / 2, kMinStrokeHitScreenPixels / scale),
    );
  }

  List<ui.Offset>? _path;
  Rect? _pathBounds;

  /// The stroke's points in document space, worked out once.
  List<ui.Offset> get _documentPath =>
      _path ??= points.map(_rotatePoint).toList(growable: false);

  Rect get _documentBounds {
    final cached = _pathBounds;
    if (cached != null) return cached;
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (final point in _documentPath) {
      left = min(left, point.dx);
      top = min(top, point.dy);
      right = max(right, point.dx);
      bottom = max(bottom, point.dy);
    }
    return _pathBounds = Rect.fromLTRB(left, top, right, bottom);
  }

  bool _hit(
    List<ui.Offset> polygon,
    HitElementMode hitElementMode,
    double tolerance,
  ) {
    if (points.isEmpty || polygon.isEmpty || hitElementMode == .none) {
      return false;
    }
    final path = _documentPath;
    final reach = hitElementMode == .full
        ? max(strokeWidth / 2, 1e-9)
        : tolerance;
    // Only the selection's edges near the stroke can cross or touch it;
    // in a big lasso that is a handful of its many edges.
    final bounds = _documentBounds.inflate(reach);
    final left = bounds.left, top = bounds.top;
    final right = bounds.right, bottom = bounds.bottom;
    final near = <(ui.Offset, ui.Offset)>[];
    final count = polygon.length;
    for (var i = 0; i < count; i++) {
      final a = polygon[i];
      final b = count > 2
          ? polygon[(i + 1) % count]
          : polygon[min(i + 1, count - 1)];
      if (max(a.dx, b.dx) < left ||
          min(a.dx, b.dx) > right ||
          max(a.dy, b.dy) < top ||
          min(a.dy, b.dy) > bottom) {
        continue;
      }
      near.add((a, b));
    }
    bool touchesEdge() {
      if (path.length == 1) {
        return near.any(
          (edge) => distanceToSegment(path.first, edge.$1, edge.$2) <= reach,
        );
      }
      for (var i = 1; i < path.length; i++) {
        for (final edge in near) {
          if (segmentDistance(path[i - 1], path[i], edge.$1, edge.$2) <=
              reach) {
            return true;
          }
        }
      }
      return false;
    }

    final firstInside = isPointInPolygon(polygon, path.first);
    if (hitElementMode == .full) {
      // Enclosed: inside, and the visible stroke, half its width around
      // every segment, nowhere on or over the selection's edge.
      if (!firstInside || touchesEdge()) return false;
      return path.every((point) => isPointInPolygon(polygon, point));
    }
    // Touching: a point inside, or the visible stroke meets an edge. With
    // no edge near, the stroke is wholly inside or wholly outside.
    if (firstInside) return true;
    if (near.isEmpty) return false;
    return touchesEdge();
  }
}
