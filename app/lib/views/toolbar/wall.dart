import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/views/toolbar/color.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:material_ui/material_ui.dart';

/// Wall thicknesses offered as chips, in inches.
const kWallThicknessPresets = [4.5, 6.0];

/// The label of a wall thickness preset, for example `4½"`.
String wallThicknessLabel(double inches) {
  final whole = inches.truncate();
  final half = inches - whole == 0.5;
  if (half) return '$whole½"';
  final text = inches == inches.roundToDouble()
      ? inches.toInt().toString()
      : inches.toString();
  return '$text"';
}

/// Toolbar of the wall tool: its color, thickness chips and a thickness
/// field in inches.
class WallToolbarView extends StatefulWidget implements PreferredSizeWidget {
  const WallToolbarView({
    super.key,
    required this.bloc,
    required this.tool,
    required this.onToolChanged,
  });

  final DocumentBloc bloc;
  final WallTool tool;
  final ValueChanged<WallTool> onToolChanged;

  @override
  State<WallToolbarView> createState() => _WallToolbarViewState();

  @override
  Size get preferredSize => const Size.fromHeight(50);
}

class _WallToolbarViewState extends State<WallToolbarView> {
  late final _field = TextEditingController(text: _format(widget.tool));

  static String _format(WallTool tool) {
    final value = tool.thicknessIn;
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  @override
  void didUpdateWidget(WallToolbarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = _format(widget.tool);
    if (double.tryParse(_field.text) != widget.tool.thicknessIn) {
      _field.text = text;
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _setThickness(double value) {
    if (value <= 0 || value == widget.tool.thicknessIn) return;
    widget.onToolChanged(widget.tool.copyWith(thicknessIn: value));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final tool = widget.tool;
    return ColorToolbarView(
      color: tool.color,
      onChanged: (value) => widget.onToolChanged(tool.copyWith(color: value)),
      onEyeDropper: (context) {
        widget.bloc.editorController.toolCubit.changeTemporaryHandler(
          context,
          widget.bloc.editorController,
          EyeDropperTool(),
          bloc: widget.bloc,
          temporaryState: TemporaryState.removeAfterRelease,
        );
      },
      actions: [
        for (final preset in kWallThicknessPresets)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ChoiceChip(
              key: ValueKey(('amaze-wall-thickness', preset)),
              label: Text(wallThicknessLabel(preset)),
              selected: tool.thicknessIn == preset,
              onSelected: (_) => _setThickness(preset),
            ),
          ),
        SizedBox(
          width: 88,
          child: TextField(
            key: const ValueKey('amaze-wall-thickness-field'),
            controller: _field,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              isDense: true,
              labelText: loc.amazeWallThickness,
              suffixText: '"',
            ),
            onSubmitted: (value) {
              final parsed = double.tryParse(value.trim());
              if (parsed != null) _setThickness(parsed);
            },
          ),
        ),
      ],
    );
  }
}
