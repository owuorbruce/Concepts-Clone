import 'dart:typed_data';

import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/api/open.dart';
import 'package:butterfly/models/marker_palette.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Where the picker reads saved palettes from and imports new ones into.
abstract interface class AmazePaletteSource {
  /// The saved palettes of every pack, in pack order.
  Future<List<NamedItem<ColorPalette>>> load();

  /// Lets the user choose palette files and saves them. Returns one message
  /// per file that could not be read.
  Future<List<String>> import();
}

/// Reads palettes from the core and user packs and imports palette files
/// into the user's core pack, as the pack dialog does.
class PackPaletteSource implements AmazePaletteSource {
  const PackPaletteSource(this.fileSystem);

  final ButterflyFileSystem fileSystem;

  @override
  Future<List<NamedItem<ColorPalette>>> load() async {
    final packs = await fileSystem.getCoreAndUserPacks();
    return [for (final (_, pack) in packs) ...pack.getNamedPalettes()];
  }

  @override
  Future<List<String>> import() async =>
      importFiles(await importFilesWithExtensions(kPaletteFileExtensions));

  /// Saves the palettes in [files] (data, extension, name) to the user's
  /// core pack under unique names, and returns one message per bad file.
  Future<List<String>> importFiles(
    List<(Uint8List, String, String)> files,
  ) async {
    if (files.isEmpty) return const [];
    final (namespace, original) =
        (await fileSystem.getCoreAndUserPacks()).first;
    var pack = original;
    final errors = <String>[];
    for (final (data, extension, fileName) in files) {
      try {
        for (final palette in importPaletteFile(
          data,
          fileExtension: extension,
          name: fileName,
        )) {
          pack = pack.setPalette(_uniqueName(pack, palette.name), palette.item);
        }
      } on FormatException catch (e) {
        errors.add('$fileName.$extension: ${e.message}');
      }
    }
    if (!identical(pack, original)) {
      await fileSystem.updatePack(PackAssetLocation(namespace, ''), pack);
    }
    return errors;
  }

  static String _uniqueName(NoteData pack, String name) {
    final existing = pack.getPalettes().toSet();
    if (!existing.contains(name)) return name;
    var index = 2;
    while (existing.contains('$name ($index)')) {
      index++;
    }
    return '$name ($index)';
  }
}

/// The sheet behind the picker's "more" button: find a marker by code or
/// name, recent colors, a saved palette with a chooser and import, and the
/// marker data notice. Import errors are shown in the sheet.
class AmazeColorMoreSheet extends StatefulWidget {
  const AmazeColorMoreSheet({
    super.key,
    required this.color,
    required this.markers,
    required this.recentColors,
    required this.source,
    required this.onColor,
    required this.onMarker,
  });

  /// The current color, outlined wherever it appears.
  final SRGBColor color;

  /// The marker palette to search, or null if there is none.
  final MarkerPalette? markers;
  final List<SRGBColor> recentColors;
  final AmazePaletteSource? source;
  final ValueChanged<SRGBColor> onColor;
  final ValueChanged<MarkerColor> onMarker;

  @override
  State<AmazeColorMoreSheet> createState() => _AmazeColorMoreSheetState();
}

class _AmazeColorMoreSheetState extends State<AmazeColorMoreSheet> {
  List<NamedItem<ColorPalette>> _palettes = const [];
  int _selected = 0;
  bool _importing = false;
  String? _importError;
  String _query = '';

  static const _maxResults = 6;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final source = widget.source;
    if (source == null) return;
    final palettes = await source.load();
    if (!mounted) return;
    setState(() {
      _palettes = palettes;
      if (_selected >= palettes.length) _selected = 0;
    });
  }

  Future<void> _import() async {
    final source = widget.source;
    if (source == null || _importing) return;
    setState(() {
      _importing = true;
      _importError = null;
    });
    final List<String> errors;
    try {
      errors = await source.import();
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    await _load();
    if (!mounted || errors.isEmpty) return;
    setState(() => _importError = errors.join('\n'));
  }

  List<MarkerColor> get _results {
    final markers = widget.markers;
    if (markers == null || _query.trim().isEmpty) return const [];
    return markers.search(_query).take(_maxResults).toList();
  }

  Widget _swatch(Key key, SRGBColor color) {
    final selected = color == widget.color;
    return Tooltip(
      message: color.toHexString(alpha: color.a != 255),
      child: InkResponse(
        key: key,
        onTap: () => widget.onColor(color),
        radius: 22,
        child: SizedBox.square(
          dimension: 40,
          child: Center(
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Color(color.value),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.black38,
                  width: selected ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = _palettes.isEmpty ? null : _palettes[_selected];
    final results = _results;
    return SingleChildScrollView(
      key: const ValueKey('amaze-color-more-sheet'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.markers != null) ...[
            TextField(
              key: const ValueKey('amaze-color-find'),
              decoration: InputDecoration(
                labelText: loc.amazeColorFind,
                prefixIcon: const PhosphorIcon(
                  PhosphorIconsLight.magnifyingGlass,
                ),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                final first = results.firstOrNull;
                if (first != null) widget.onMarker(first);
              },
            ),
            for (final marker in results)
              ListTile(
                key: ValueKey(('amaze-color-find-result', marker.code)),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Color(marker.color.value),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black26),
                  ),
                ),
                title: Text('${marker.code}  ${marker.name}'),
                onTap: () => widget.onMarker(marker),
              ),
            const SizedBox(height: 12),
          ],
          if (widget.recentColors.isNotEmpty) ...[
            Text(loc.amazeColorRecent, style: theme.textTheme.labelLarge),
            Wrap(
              children: [
                for (final (index, color) in widget.recentColors.indexed)
                  _swatch(ValueKey(('amaze-color-recent', index)), color),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (widget.source != null) ...[
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: MenuAnchor(
                      menuChildren: [
                        for (final (index, item) in _palettes.indexed)
                          MenuItemButton(
                            key: ValueKey(('amaze-color-palette', index)),
                            leadingIcon: index == _selected
                                ? const PhosphorIcon(PhosphorIconsLight.check)
                                : const SizedBox(width: 24),
                            onPressed: () => setState(() => _selected = index),
                            child: Text(item.name),
                          ),
                      ],
                      builder: (context, controller, child) => TextButton.icon(
                        key: const ValueKey('amaze-color-palette-chooser'),
                        onPressed: _palettes.isEmpty
                            ? null
                            : () => controller.isOpen
                                  ? controller.close()
                                  : controller.open(),
                        icon: const PhosphorIcon(PhosphorIconsLight.palette),
                        label: Text(palette?.name ?? loc.palettes),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('amaze-color-import'),
                  tooltip: loc.import,
                  onPressed: _importing ? null : _import,
                  icon: const PhosphorIcon(PhosphorIconsLight.downloadSimple),
                ),
              ],
            ),
            if (_importError case final error?)
              Text(
                error,
                key: const ValueKey('amaze-color-import-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            if (palette != null)
              Wrap(
                children: [
                  for (final (index, color) in palette.item.colors.indexed)
                    _swatch(
                      ValueKey(('amaze-color-palette-color', index)),
                      color,
                    ),
                ],
              ),
            const SizedBox(height: 8),
          ],
          Text(
            '${loc.amazeColorTrademark}\n${loc.amazeColorDataAttribution}',
            key: const ValueKey('amaze-color-info'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
