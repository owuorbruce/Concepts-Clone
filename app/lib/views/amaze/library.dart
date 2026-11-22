import 'package:butterfly/brushes/brush_registry.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/visualizer/tool.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:butterfly/visualizer/property.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'icons.dart';

/// Prefix of the display icon of tools made from the brush library.
const kLibraryIconPrefix = 'amaze.';

/// Where an entry is shown in the brush library.
enum LibrarySection { basics, tools, market }

/// An item of the brush library. Market entries are packs of brushes; the
/// library opens them to pick one with [createPackTool].
enum LibraryEntry {
  pen(.basics, AmazeGlyph.pen),
  fountain(.basics, AmazeGlyph.fountain),
  dynamicPen(.basics, AmazeGlyph.dynamicPen),
  fixedWidth(.basics, AmazeGlyph.fixedWidth),
  wire(.basics, AmazeGlyph.wire),
  softPencil(.basics, AmazeGlyph.softPencil),
  hardPencil(.basics, AmazeGlyph.hardPencil),
  marker(.basics, AmazeGlyph.marker),
  watercolor(.basics, AmazeGlyph.watercolor),
  airbrush(.basics, AmazeGlyph.airbrush),
  fill(.basics, AmazeGlyph.fill),
  dotted(.basics, AmazeGlyph.dotted),
  lasso(.tools, AmazeGlyph.lasso),
  nudge(.tools, AmazeGlyph.nudge),
  slice(.tools, AmazeGlyph.slice),
  hardMask(.tools, AmazeGlyph.hardMask),
  softMask(.tools, AmazeGlyph.softMask),
  text(.tools),
  pan(.tools),
  rotate(.tools, AmazeGlyph.rotate),
  zoom(.tools),
  tilingPatterns(.market, AmazeGlyph.tilingPatterns),
  waterful(.market, AmazeGlyph.waterful),
  crosshatching(.market, AmazeGlyph.crosshatching),
  inkBlot(.market, AmazeGlyph.inkBlot);

  const LibraryEntry(this.section, [this.glyph]);

  final LibrarySection section;

  /// Custom glyph, or null for entries that use a Phosphor icon.
  final AmazeGlyph? glyph;

  static List<LibraryEntry> of(LibrarySection section) {
    return values.where((entry) => entry.section == section).toList();
  }

  /// Looks up an entry by its name, or returns null.
  static LibraryEntry? byName(String name) {
    for (final entry in values) {
      if (entry.name == name) return entry;
    }
    return null;
  }

  AmazeIconData get icon {
    final glyph = this.glyph;
    if (glyph != null) return GlyphAmazeIcon(glyph);
    return switch (this) {
      text => const PhosphorAmazeIcon(
        PhosphorIconsLight.textT,
        PhosphorIconsFill.textT,
      ),
      pan => const PhosphorAmazeIcon(
        PhosphorIconsLight.hand,
        PhosphorIconsFill.hand,
      ),
      zoom => const PhosphorAmazeIcon(
        PhosphorIconsLight.magnifyingGlassPlus,
        PhosphorIconsFill.magnifyingGlassPlus,
      ),
      _ => const PhosphorAmazeIcon(
        PhosphorIconsLight.paintBrush,
        PhosphorIconsFill.paintBrush,
      ),
    };
  }

  /// Whether the canvas can use this entry today.
  bool get available => _build() != null;

  String getLocalizedName(AppLocalizations loc) {
    return switch (this) {
      pen => loc.pen,
      fountain => loc.fountainPen,
      dynamicPen => loc.dynamicPen,
      fixedWidth => loc.fixedWidth,
      wire => loc.wire,
      softPencil => loc.softPencil,
      hardPencil => loc.hardPencil,
      marker => loc.marker,
      watercolor => loc.watercolor,
      airbrush => loc.airbrush,
      fill => loc.fill,
      dotted => loc.dotted,
      lasso => loc.lasso,
      nudge => loc.nudge,
      slice => loc.slice,
      hardMask => loc.hardMask,
      softMask => loc.softMask,
      text => loc.text,
      pan => loc.pan,
      rotate => loc.rotate,
      zoom => loc.zoom,
      tilingPatterns => loc.tilingPatterns,
      waterful => loc.waterful,
      crosshatching => loc.crosshatching,
      inkBlot => loc.inkAndBlotTextures,
    };
  }

  /// What this entry does, in one sentence, for entries that need one.
  String? getLocalizedInfo(AppLocalizations loc) => switch (this) {
    fill => loc.amazeInfoFill,
    _ => null,
  };

  /// A new tool for this entry, named [name], or null if it is unavailable.
  ///
  /// The tool remembers its entry in its display icon, so the wheel can show
  /// the same icon as the library. Classic Butterfly ignores unknown display
  /// icons and falls back to the tool's own icon.
  Tool? createTool({String name = ''}) {
    final tool = _build();
    if (tool == null) return null;
    return tool.copyWith(
      name: name,
      displayIcon: '$kLibraryIconPrefix${this.name}',
    );
  }

  /// The brush id this entry draws with, or null.
  String? get brushId => switch (this) {
    pen => 'amaze.pen',
    fountain => 'amaze.fountain',
    dynamicPen => 'amaze.dynamic',
    fixedWidth => 'amaze.fixed',
    wire => 'amaze.wire',
    dotted => 'amaze.dotted',
    softPencil => 'amaze.softPencil',
    hardPencil => 'amaze.hardPencil',
    marker => 'amaze.marker',
    airbrush => 'amaze.airbrush',
    watercolor => 'amaze.watercolor',
    hardMask => 'amaze.hardMask',
    softMask => 'amaze.softMask',
    // A pack previews and starts with its first brush.
    tilingPatterns ||
    waterful ||
    crosshatching ||
    inkBlot => packBrushIds.first,
    _ => null,
  };

  /// Whether this entry is a pack of brushes.
  bool get isPack => section == LibrarySection.market;

  /// The brushes of a market pack, in library order. Empty for other
  /// entries.
  List<String> get packBrushIds => switch (this) {
    tilingPatterns => const [
      'amaze.pattern.bricks',
      'amaze.pattern.hexagons',
      'amaze.pattern.scales',
      'amaze.pattern.dotGrid',
    ],
    waterful => const [
      'amaze.waterful.wetWash',
      'amaze.waterful.bleed',
      'amaze.waterful.granulate',
      'amaze.waterful.glaze',
    ],
    crosshatching => const [
      'amaze.hatch.hatch',
      'amaze.hatch.crosshatch',
      'amaze.hatch.stipple',
      'amaze.hatch.byPressure',
    ],
    inkBlot => const [
      'amaze.ink.splatter',
      'amaze.ink.blot',
      'amaze.ink.dripPen',
      'amaze.ink.woodGrain',
    ],
    _ => const [],
  };

  /// A pen of this pack drawing with [brushId], or null if the brush is not
  /// in the pack. The tool is named after the brush.
  Tool? createPackTool(String brushId, {String? name}) {
    if (!packBrushIds.contains(brushId)) return null;
    final definition = brushById(brushId);
    return _brushTool(const PenProperty(), id: brushId).copyWith(
      name: name ?? definition?.name ?? '',
      displayIcon: '$kLibraryIconPrefix${this.name}',
    );
  }

  /// The definition of [brushId], once the registry has loaded.
  BrushDefinition? get brushDefinition {
    final id = brushId;
    return id == null ? null : brushById(id);
  }

  Tool? _build() {
    return switch (this) {
      pen => _brushTool(const PenProperty()),
      dynamicPen => _brushTool(const PenProperty(thinning: 0.8)),
      fixedWidth => _brushTool(const PenProperty(thinning: 0)),
      wire => _brushTool(
        const PenProperty(strokeWidth: 1, thinning: 0),
        zoomDependent: true,
        keepSize: true,
      ),
      fountain ||
      dotted ||
      softPencil ||
      hardPencil ||
      marker ||
      airbrush ||
      watercolor ||
      hardMask ||
      softMask ||
      tilingPatterns ||
      waterful ||
      crosshatching ||
      inkBlot => _brushTool(const PenProperty()),
      fill => Tool.pen(
        property: const PenProperty(fillPaint: ElementPaint.solid()),
      ),
      lasso => Tool.select(mode: SelectMode.lasso),
      nudge => Tool.canvasAction(kind: CanvasActionKind.nudge),
      slice => Tool.canvasAction(kind: CanvasActionKind.slice),
      rotate => Tool.canvasAction(kind: CanvasActionKind.rotate),
      zoom => Tool.canvasAction(kind: CanvasActionKind.zoom),
      text => Tool.label(),
      pan => Tool.hand(),
    };
  }

  /// A pen drawing with [brushId] at its newest version. The definition's
  /// default size and opacity apply unless [keepSize].
  Tool _brushTool(
    PenProperty base, {
    bool zoomDependent = false,
    bool keepSize = false,
    String? id,
  }) {
    id ??= brushId!;
    final definition = brushById(id);
    var property = base.copyWith(
      brush: id,
      brushVersion: definition?.version ?? 1,
    );
    final size = definition?.defaultSize;
    if (size != null && !keepSize) {
      property = property.copyWith(strokeWidth: size);
    }
    final opacity = definition?.defaultOpacity;
    if (opacity != null) {
      property = property.copyWith(
        paint: property.paint.withAlpha((opacity.clamp(0, 1) * 255).round()),
      );
    }
    return Tool.pen(zoomDependent: zoomDependent, property: property);
  }
}

/// The library entry a tool was made from, or the entry that matches a
/// built-in tool, so its icon matches the library. Returns null for tools
/// the library does not offer, which keep their own icon.
LibraryEntry? libraryEntryOf(Tool tool) {
  final displayIcon = tool.displayIcon;
  if (displayIcon.startsWith(kLibraryIconPrefix)) {
    return LibraryEntry.byName(
      displayIcon.substring(kLibraryIconPrefix.length),
    );
  }
  if (displayIcon.isNotEmpty) return null;
  return switch (tool) {
    PenTool() => LibraryEntry.pen,
    SelectTool(mode: SelectMode.lasso) => LibraryEntry.lasso,
    LabelTool(mode: LabelMode.text) => LibraryEntry.text,
    HandTool() => LibraryEntry.pan,
    CanvasActionTool(:final kind) => switch (kind) {
      CanvasActionKind.rotate => LibraryEntry.rotate,
      CanvasActionKind.zoom => LibraryEntry.zoom,
      CanvasActionKind.nudge => LibraryEntry.nudge,
      CanvasActionKind.slice => LibraryEntry.slice,
    },
    _ => null,
  };
}

/// The icon of [tool] on the wheel, the bar and in the library.
AmazeIconData amazeToolIcon(Tool tool) {
  final entry = libraryEntryOf(tool);
  if (entry != null) return entry.icon;
  return PhosphorAmazeIcon(tool.icon(), tool.icon(filled: true));
}

/// Gives a library fill brush the same interior color as its outline.
Tool syncLibraryFill(Tool tool) {
  if (tool is! PenTool || libraryEntryOf(tool) != LibraryEntry.fill) {
    return tool;
  }
  final property = tool.property;
  final color = property.paint.previewColor;
  return tool.copyWith(
    property: property.copyWith(fillPaint: ElementPaint.solid(color: color)),
  );
}

/// The groups of "More tools" in the brush library, in display order.
enum ToolGroup { drawEdit, objects, precision, present }

/// The light gray grid the Pattern fill tile starts with. The bare
/// [PatternTexture] default has no boxes and a white fill, so it would be
/// invisible on white paper.
const kVisiblePatternTexture = PatternTexture(
  boxWidth: 40,
  boxHeight: 40,
  boxXColor: SRGBColor(0xFFD0D0D0),
  boxYColor: SRGBColor(0xFFD0D0D0),
  boxColor: SRGBColor.transparent,
  boxXStroke: 1,
  boxYStroke: 1,
);

/// One tile of "More tools": a tool, or a family of presets that differ
/// only in a subtype (shape, barcode type, axis, mode).
///
/// Every preset of [slotToolCatalog] belongs to exactly one family, so all
/// of them stay reachable through [variants].
enum ToolFamily {
  select(.drawEdit),
  eraser(.drawEdit),
  shapes(.drawEdit),
  polygon(.drawEdit),
  text(.drawEdit),
  classicPen(.drawEdit),
  stamp(.objects),
  patternFill(.objects),
  table(.objects),
  barcode(.objects),
  straightedge(.precision),
  grid(.precision),
  insertSpace(.precision),
  artboard(.precision),
  wall(.precision),
  laserPointer(.present),
  presentation(.present),
  hand(.present),
  eyedropper(.present),
  fullScreen(.present),
  collections(.present);

  const ToolFamily(this.group);

  final ToolGroup group;

  static List<ToolFamily> of(ToolGroup group) =>
      values.where((family) => family.group == group).toList();

  /// Whether the tile runs at once instead of going into the slot.
  bool get isAction => this == fullScreen || this == collections;

  /// The presets of this family, the default first.
  List<Tool> get variants => switch (this) {
    select => [for (final mode in SelectMode.values) Tool.select(mode: mode)],
    eraser => [for (final mode in EraserMode.values) Tool.eraser(mode: mode)],
    shapes => [
      for (final shape in [
        PathShape.line,
        PathShape.rectangle,
        PathShape.circle,
        PathShape.triangle,
      ])
        Tool.shape(property: ShapeProperty(shape: shape())),
    ],
    polygon => [Tool.polygon()],
    text => [Tool.label()],
    classicPen => [Tool.pen()],
    stamp => [Tool.stamp()],
    patternFill => [Tool.texture(texture: kVisiblePatternTexture)],
    table => [Tool.table()],
    barcode => [
      for (final type in BarcodeType.values) Tool.barcode(barcodeType: type),
    ],
    straightedge => [Tool.ruler()],
    grid => [Tool.grid()],
    insertSpace => [for (final axis in Axis2D.values) Tool.spacer(axis: axis)],
    artboard => [Tool.area()],
    wall => [Tool.wall()],
    // The trail fades out over a second, shortly after the pen lifts.
    laserPointer => [Tool.laser(duration: 0.25, hideDuration: 1)],
    presentation => [Tool.presentation()],
    hand => [Tool.hand()],
    eyedropper => [Tool.eyeDropper()],
    fullScreen => [Tool.fullScreen()],
    collections => [Tool.collection()],
  };

  /// The tool the tile puts into the slot.
  Tool get defaultTool => variants.first;

  /// Whether the tile has a subtype chooser.
  bool get hasVariants => variants.length > 1;

  /// The family [tool] belongs to, or null for tools "More tools" does not
  /// offer (brushes, canvas actions, undo).
  static ToolFamily? ofTool(Tool tool) => switch (tool) {
    SelectTool() => select,
    EraserTool() => eraser,
    ShapeTool() => shapes,
    PolygonTool() => polygon,
    LabelTool() => text,
    PenTool(:final property, :final displayIcon)
        when property.brush.isEmpty &&
            !displayIcon.startsWith(kLibraryIconPrefix) =>
      classicPen,
    StampTool() => stamp,
    TextureTool() => patternFill,
    TableTool() => table,
    BarcodeTool() => barcode,
    RulerTool() => straightedge,
    GridTool() => grid,
    SpacerTool() => insertSpace,
    AreaTool() => artboard,
    WallTool() => wall,
    LaserTool() => laserPointer,
    PresentationTool() => presentation,
    HandTool() => hand,
    EyeDropperTool() => eyedropper,
    FullScreenTool() => fullScreen,
    CollectionTool() => collections,
    _ => null,
  };

  AmazeIconData get icon => switch (this) {
    shapes => const PhosphorAmazeIcon(
      PhosphorIconsLight.shapes,
      PhosphorIconsFill.shapes,
    ),
    barcode => const PhosphorAmazeIcon(
      PhosphorIconsLight.qrCode,
      PhosphorIconsFill.qrCode,
    ),
    _ => PhosphorAmazeIcon(defaultTool.icon(), defaultTool.icon(filled: true)),
  };

  String getLocalizedName(AppLocalizations loc) => switch (this) {
    select => loc.amazeToolSelect,
    eraser => loc.amazeToolEraser,
    shapes => loc.amazeToolShapes,
    polygon => loc.amazeToolPolygon,
    text => loc.amazeToolText,
    classicPen => loc.amazeToolClassicPen,
    stamp => loc.amazeToolStamp,
    patternFill => loc.amazeToolPatternFill,
    table => loc.amazeToolTable,
    barcode => loc.amazeToolBarcode,
    straightedge => loc.amazeToolStraightedge,
    grid => loc.amazeToolGrid,
    insertSpace => loc.amazeToolInsertSpace,
    artboard => loc.amazeToolArtboard,
    wall => loc.amazeToolWall,
    laserPointer => loc.amazeToolLaserPointer,
    presentation => loc.amazeToolPresentation,
    hand => loc.amazeToolHand,
    eyedropper => loc.amazeToolEyedropper,
    fullScreen => loc.amazeToolFullScreen,
    collections => loc.amazeToolCollections,
  };

  /// The name of a slot holding this family's tool. Only the More tools
  /// tile tells the classic pen apart; in a slot it is just the pen.
  String getSlotName(AppLocalizations loc) => switch (this) {
    classicPen => loc.pen,
    _ => getLocalizedName(loc),
  };

  /// One plain sentence: what the tool does and how to use it.
  String getLocalizedInfo(AppLocalizations loc) => switch (this) {
    select => loc.amazeInfoSelect,
    eraser => loc.amazeInfoEraser,
    shapes => loc.amazeInfoShapes,
    polygon => loc.amazeInfoPolygon,
    text => loc.amazeInfoText,
    classicPen => loc.amazeInfoClassicPen,
    stamp => loc.amazeInfoStamp,
    patternFill => loc.amazeInfoPatternFill,
    table => loc.amazeInfoTable,
    barcode => loc.amazeInfoBarcode,
    straightedge => loc.amazeInfoStraightedge,
    grid => loc.amazeInfoGrid,
    insertSpace => loc.amazeInfoInsertSpace,
    artboard => loc.amazeInfoArtboard,
    wall => loc.amazeInfoWall,
    laserPointer => loc.amazeInfoLaserPointer,
    presentation => loc.amazeInfoPresentation,
    hand => loc.amazeInfoHand,
    eyedropper => loc.amazeInfoEyedropper,
    fullScreen => loc.amazeInfoFullScreen,
    collections => loc.amazeInfoCollections,
  };

  /// Whether [query] matches this family's name or description.
  bool matches(AppLocalizations loc, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return getLocalizedName(loc).toLowerCase().contains(q) ||
        getLocalizedInfo(loc).toLowerCase().contains(q);
  }
}

/// The name of one subtype of a family, for choosers.
String toolVariantName(BuildContext context, Tool tool) => switch (tool) {
  SelectTool(:final mode) => mode.getLocalizedName(context),
  EraserTool(:final mode) => mode.getLocalizedName(context),
  ShapeTool(:final property) => property.shape.getLocalizedName(context),
  BarcodeTool(:final barcodeType) => barcodeType.getLocalizedName(context),
  SpacerTool(:final axis) => axis.getLocalizedName(context),
  _ => tool.getLocalizedName(context),
};

/// The icon of one subtype of a family, for choosers.
PhosphorIconData toolVariantIcon(Tool tool) => switch (tool) {
  SelectTool(:final mode) => mode.icon(),
  EraserTool(:final mode) => mode.icon(),
  BarcodeTool(:final barcodeType) => barcodeType.icon(),
  SpacerTool(:final axis) => axis.icon(),
  _ => tool.icon(),
};

/// Whether [a] and [b] are the same subtype of one family.
bool sameToolVariant(Tool a, Tool b) => switch ((a, b)) {
  (SelectTool a, SelectTool b) => a.mode == b.mode,
  (EraserTool a, EraserTool b) => a.mode == b.mode,
  (ShapeTool a, ShapeTool b) =>
    a.property.shape.runtimeType == b.property.shape.runtimeType,
  (BarcodeTool a, BarcodeTool b) => a.barcodeType == b.barcodeType,
  (SpacerTool a, SpacerTool b) => a.axis == b.axis,
  _ => a.runtimeType == b.runtimeType,
};

/// [current] switched to the subtype of [variant]. The tool keeps its id,
/// name and other settings where the two share them.
Tool applyToolVariant(Tool current, Tool variant) =>
    switch ((current, variant)) {
      (SelectTool c, SelectTool v) => c.copyWith(mode: v.mode),
      (EraserTool c, EraserTool v) => c.copyWith(mode: v.mode),
      (ShapeTool c, ShapeTool v) => c.copyWith(
        property: c.property.copyWith(shape: v.property.shape),
      ),
      (BarcodeTool c, BarcodeTool v) => c.copyWith(barcodeType: v.barcodeType),
      (SpacerTool c, SpacerTool v) => c.copyWith(axis: v.axis),
      _ => variant.copyWith(id: current.id),
    };
