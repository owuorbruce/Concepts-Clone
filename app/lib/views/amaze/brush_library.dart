import 'package:butterfly/brushes/brush_preview.dart';
import 'package:butterfly/brushes/brush_registry.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/visualizer/tool.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'icons.dart';
import 'library.dart';
import 'style.dart';
import 'tool_slots.dart';

/// Width of the brush library sidebar.
const kBrushLibraryWidth = 360.0;

/// The brush library: picks the brush or tool of one wheel slot.
///
/// Shows the slot's current tool at the top, then the basic brushes, the
/// tools and the brush market in one scroll view. A market pack opens a
/// small sheet with its brushes.
class BrushLibrarySidebar extends StatefulWidget {
  const BrushLibrarySidebar({
    super.key,
    required this.slot,
    required this.onSelect,
    required this.onClose,
    this.onSelectTool,
    this.onSlotOptions,
  });

  /// The slot (0 to 7) the library picks for.
  final int slot;

  final ValueChanged<LibraryEntry> onSelect;
  final VoidCallback onClose;

  /// Puts a tool from [slotToolCatalog] into the slot. Without it the
  /// library has no "More tools".
  final ValueChanged<Tool>? onSelectTool;

  /// Opens the slot menu (settings, move, replace, remove). It is only
  /// offered while the slot holds a tool.
  final VoidCallback? onSlotOptions;

  @override
  State<BrushLibrarySidebar> createState() => _BrushLibrarySidebarState();
}

class _BrushLibrarySidebarState extends State<BrushLibrarySidebar> {
  bool _marketOpen = false;
  LibraryEntry? _openPack;

  void _selectEntry(LibraryEntry entry) {
    if (entry.isPack) {
      setState(() => _openPack = _openPack == entry ? null : entry);
      return;
    }
    widget.onSelect(entry);
  }

  void _selectPackBrush(LibraryEntry pack, String brushId) {
    final tool = pack.createPackTool(brushId);
    if (tool == null) return;
    final onSelectTool = widget.onSelectTool;
    if (onSelectTool != null) {
      onSelectTool(tool);
    } else {
      // Without a tool callback the pack's first brush is all that fits.
      widget.onSelect(pack);
    }
  }

  late final List<Tool> _catalog = slotToolCatalog();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentBloc, DocumentState>(
      builder: (context, state) {
        Tool? tool;
        if (state is DocumentLoadSuccess) {
          final tools = state.info.tools;
          final slots = slotToolIndices(tools);
          if (widget.slot < slots.length) tool = tools[slots[widget.slot]];
        }
        return _buildSidebar(context, tool);
      },
    );
  }

  Widget _buildSidebar(BuildContext context, Tool? tool) {
    final style = AmazeStyle.of(context);
    final loc = AppLocalizations.of(context);
    final current = tool == null ? null : libraryEntryOf(tool);
    final currentBrush = tool is PenTool ? tool.property.brush : null;
    final textTheme = Theme.of(context).textTheme;
    Widget heading(String text, {Key? key}) {
      return Padding(
        key: key,
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(
          text,
          style: textTheme.titleSmall?.copyWith(
            color: style.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    Widget label(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: textTheme.labelSmall?.copyWith(
            color: style.muted,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    Widget grid(LibrarySection section) {
      return _LibraryGrid(
        entries: LibraryEntry.of(section),
        current: current,
        style: style,
        onSelect: _selectEntry,
      );
    }

    return AmazeSurface(
      key: const ValueKey('amaze-brush-library'),
      radius: 24,
      child: Column(
        children: [
          _LibraryHeader(
            tool: tool,
            entry: current,
            slot: widget.slot,
            style: style,
            onClose: widget.onClose,
            onSlotOptions: tool == null ? null : widget.onSlotOptions,
          ),
          Divider(height: 1, color: style.outline),
          Expanded(
            child: ListView(
              key: const ValueKey('amaze-library-scroll'),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                heading(loc.myBrushes),
                label(loc.basics),
                grid(LibrarySection.basics),
                label(loc.tools),
                grid(LibrarySection.tools),
                if (widget.onSelectTool case final onSelectTool?) ...[
                  label(loc.amazeMoreTools),
                  _ToolCatalogGrid(
                    key: const ValueKey('amaze-library-more-tools'),
                    tools: _catalog,
                    style: style,
                    onSelect: onSelectTool,
                  ),
                ],
                const SizedBox(height: 12),
                _MarketHeader(
                  open: _marketOpen,
                  style: style,
                  onTap: () => setState(() => _marketOpen = !_marketOpen),
                ),
                if (_marketOpen) grid(LibrarySection.market),
                if (_openPack case final pack? when _marketOpen)
                  _PackSheet(
                    key: ValueKey(('amaze-library-pack', pack.name)),
                    pack: pack,
                    currentBrush: current == pack ? currentBrush : null,
                    style: style,
                    onSelect: (id) => _selectPackBrush(pack, id),
                    onClose: () => setState(() => _openPack = null),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.tool,
    required this.entry,
    required this.slot,
    required this.style,
    required this.onClose,
    this.onSlotOptions,
  });

  final Tool? tool;
  final LibraryEntry? entry;
  final int slot;
  final AmazeStyle style;
  final VoidCallback onClose;
  final VoidCallback? onSlotOptions;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final tool = this.tool;
    final name = tool?.getDisplay(context) ?? loc.emptySlot;
    // The slot's own brush, so a pack shows the brush that was picked.
    final brush = tool is PenTool
        ? brushById(tool.property.brush, tool.property.brushVersion) ??
              entry?.brushDefinition
        : entry?.brushDefinition;
    final glyph = entry?.glyph;
    final Widget preview;
    if (brush != null && !brush.mask) {
      preview = BrushEnginePreview(brush, color: style.onSurface);
    } else if (glyph != null && glyph.isBrush) {
      preview = AmazeBrushPreview(glyph, color: style.onSurface);
    } else if (tool != null) {
      preview = Center(
        child: AmazeIcon(amazeToolIcon(tool), size: 36, color: style.onSurface),
      );
    } else {
      preview = Center(
        child: PhosphorIcon(
          PhosphorIconsLight.plus,
          size: 32,
          color: style.muted,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Container(
            key: const ValueKey('amaze-library-preview'),
            width: 96,
            height: 60,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: style.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
            ),
            child: preview,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text(
                  loc.brushLibrary,
                  style: textTheme.labelMedium?.copyWith(color: style.muted),
                ),
                Text(
                  name,
                  key: const ValueKey('amaze-library-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    color: style.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  loc.toolSlot(slot + 1),
                  style: textTheme.labelSmall?.copyWith(color: style.muted),
                ),
              ],
            ),
          ),
          if (onSlotOptions != null)
            IconButton(
              key: const ValueKey('amaze-library-slot-menu'),
              tooltip: loc.slotOptions,
              onPressed: onSlotOptions,
              icon: AmazeIcon(AmazeIcons.slotOptions, color: style.onSurface),
            ),
          IconButton(
            key: const ValueKey('amaze-library-close'),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
            icon: PhosphorIcon(PhosphorIconsLight.x, color: style.onSurface),
          ),
        ],
      ),
    );
  }
}

class _MarketHeader extends StatelessWidget {
  const _MarketHeader({
    required this.open,
    required this.style,
    required this.onTap,
  });

  final bool open;
  final AmazeStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      key: const ValueKey('amaze-library-market'),
      color: style.surfaceVariant,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            spacing: 10,
            children: [
              PhosphorIcon(PhosphorIconsLight.storefront, color: style.accent),
              Expanded(
                child: Text(
                  loc.brushMarket,
                  style: textTheme.titleSmall?.copyWith(
                    color: style.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PhosphorIcon(
                open
                    ? PhosphorIconsLight.caretUp
                    : PhosphorIconsLight.caretDown,
                size: 18,
                color: style.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.entries,
    required this.current,
    required this.style,
    required this.onSelect,
  });

  final List<LibraryEntry> entries;
  final LibraryEntry? current;
  final AmazeStyle style;
  final ValueChanged<LibraryEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.8,
      children: [
        for (final entry in entries)
          _LibraryTile(
            entry: entry,
            selected: entry == current,
            style: style,
            onSelect: onSelect,
          ),
      ],
    );
  }
}

/// Every tool of [slotToolCatalog], as tiles in the library's style.
class _ToolCatalogGrid extends StatelessWidget {
  const _ToolCatalogGrid({
    super.key,
    required this.tools,
    required this.style,
    required this.onSelect,
  });

  final List<Tool> tools;
  final AmazeStyle style;
  final ValueChanged<Tool> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.8,
      children: [
        for (final (index, tool) in tools.indexed)
          Semantics(
            button: true,
            label: tool.getDisplay(context),
            child: Material(
              key: ValueKey(('amaze-library-tool', index)),
              color: style.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelect(tool),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: PhosphorIcon(
                            tool.icon(),
                            size: 30,
                            color: style.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tool.getDisplay(context),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: style.onSurface,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.entry,
    required this.selected,
    required this.style,
    required this.onSelect,
  });

  final LibraryEntry entry;
  final bool selected;
  final AmazeStyle style;
  final ValueChanged<LibraryEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final name = entry.getLocalizedName(loc);
    final foreground = selected ? style.onAccent : style.onSurface;
    final glyph = entry.glyph;
    final Widget icon;
    final brush = entry.brushDefinition;
    if (brush != null && !brush.mask) {
      // Brushes draw their preview stroke with their own engine.
      icon = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: BrushEnginePreview(brush, color: foreground),
      );
    } else if (glyph != null && (glyph.isBrush || glyph.isPack)) {
      // Brushes show a long stroke so their character reads at a glance.
      icon = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: AmazeBrushPreview(glyph, color: foreground),
      );
    } else if (glyph != null) {
      icon = Center(child: AmazeGlyphIcon(glyph, size: 34, color: foreground));
    } else {
      icon = Center(child: AmazeIcon(entry.icon, size: 30, color: foreground));
    }
    final tile = Material(
      key: ValueKey(('amaze-library-item', entry.name)),
      color: selected ? style.accent : style.surfaceVariant,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onSelect(entry),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Column(
            children: [
              Expanded(child: icon),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: foreground,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: tile,
    );
  }
}

/// The brushes of a market pack, drawn by their engine.
class _PackSheet extends StatelessWidget {
  const _PackSheet({
    super.key,
    required this.pack,
    required this.currentBrush,
    required this.style,
    required this.onSelect,
    required this.onClose,
  });

  final LibraryEntry pack;
  final String? currentBrush;
  final AmazeStyle style;
  final ValueChanged<String> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 10),
      decoration: BoxDecoration(
        border: Border.all(color: style.outline),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pack.getLocalizedName(loc),
                  style: textTheme.titleSmall?.copyWith(
                    color: style.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: onClose,
                icon: PhosphorIcon(
                  PhosphorIconsLight.x,
                  size: 18,
                  color: style.muted,
                ),
              ),
            ],
          ),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(right: 6),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.8,
            children: [
              for (final id in pack.packBrushIds)
                _PackBrushTile(
                  brushId: id,
                  selected: id == currentBrush,
                  style: style,
                  onSelect: onSelect,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PackBrushTile extends StatelessWidget {
  const _PackBrushTile({
    required this.brushId,
    required this.selected,
    required this.style,
    required this.onSelect,
  });

  final String brushId;
  final bool selected;
  final AmazeStyle style;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final definition = brushById(brushId);
    final name = definition?.name ?? brushId;
    final foreground = selected ? style.onAccent : style.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: Material(
        key: ValueKey(('amaze-library-pack-brush', brushId)),
        color: selected ? style.accent : style.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onSelect(brushId),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Column(
              children: [
                Expanded(
                  child: definition == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: BrushEnginePreview(
                            definition,
                            color: foreground,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: foreground,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
