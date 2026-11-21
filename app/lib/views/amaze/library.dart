import 'package:butterfly/brushes/brush_registry.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/visualizer/tool.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'icons.dart';

/// Prefix of the display icon of tools made from the brush library.
const kLibraryIconPrefix = 'amaze.';

/// Where an entry is shown in the brush library.
enum LibrarySection { basics, tools, market }

/// An item of the brush library.
///
/// Entries that the canvas cannot do yet have no [createTool] result and are
/// shown as unavailable, never replaced by another tool.
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
      _ => AmazeIcons.unavailable,
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
    _ => null,
  };

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
      watercolor => _brushTool(const PenProperty()),
      fill => Tool.pen(
        property: const PenProperty(fillPaint: ElementPaint.solid()),
      ),
      lasso => Tool.select(mode: SelectMode.lasso),
      nudge => Tool.hand(),
      slice => Tool.eraser(mode: EraserMode.stroke),
      text => Tool.label(),
      pan => Tool.hand(),
      _ => null,
    };
  }

  /// A pen drawing with [brushId] at its newest version. The definition's
  /// default size and opacity apply unless [keepSize].
  Tool _brushTool(
    PenProperty base, {
    bool zoomDependent = false,
    bool keepSize = false,
  }) {
    final id = brushId!;
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
