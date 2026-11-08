import 'dart:typed_data';

import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/api/open.dart';
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

/// White and black chips, recent colors, a saved palette with a chooser,
/// palette import and the eyedropper. Colors only go to [onPreview].
class PaletteStrip extends StatefulWidget {
  const PaletteStrip({
    super.key,
    required this.color,
    required this.recentColors,
    required this.source,
    required this.onPreview,
    required this.onEyedropper,
  });

  /// The previewed color, outlined wherever it appears.
  final SRGBColor color;
  final List<SRGBColor> recentColors;
  final AmazePaletteSource? source;
  final ValueChanged<SRGBColor> onPreview;
  final VoidCallback onEyedropper;

  @override
  State<PaletteStrip> createState() => _PaletteStripState();
}

class _PaletteStripState extends State<PaletteStrip> {
  List<NamedItem<ColorPalette>> _palettes = const [];
  int _selected = 0;
  bool _importing = false;

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
    setState(() => _importing = true);
    final List<String> errors;
    try {
      errors = await source.import();
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    await _load();
    if (errors.isEmpty || !mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(errors.join('\n'))));
  }

  Widget _swatch(Key key, SRGBColor color, String tooltip) {
    final selected = color == widget.color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          key: key,
          onTap: () => widget.onPreview(color),
          radius: 20,
          child: SizedBox.square(
            dimension: 36,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
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
      ),
    );
  }

  String _hex(SRGBColor color) => color.toHexString(alpha: color.a != 255);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final palette = _palettes.isEmpty ? null : _palettes[_selected];
    final divider = Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme.of(context).dividerColor,
    );
    return SingleChildScrollView(
      key: const ValueKey('amaze-color-strip'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('amaze-color-eyedropper'),
            tooltip: loc.eyeDropper,
            onPressed: widget.onEyedropper,
            icon: const PhosphorIcon(PhosphorIconsLight.eyedropper),
          ),
          _swatch(
            const ValueKey('amaze-color-white'),
            SRGBColor.white,
            _hex(SRGBColor.white),
          ),
          _swatch(
            const ValueKey('amaze-color-black'),
            SRGBColor.black,
            _hex(SRGBColor.black),
          ),
          if (widget.recentColors.isNotEmpty) ...[
            divider,
            Tooltip(
              message: loc.amazeColorRecent,
              child: const PhosphorIcon(
                PhosphorIconsLight.clockCounterClockwise,
              ),
            ),
            for (final (index, color) in widget.recentColors.indexed)
              _swatch(
                ValueKey(('amaze-color-recent', index)),
                color,
                _hex(color),
              ),
          ],
          divider,
          MenuAnchor(
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
          if (palette != null)
            for (final (index, color) in palette.item.colors.indexed)
              _swatch(
                ValueKey(('amaze-color-palette-color', index)),
                color,
                _hex(color),
              ),
          if (widget.source != null)
            IconButton(
              key: const ValueKey('amaze-color-import'),
              tooltip: loc.import,
              onPressed: _importing ? null : _import,
              icon: const PhosphorIcon(PhosphorIconsLight.downloadSimple),
            ),
        ],
      ),
    );
  }
}
