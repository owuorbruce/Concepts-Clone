part of 'handler.dart';

class FullScreenHandler extends Handler<FullScreenTool> {
  FullScreenHandler(super.data);

  @override
  SelectState onSelected(BuildContext context, [bool wasAdded = true]) {
    final controller = context.read<EditorController>();
    final window = context.read<WindowCubit>();
    final loc = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    unawaited(
      toggleFullScreen(controller, window).then((_) {
        final on = controller.saveCubit.state.embedding != null
            ? controller.saveCubit.state.fullScreen
            : window.state.fullScreen;
        // A short confirmation, since a tablet may show no window frame.
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(milliseconds: 1500),
              content: Text(
                on ? loc.amazeFullScreenOn : loc.amazeFullScreenOff,
              ),
            ),
          );
      }),
    );
    return SelectState.none;
  }

  @override
  PhosphorIconData getIcon(DocumentBloc bloc) =>
      (bloc.editorController.saveCubit.state.embedding != null
          ? bloc.editorController.saveCubit.state.fullScreen
          : bloc.state.windowCubit.state.fullScreen)
      ? PhosphorIconsLight.arrowsIn
      : PhosphorIconsLight.arrowsOut;
}
