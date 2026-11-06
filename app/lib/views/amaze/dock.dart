import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/views/navigator/view.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'style.dart';

/// Vertical dock on the edge of the aMaze editor.
///
/// It opens the document navigator pages (layers, pages, areas and more) and
/// turns the tool options, zoom controls and full tool bar on and off. On
/// large screens the navigator opens as a side panel next to the dock;
/// otherwise it opens as a dialog.
class AmazeDock extends StatelessWidget {
  const AmazeDock({
    super.key,
    required this.large,
    required this.editable,
    required this.showAllTools,
    required this.onToggleAllTools,
    required this.showToolOptions,
    required this.onToggleToolOptions,
    required this.showZoom,
    required this.onToggleZoom,
  });

  final bool large;
  final bool editable;
  final bool showAllTools;
  final VoidCallback onToggleAllTools;
  final bool showToolOptions;
  final VoidCallback onToggleToolOptions;
  final bool showZoom;
  final VoidCallback onToggleZoom;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final embedded = context.select<DocumentSaveCubit, bool>(
      (cubit) => cubit.state.embedding != null,
    );
    // Put the everyday drawing destinations first. Layers should not be
    // buried beneath Waypoints and Areas on a tablet drawing workspace.
    final pages = <NavigatorPage>[
      NavigatorPage.layers,
      NavigatorPage.pages,
      NavigatorPage.areas,
      NavigatorPage.waypoints,
      NavigatorPage.components,
      NavigatorPage.files,
    ].where((page) => !embedded || page != NavigatorPage.files).toList();
    return BlocBuilder<EditorViewCubit, EditorViewState>(
      buildWhen: (previous, current) =>
          previous.navigatorEnabled != current.navigatorEnabled ||
          previous.navigatorPage != current.navigatorPage,
      builder: (context, viewState) {
        final open = large && viewState.navigatorEnabled;
        return AmazeSurface(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: .min,
              spacing: 2,
              children: [
                for (final page in pages)
                  _DockButton(
                    key: ValueKey(('amaze-dock', page.name)),
                    icon: page.icon(),
                    selectedIcon: page.icon(filled: true),
                    tooltip: page.getLocalizedName(context),
                    selected: open && viewState.navigatorPage == page,
                    onPressed: () => _openPage(context, page, viewState),
                  ),
                const SizedBox(width: 32, child: Divider(height: 8)),
                if (editable)
                  _DockButton(
                    key: const ValueKey('amaze-dock-tool-options'),
                    icon: PhosphorIconsLight.slidersHorizontal,
                    selectedIcon: PhosphorIconsFill.slidersHorizontal,
                    tooltip: loc.toolOptions,
                    selected: showToolOptions,
                    onPressed: onToggleToolOptions,
                  ),
                _DockButton(
                  key: const ValueKey('amaze-dock-zoom'),
                  icon: PhosphorIconsLight.magnifyingGlass,
                  selectedIcon: PhosphorIconsFill.magnifyingGlass,
                  tooltip: loc.zoomControls,
                  selected: showZoom,
                  onPressed: onToggleZoom,
                ),
                if (editable)
                  _DockButton(
                    key: const ValueKey('amaze-dock-all-tools'),
                    icon: PhosphorIconsLight.toolbox,
                    selectedIcon: PhosphorIconsFill.toolbox,
                    tooltip: loc.allTools,
                    selected: showAllTools,
                    onPressed: onToggleAllTools,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openPage(
    BuildContext context,
    NavigatorPage page,
    EditorViewState viewState,
  ) {
    final cubit = context.read<EditorViewCubit>();
    if (large) {
      final isOpen =
          viewState.navigatorEnabled && viewState.navigatorPage == page;
      cubit.setNavigator(page: page, enabled: !isOpen);
      return;
    }
    cubit.setNavigator(page: page);
    showAmazeNavigatorDialog(context);
  }
}

/// Opens the document navigator as a dialog with the editor's state.
void showAmazeNavigatorDialog(BuildContext context) {
  final controller = context.read<EditorController>();
  final bloc = context.read<DocumentBloc>();
  final transformCubit = context.read<TransformCubit>();
  final sessionCubit = controller.editorSessionCubit;
  showDialog(
    context: context,
    builder: (context) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: bloc),
        BlocProvider.value(value: transformCubit),
        if (sessionCubit != null) BlocProvider.value(value: sessionCubit),
        BlocProvider.value(value: controller.rendererCubit),
        BlocProvider.value(value: controller.toolCubit),
        BlocProvider.value(value: controller.inputCubit),
        BlocProvider.value(value: controller.saveCubit),
        BlocProvider.value(value: controller.viewCubit),
      ],
      child: RepositoryProvider.value(
        value: controller,
        child: const DocumentNavigator(asDialog: true),
      ),
    ),
  );
}

/// Side panel that shows the document navigator on large screens.
class AmazeNavigatorPanel extends StatelessWidget {
  const AmazeNavigatorPanel({super.key, this.width = 340});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('amaze-navigator-panel'),
      width: width,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: AmazeSurface(child: DocumentNavigator()),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final PhosphorIconData icon;
  final PhosphorIconData selectedIcon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = AmazeStyle.of(context);
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: style.onSurface,
        backgroundColor: selected ? style.accent : null,
      ),
      selectedIcon: PhosphorIcon(selectedIcon, color: style.onAccent),
      icon: PhosphorIcon(icon),
    );
  }
}
