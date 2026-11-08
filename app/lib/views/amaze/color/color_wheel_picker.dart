import 'dart:math' as math;

import 'package:butterfly/models/marker_palette.dart';
import 'package:butterfly/services/marker_palette_loader.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';

import 'color_model.dart';
import 'marker_ring.dart';

sealed class AmazeColorResult {
  const AmazeColorResult();
}

final class AmazePickedColor extends AmazeColorResult {
  const AmazePickedColor(this.color);

  final SRGBColor color;
}

final class AmazeEyedropperRequested extends AmazeColorResult {
  const AmazeEyedropperRequested();
}

/// Opens a bounded overlay around the wheel. The viewport is repositioned
/// when the wheel is near an edge, and recalculated on window size changes.
Future<AmazeColorResult?> showAmazeColorWheel(
  BuildContext context, {
  required Offset center,
  required double innerRadius,
  required SRGBColor initial,
  Future<MarkerPalette?> Function()? paletteLoader,
}) async {
  final palette = await (paletteLoader ?? loadMarkerPalette)();
  final mode = await loadAmazeColorMode(palette: palette);
  if (!context.mounted) return null;
  return showGeneralDialog<AmazeColorResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppLocalizations.of(context).amazeColorCancel,
    barrierColor: Colors.black54,
    pageBuilder: (context, animation, secondaryAnimation) => _AmazeColorOverlay(
      center: center,
      innerRadius: innerRadius,
      initial: initial,
      palette: palette,
      initialMode: mode,
    ),
  );
}

class _AmazeColorOverlay extends StatefulWidget {
  const _AmazeColorOverlay({
    required this.center,
    required this.innerRadius,
    required this.initial,
    required this.palette,
    required this.initialMode,
  });

  final Offset center;
  final double innerRadius;
  final SRGBColor initial;
  final MarkerPalette? palette;
  final AmazeColorMode initialMode;

  @override
  State<_AmazeColorOverlay> createState() => _AmazeColorOverlayState();
}

class _AmazeColorOverlayState extends State<_AmazeColorOverlay> {
  late SRGBColor _preview = widget.initial;
  late AmazeColorMode _mode = widget.initialMode;
  MarkerColor? _pickedMarker;

  void _previewMarker(MarkerColor marker) {
    setState(() {
      _preview = marker.color.withValues(a: _preview.a);
      _pickedMarker = marker;
    });
  }

  void _setMode(AmazeColorMode mode) {
    setState(() => _mode = mode);
    saveAmazeColorMode(mode);
  }

  void _cancel() => Navigator.of(context).pop();

  void _done() => Navigator.of(context).pop(AmazePickedColor(_preview));

  void _showInfo() {
    final loc = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.information),
        content: Text(
          '${loc.amazeColorTrademark}\n\n${loc.amazeColorDataAttribution}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(loc.amazeColorDone),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final matches = markersFor(_preview, widget.palette);
    final code = _pickedMarker?.code ?? matches.map((m) => m.code).join(' / ');
    final name =
        _pickedMarker?.name ?? (matches.length == 1 ? matches.first.name : '');
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screen = constraints.biggest;
          final width = math.min(980.0, math.max(0.0, screen.width - 16));
          final height = math.min(740.0, math.max(0.0, screen.height - 16));
          final left = (widget.center.dx - width / 2)
              .clamp(8.0, math.max(8.0, screen.width - width - 8))
              .toDouble();
          final top = (widget.center.dy - height / 2)
              .clamp(8.0, math.max(8.0, screen.height - height - 8))
              .toDouble();
          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: Material(
                  elevation: 16,
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(20),
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (final mode in AmazeColorMode.values)
                              if (mode != AmazeColorMode.copic ||
                                  widget.palette != null)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: ChoiceChip(
                                    key: ValueKey(
                                      'amaze-color-mode-${mode.name}',
                                    ),
                                    label: Text(mode.name.toUpperCase()),
                                    selected: _mode == mode,
                                    onSelected: (_) => _setMode(mode),
                                  ),
                                ),
                            const Spacer(),
                            IconButton(
                              key: const ValueKey('amaze-color-info'),
                              tooltip: loc.information,
                              onPressed: _showInfo,
                              icon: const Icon(Icons.info_outline),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              key: const ValueKey('amaze-color-preview'),
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Color(_preview.value),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black54),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    code.isEmpty
                                        ? _preview.toHexString(alpha: false)
                                        : code,
                                  ),
                                  if (name.isNotEmpty) Text(name),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child:
                              widget.palette != null &&
                                  _mode == AmazeColorMode.copic
                              ? MarkerRing(
                                  palette: widget.palette!,
                                  innerRadius: widget.innerRadius,
                                  color: _preview.value,
                                  onPreview: _previewMarker,
                                )
                              : const SizedBox.expand(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              key: const ValueKey('amaze-color-cancel'),
                              onPressed: _cancel,
                              child: Text(loc.amazeColorCancel),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              key: const ValueKey('amaze-color-done'),
                              onPressed: _done,
                              child: Text(loc.amazeColorDone),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
