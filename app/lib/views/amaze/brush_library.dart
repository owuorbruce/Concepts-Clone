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
const kBrushLibraryWidth = 400.0;

/// The brush library: picks the brush or tool of one wheel slot.
///
/// Shows the slot's current tool at the top, then the basic brushes, the
/// tools and the brush market in one scroll view. Entries the canvas cannot
/// do yet are shown dimmed and cannot be picked.
class BrushLibrarySidebar extends StatefulWidget {
  const BrushLibrarySidebar({
    super.key,
    required this.slot,
    required this.onSelect,
    required this.onClose,
    this.onSlotOptions,
  });

  /// The slot (0 to 7) the library picks for.
  final int slot;

  final ValueChanged<LibraryEntry> onSelect;
  final VoidCallback onClose;

  /// Opens the slot menu (settings, move, replace, remove). It is only
  /// offered while the slot holds a tool.
  final VoidCallback? onSlotOptions;

  @override
  State<BrushLibrarySidebar> createState() => _BrushLibrarySidebarState();
}

class _BrushLibrarySidebarState extends State<BrushLibrarySidebar> {
  bool _marketOpen = false;

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
        onSelect: widget.onSelect,
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
                const SizedBox(height: 12),
                _MarketHeader(
                  open: _marketOpen,
                  style: style,
                  onTap: () => setState(() => _marketOpen = !_marketOpen),
                ),
                if (_marketOpen) grid(LibrarySection.market),
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
    final glyph = entry?.glyph;
    final Widget preview;
    if (glyph != null && glyph.isBrush) {
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
    final available = entry.available;
    final name = entry.getLocalizedName(loc);
    final foreground = selected ? style.onAccent : style.onSurface;
    final glyph = entry.glyph;
    final Widget icon;
    if (glyph != null && (glyph.isBrush || glyph.isPack)) {
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
        onTap: available ? () => onSelect(entry) : null,
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
    if (available) {
      return Semantics(
        button: true,
        selected: selected,
        label: name,
        child: tile,
      );
    }
    return Tooltip(
      message: '$name: ${loc.notAvailableYet}',
      child: Semantics(
        enabled: false,
        label: '$name, ${loc.notAvailableYet}',
        child: Stack(
          children: [
            Positioned.fill(child: Opacity(opacity: 0.38, child: tile)),
            Positioned(
              top: 5,
              right: 5,
              child: AmazeIcon(
                AmazeIcons.unavailable,
                size: 14,
                color: style.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
