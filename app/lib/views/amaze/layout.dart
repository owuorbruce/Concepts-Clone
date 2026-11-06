import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/views/edit.dart';
import 'package:butterfly/views/toolbar/view.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import 'dock.dart';
import 'tool_wheel.dart';
import 'wheel_prefs.dart';

/// Editor layout of aMaze.
///
/// The canvas fills the screen. A dock on the left opens layers and the other
/// navigator pages, the movable [ToolWheel] picks tools, and the existing
/// tool options, property and zoom views float on top of the canvas.
class AmazeEditorLayout extends StatefulWidget {
  const AmazeEditorLayout({
    super.key,
    required this.viewport,
    required this.selectionListener,
    required this.zoom,
    required this.property,
    required this.showChrome,
    required this.editable,
    required this.large,
  });

  /// The canvas.
  final Widget viewport;

  /// Clears the selection when the canvas is tapped.
  final Widget selectionListener;

  /// Zoom controls; also shown while the rest of the interface is hidden.
  final Widget zoom;

  /// The selection property view.
  final Widget property;

  /// Whether the dock, tool options and tool wheel are shown.
  final bool showChrome;

  /// Whether the document can be edited.
  final bool editable;

  /// Whether there is room for side panels next to the canvas.
  final bool large;

  @override
  State<AmazeEditorLayout> createState() => _AmazeEditorLayoutState();
}

class _AmazeEditorLayoutState extends State<AmazeEditorLayout> {
  bool _showAllTools = false;
  // The wheel is the main drawing control, so the inherited tool options
  // and zoom panels start hidden and are turned on from the dock.
  AmazePanels _panels = (toolOptions: false, zoom: false);

  @override
  void initState() {
    super.initState();
    loadAmazePanels().then((panels) {
      if (mounted) setState(() => _panels = panels);
    });
  }

  void _toggleAllTools() => setState(() => _showAllTools = !_showAllTools);

  void _setPanels(AmazePanels panels) {
    setState(() => _panels = panels);
    saveAmazePanels(panels);
  }

  void _toggleToolOptions() {
    _setPanels((toolOptions: !_panels.toolOptions, zoom: _panels.zoom));
  }

  void _toggleZoom() {
    _setPanels((toolOptions: _panels.toolOptions, zoom: !_panels.zoom));
  }

  @override
  Widget build(BuildContext context) {
    final chrome = widget.showChrome;
    final tools = chrome && widget.editable;
    // Zoom stays visible while the interface is hidden: it holds the button
    // that brings the interface back.
    final overlays = <Widget>[
      if (_panels.zoom || !chrome) widget.zoom,
      widget.property,
    ];
    return Stack(
      children: [
        widget.viewport,
        widget.selectionListener,
        SafeArea(
          child: Row(
            textDirection: .ltr,
            children: [
              if (chrome)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                    child: AmazeDock(
                      large: widget.large,
                      editable: widget.editable,
                      showAllTools: _showAllTools,
                      onToggleAllTools: _toggleAllTools,
                      showToolOptions: _panels.toolOptions,
                      onToggleToolOptions: _toggleToolOptions,
                      showZoom: _panels.zoom,
                      onToggleZoom: _toggleZoom,
                    ),
                  ),
                ),
              if (tools && _showAllTools)
                const Padding(
                  key: ValueKey('amaze-all-tools'),
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: EditToolbar(isMobile: false, direction: .vertical),
                ),
              if (chrome && widget.large)
                BlocSelector<EditorViewCubit, EditorViewState, bool>(
                  selector: (state) => state.navigatorEnabled,
                  builder: (context, enabled) {
                    if (!enabled) return const SizedBox.shrink();
                    return const AmazeNavigatorPanel();
                  },
                ),
              Expanded(
                child: Column(
                  children: [
                    if (tools && _panels.toolOptions) const ToolbarView(),
                    Expanded(child: Stack(children: overlays)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (tools)
          const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: AmazeToolWheelLayer(key: ValueKey('amaze-wheel-layer')),
            ),
          ),
      ],
    );
  }
}
