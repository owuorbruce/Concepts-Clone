import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/visualizer/tool.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'tool_slots.dart';

/// What to do with a filled tool slot.
enum ToolSlotAction { configure, replace, moveEarlier, moveLater, remove }

/// Shows the actions for the tool in [slot].
Future<ToolSlotAction?> showToolSlotMenu(
  BuildContext context, {
  required Tool tool,
  required int slot,
  required int filledSlots,
}) {
  return showModalBottomSheet<ToolSlotAction>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final loc = AppLocalizations.of(context);
      void pick(ToolSlotAction action) => Navigator.of(context).pop(action);
      return SafeArea(
        child: Column(
          mainAxisSize: .min,
          children: [
            ListTile(
              leading: PhosphorIcon(tool.icon(filled: true)),
              title: Text(tool.getDisplay(context)),
              subtitle: Text(loc.toolSlot(slot + 1)),
            ),
            const Divider(height: 1),
            ListTile(
              key: const ValueKey('amaze-slot-configure'),
              leading: const PhosphorIcon(PhosphorIconsLight.slidersHorizontal),
              title: Text(loc.toolSettings),
              onTap: () => pick(ToolSlotAction.configure),
            ),
            ListTile(
              key: const ValueKey('amaze-slot-replace'),
              leading: const PhosphorIcon(PhosphorIconsLight.swap),
              title: Text(loc.replaceTool),
              onTap: () => pick(ToolSlotAction.replace),
            ),
            ListTile(
              key: const ValueKey('amaze-slot-earlier'),
              enabled: slot > 0,
              leading: const PhosphorIcon(PhosphorIconsLight.arrowLeft),
              title: Text(loc.moveToPreviousSlot),
              onTap: () => pick(ToolSlotAction.moveEarlier),
            ),
            ListTile(
              key: const ValueKey('amaze-slot-later'),
              enabled: slot < filledSlots - 1,
              leading: const PhosphorIcon(PhosphorIconsLight.arrowRight),
              title: Text(loc.moveToNextSlot),
              onTap: () => pick(ToolSlotAction.moveLater),
            ),
            ListTile(
              key: const ValueKey('amaze-slot-remove'),
              leading: const PhosphorIcon(PhosphorIconsLight.trash),
              title: Text(loc.removeTool),
              onTap: () => pick(ToolSlotAction.remove),
            ),
          ],
        ),
      );
    },
  );
}

/// Lets the user choose a tool for a slot from [slotToolCatalog].
Future<Tool?> showToolSlotCatalog(BuildContext context) {
  final tools = slotToolCatalog();
  return showModalBottomSheet<Tool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final loc = AppLocalizations.of(context);
      final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: .min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  loc.chooseTool,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: GridView.extent(
                  maxCrossAxisExtent: 128,
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(12),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final (index, tool) in tools.indexed)
                      _CatalogTile(
                        key: ValueKey(('amaze-catalog', index)),
                        tool: tool,
                        onTap: () => Navigator.of(context).pop(tool),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({super.key, required this.tool, required this.onTap});

  final Tool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final caption = tool.getLocalizedCaption(context);
    final textTheme = Theme.of(context).textTheme;
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: .center,
            children: [
              PhosphorIcon(tool.icon(), size: 28),
              const SizedBox(height: 6),
              Text(
                tool.getLocalizedName(context),
                textAlign: .center,
                maxLines: 1,
                overflow: .ellipsis,
                style: textTheme.labelLarge,
              ),
              if (caption.isNotEmpty)
                Text(
                  caption,
                  textAlign: .center,
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
