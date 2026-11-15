import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../style.dart';
import 'object_favorites.dart';
import 'object_store.dart';

/// Width of the object library on large screens.
const kObjectLibraryWidth = 360.0;

/// Screens narrower than this show the object library at full width.
const kObjectLibraryFullWidthBreakpoint = 600.0;

/// How long the object library takes to slide in or out.
const kObjectLibraryAnimation = Duration(milliseconds: 150);

/// Minimum tile size in the object grid.
const kObjectTileMinWidth = 80.0;
const kObjectTileHeight = 112.0;
const _tileSpacing = 8.0;

/// Places the object library on the right edge and slides it in and out.
class ObjectLibraryLayer extends StatefulWidget {
  const ObjectLibraryLayer({
    super.key,
    required this.open,
    required this.editable,
    required this.onClose,
    required this.onPlace,
    this.loadPacks,
  });

  final bool open;
  final bool editable;
  final VoidCallback onClose;
  final ValueChanged<ObjectEntry> onPlace;

  /// Loads the packs; defaults to [loadObjectPacks].
  final Future<List<ObjectPack>> Function()? loadPacks;

  @override
  State<ObjectLibraryLayer> createState() => _ObjectLibraryLayerState();
}

class _ObjectLibraryLayerState extends State<ObjectLibraryLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kObjectLibraryAnimation,
    value: widget.open ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));

  late final Animation<Offset> _slide = Tween(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void didUpdateWidget(ObjectLibraryLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open && _controller.isDismissed) {
      return const SizedBox.shrink();
    }
    final full =
        MediaQuery.sizeOf(context).width < kObjectLibraryFullWidthBreakpoint;
    return Positioned.fill(
      child: SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              key: const ValueKey('amaze-object-library'),
              width: full ? constraints.maxWidth : kObjectLibraryWidth,
              height: constraints.maxHeight,
              child: SlideTransition(
                position: _slide,
                child: Padding(
                  padding: EdgeInsets.all(full ? 0 : 8),
                  child: ObjectLibraryPanel(
                    editable: widget.editable,
                    onClose: widget.onClose,
                    onPlace: widget.onPlace,
                    loadPacks: widget.loadPacks,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The object library: the components of all packs, placed on the canvas by
/// a tap or a drag.
class ObjectLibraryPanel extends StatefulWidget {
  const ObjectLibraryPanel({
    super.key,
    required this.editable,
    required this.onClose,
    required this.onPlace,
    this.loadPacks,
  });

  /// Whether the drawing can be edited. Tiles are disabled otherwise.
  final bool editable;
  final VoidCallback onClose;
  final ValueChanged<ObjectEntry> onPlace;
  final Future<List<ObjectPack>> Function()? loadPacks;

  @override
  State<ObjectLibraryPanel> createState() => _ObjectLibraryPanelState();
}

class _ObjectLibraryPanelState extends State<ObjectLibraryPanel> {
  final _scope = FocusScopeNode(debugLabel: 'amaze-object-library');
  final _search = TextEditingController();
  List<ObjectPack>? _packs;
  ObjectFavorites _favorites = const ObjectFavorites();
  String _query = '';

  @override
  void initState() {
    super.initState();
    final load =
        widget.loadPacks ??
        () => loadObjectPacks(context.read<ButterflyFileSystem>());
    Future.wait([load(), ObjectFavorites.load()]).then((result) {
      if (!mounted) return;
      setState(() {
        _packs = result[0] as List<ObjectPack>;
        _favorites = result[1] as ObjectFavorites;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scope.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _update(Future<ObjectFavorites> change) async {
    final next = await change;
    if (mounted) setState(() => _favorites = next);
  }

  bool _matches(ObjectEntry entry) {
    if (_query.isEmpty) return true;
    bool has(String? text) => text?.toLowerCase().contains(_query) ?? false;
    return has(entry.name) || has(entry.category) || has(entry.packName);
  }

  /// Favorite packs, bundled, core, then user packs alphabetically.
  List<ObjectPack> _orderedPacks(List<ObjectPack> packs) {
    int rank(ObjectPack pack) => switch (pack.source) {
      .bundled => 0,
      .core => 1,
      .user => 2,
    };
    final sorted = [...packs]
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        if (a.source != .user) return 0;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return [
      ...sorted.where((p) => _favorites.isFavoritePack(p.id)),
      ...sorted.where((p) => !_favorites.isFavoritePack(p.id)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final style = AmazeStyle.of(context);
    final loc = AppLocalizations.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: FocusScope(
        node: _scope,
        child: AmazeSurface(
          radius: 24,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        loc.amazeObjects,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: style.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('amaze-objects-close'),
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      onPressed: widget.onClose,
                      icon: PhosphorIcon(
                        PhosphorIconsLight.x,
                        color: style.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  key: const ValueKey('amaze-objects-search'),
                  controller: _search,
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: loc.amazeSearchObjects,
                    prefixIcon: const PhosphorIcon(
                      PhosphorIconsLight.magnifyingGlass,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Divider(height: 1, color: style.outline),
              Expanded(child: _buildContent(context, style, loc)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AmazeStyle style,
    AppLocalizations loc,
  ) {
    final packs = _packs;
    if (packs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    Widget message(String text, Key key) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          key: key,
          textAlign: TextAlign.center,
          style: TextStyle(color: style.muted),
        ),
      ),
    );
    if (packs.isEmpty) {
      return message(
        loc.amazeNoObjectsYet,
        const ValueKey('amaze-objects-empty'),
      );
    }
    final children = <Widget>[];
    final favorites = _favorites.resolve(packs).where(_matches).toList();
    if (favorites.isNotEmpty) {
      children
        ..add(
          _Heading(
            key: const ValueKey('amaze-objects-favorites'),
            text: loc.amazeFavorites,
            style: style,
          ),
        )
        ..add(_grid(favorites, 'amaze-object-favorite'));
    }
    for (final pack in _orderedPacks(packs)) {
      final visible = pack.objects.where(_matches).toList();
      if (visible.isEmpty) continue;
      final collapsed = _query.isEmpty && _favorites.isCollapsed(pack.id);
      children.add(
        _PackHeader(
          key: ValueKey(('amaze-object-pack', pack.id)),
          pack: pack,
          style: style,
          collapsed: collapsed,
          favorite: _favorites.isFavoritePack(pack.id),
          onToggle: () => _update(_favorites.toggleCollapsed(pack.id)),
          onToggleFavorite: () =>
              _update(_favorites.toggleFavoritePack(pack.id)),
        ),
      );
      if (collapsed) continue;
      final categories = <String, List<ObjectEntry>>{};
      final plain = <ObjectEntry>[];
      for (final entry in visible) {
        final category = entry.category;
        if (category == null) {
          plain.add(entry);
        } else {
          (categories[category] ??= []).add(entry);
        }
      }
      if (plain.isNotEmpty) children.add(_grid(plain, 'amaze-object'));
      for (final MapEntry(key: category, value: entries)
          in categories.entries) {
        children
          ..add(
            _CategoryHeading(
              key: ValueKey(('amaze-object-category', pack.id, category)),
              text: category,
              style: style,
            ),
          )
          ..add(_grid(entries, 'amaze-object'));
      }
    }
    if (children.isEmpty) {
      return message(
        loc.amazeNoObjectsFound,
        const ValueKey('amaze-objects-no-results'),
      );
    }
    return FocusTraversalGroup(
      child: ListView(
        key: const ValueKey('amaze-objects-scroll'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: children,
      ),
    );
  }

  Widget _grid(List<ObjectEntry> entries, String keyPrefix) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            ((constraints.maxWidth + _tileSpacing) /
                    (kObjectTileMinWidth + _tileSpacing))
                .floor()
                .clamp(1, 12);
        final width =
            (constraints.maxWidth - (columns - 1) * _tileSpacing) / columns;
        return Wrap(
          spacing: _tileSpacing,
          runSpacing: _tileSpacing,
          children: [
            for (final entry in entries)
              SizedBox(
                width: width,
                height: kObjectTileHeight,
                child: _ObjectTile(
                  key: ValueKey((keyPrefix, entry.packId, entry.key)),
                  starKey: ValueKey((
                    '$keyPrefix-star',
                    entry.packId,
                    entry.key,
                  )),
                  entry: entry,
                  editable: widget.editable,
                  favorite: _favorites.isFavorite(entry),
                  onPlace: () => widget.onPlace(entry),
                  onToggleFavorite: () =>
                      _update(_favorites.toggleFavorite(entry)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({super.key, required this.text, required this.style});

  final String text;
  final AmazeStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: style.onSurface, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CategoryHeading extends StatelessWidget {
  const _CategoryHeading({super.key, required this.text, required this.style});

  final String text;
  final AmazeStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: style.muted,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PackHeader extends StatelessWidget {
  const _PackHeader({
    super.key,
    required this.pack,
    required this.style,
    required this.collapsed,
    required this.favorite,
    required this.onToggle,
    required this.onToggleFavorite,
  });

  final ObjectPack pack;
  final AmazeStyle style;
  final bool collapsed, favorite;
  final VoidCallback onToggle, onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              PhosphorIcon(
                collapsed
                    ? PhosphorIconsLight.caretRight
                    : PhosphorIconsLight.caretDown,
                size: 16,
                color: style.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pack.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: style.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${pack.objects.length}',
                key: ValueKey(('amaze-object-pack-count', pack.id)),
                style: textTheme.labelMedium?.copyWith(color: style.muted),
              ),
              IconButton(
                key: ValueKey(('amaze-object-pack-star', pack.id)),
                isSelected: favorite,
                onPressed: onToggleFavorite,
                icon: PhosphorIcon(
                  PhosphorIconsLight.star,
                  size: 18,
                  color: style.muted,
                ),
                selectedIcon: PhosphorIcon(
                  PhosphorIconsFill.star,
                  size: 18,
                  color: style.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ObjectTile extends StatelessWidget {
  const _ObjectTile({
    super.key,
    required this.starKey,
    required this.entry,
    required this.editable,
    required this.favorite,
    required this.onPlace,
    required this.onToggleFavorite,
  });

  final Key starKey;
  final ObjectEntry entry;
  final bool editable, favorite;
  final VoidCallback onPlace, onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final style = AmazeStyle.of(context);
    final loc = AppLocalizations.of(context);
    Widget tile = Material(
      color: style.surfaceVariant,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: editable ? onPlace : null,
        child: Opacity(
          opacity: editable ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
            child: Column(
              children: [
                Expanded(child: ObjectPreview(component: entry.component)),
                const SizedBox(height: 4),
                Text(
                  entry.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: style.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (editable) {
      tile = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): onPlace,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): onPlace,
        },
        child: tile,
      );
      final feedback = Transform.translate(
        offset: const Offset(-36, -36),
        child: Opacity(
          opacity: 0.6,
          child: SizedBox.square(
            dimension: 72,
            child: ObjectPreview(component: entry.component),
          ),
        ),
      );
      tile = _TouchObjectDraggable(
        data: entry,
        feedback: feedback,
        child: _MouseObjectDraggable(
          data: entry,
          feedback: feedback,
          child: tile,
        ),
      );
    } else {
      tile = Tooltip(message: loc.amazeObjectReadOnly, child: tile);
    }
    return Stack(
      children: [
        Positioned.fill(child: tile),
        Positioned(
          top: 0,
          right: 0,
          child: SizedBox.square(
            dimension: 32,
            child: IconButton(
              key: starKey,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              isSelected: favorite,
              onPressed: onToggleFavorite,
              icon: PhosphorIcon(
                PhosphorIconsLight.star,
                size: 16,
                color: style.muted,
              ),
              selectedIcon: PhosphorIcon(
                PhosphorIconsFill.star,
                size: 16,
                color: style.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _touchDevices = {
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
};

/// Starts a drag after a long press, for touch and stylus.
class _TouchObjectDraggable extends LongPressDraggable<ObjectEntry> {
  const _TouchObjectDraggable({
    required super.data,
    required super.feedback,
    required super.child,
  }) : super(dragAnchorStrategy: pointerDragAnchorStrategy);

  @override
  DelayedMultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => DelayedMultiDragGestureRecognizer(
    delay: delay,
    supportedDevices: _touchDevices,
  )..onStart = onStart;
}

/// Starts a drag at once, for the mouse.
class _MouseObjectDraggable extends Draggable<ObjectEntry> {
  const _MouseObjectDraggable({
    required super.data,
    required super.feedback,
    required super.child,
  }) : super(dragAnchorStrategy: pointerDragAnchorStrategy);

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => ImmediateMultiDragGestureRecognizer(
    supportedDevices: const {PointerDeviceKind.mouse},
  )..onStart = onStart;
}

/// The preview of a component: its thumbnail, else its first element when
/// that is an SVG data URI, else a generic shapes icon.
class ObjectPreview extends StatelessWidget {
  const ObjectPreview({super.key, required this.component});

  final ButterflyComponent component;

  static Uint8List? svgData(ButterflyComponent component) {
    final first = component.elements.firstOrNull;
    if (first is! SvgElement || !first.source.startsWith('data:')) return null;
    try {
      return UriData.parse(first.source).contentAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = AmazeStyle.of(context);
    final fallback = Center(
      child: PhosphorIcon(
        PhosphorIconsLight.shapes,
        key: const ValueKey('amaze-object-preview-icon'),
        size: 32,
        color: style.muted,
      ),
    );
    final thumbnail = component.thumbnail;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      return Image.memory(
        thumbnail,
        key: const ValueKey('amaze-object-preview-image'),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    final svg = svgData(component);
    if (svg != null) {
      return SvgPicture.memory(
        svg,
        key: const ValueKey('amaze-object-preview-svg'),
        fit: BoxFit.contain,
      );
    }
    return fallback;
  }
}
