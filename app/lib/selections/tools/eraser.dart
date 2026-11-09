part of '../selection.dart';

class EraserToolSelection extends ToolSelection<EraserTool> {
  EraserToolSelection(super.selected);

  @override
  List<Widget> buildProperties(BuildContext context) {
    final tool = selected.first;
    final currentMode = tool.hitElementMode;
    final loc = AppLocalizations.of(context);
    return [
      ...super.buildProperties(context),
      RadioGroup<EraserMode>(
        groupValue: tool.mode,
        onChanged: (value) {
          if (value == null) return;
          update(
            context,
            selected.map((e) => e.copyWith(mode: value)).toList(),
          );
        },
        child: Column(
          children: [
            for (final mode in EraserMode.values)
              RadioListTile<EraserMode>(
                key: ValueKey(('eraser-mode', mode.name)),
                value: mode,
                secondary: PhosphorIcon(mode.icon()),
                title: Text(_eraserModeTitle(loc, mode)),
                subtitle: Text(_eraserModeDescription(loc, mode)),
              ),
          ],
        ),
      ),
      ExactSlider(
        header: Text(loc.strokeWidth),
        value: tool.strokeWidth,
        min: 0,
        max: 70,
        sliderStep: 1,
        defaultValue: 5,
        onChangeEnd: (value) => update(
          context,
          selected.map((e) => e.copyWith(strokeWidth: value)).toList(),
        ),
      ),
      ExpansionTile(
        leading: const PhosphorIcon(PhosphorIconsLight.shapes),
        title: Text(loc.eraseShapes),
        subtitle: Text(currentMode.getLocalizedName(context, isEraser: true)),
        shape: const Border(),
        children: [
          RadioGroup<HitElementMode>(
            groupValue: currentMode,
            onChanged: (HitElementMode? value) {
              if (value != null) {
                update(
                  context,
                  selected
                      .map((e) => e.copyWith(hitElementMode: value))
                      .toList(),
                );
              }
            },
            child: Column(
              children: HitElementMode.eraserValues().map((mode) {
                return RadioListTile<HitElementMode>(
                  title: Text(mode.getLocalizedName(context, isEraser: true)),
                  value: mode,
                  activeColor: Theme.of(context).colorScheme.primary,
                  contentPadding: const EdgeInsets.only(
                    left: 56.0,
                    right: 16.0,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
      CheckboxListTile(
        value: tool.eraseElements,
        title: Text(loc.eraseAllElements),
        subtitle: Text(loc.eraseAllElementsDescription),
        secondary: const PhosphorIcon(PhosphorIconsLight.image),
        onChanged: (value) => update(
          context,
          selected
              .map((e) => e.copyWith(eraseElements: value ?? false))
              .toList(),
        ),
      ),
    ];
  }

  @override
  Selection insert(dynamic element) {
    if (element is EraserTool) {
      return EraserToolSelection([...selected, element]);
    }
    return super.insert(element);
  }
}

String _eraserModeTitle(AppLocalizations loc, EraserMode mode) {
  return switch (mode) {
    .stroke => loc.eraserModeStroke,
    .path => loc.eraserModePath,
  };
}

String _eraserModeDescription(AppLocalizations loc, EraserMode mode) {
  return switch (mode) {
    .stroke => loc.eraserModeStrokeDescription,
    .path => loc.eraserModePathDescription,
  };
}
