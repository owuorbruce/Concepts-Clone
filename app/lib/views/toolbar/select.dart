import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:material_ui/material_ui.dart';

/// The one-line explanation of a select hit mode.
String selectHitModeInfo(AppLocalizations loc, HitElementMode mode) =>
    switch (mode) {
      HitElementMode.full => loc.amazeHitEnclosedInfo,
      HitElementMode.touchEdges => loc.amazeHitEdgesInfo,
      _ => loc.amazeHitTouchingInfo,
    };

/// Toolbar of the select tool: Touching and Enclosed, with what the
/// current one does. "Touch edges" stays in the tool's settings.
class SelectToolbarView extends StatelessWidget implements PreferredSizeWidget {
  const SelectToolbarView({
    super.key,
    required this.tool,
    required this.onToolChanged,
  });

  final SelectTool tool;
  final ValueChanged<SelectTool> onToolChanged;

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final mode = tool.hitElementMode;
    Widget chip(HitElementMode value, String label) => ChoiceChip(
      key: ValueKey(('amaze-select-hit', value.name)),
      label: Text(label),
      selected: mode == value,
      onSelected: (_) => onToolChanged(tool.copyWith(hitElementMode: value)),
    );
    return SizedBox(
      height: preferredSize.height,
      child: Row(
        spacing: 8,
        children: [
          const SizedBox(width: 8),
          chip(HitElementMode.touchAnywhere, loc.amazeHitTouching),
          chip(HitElementMode.full, loc.amazeHitEnclosed),
          Expanded(
            child: Text(
              selectHitModeInfo(loc, mode),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
