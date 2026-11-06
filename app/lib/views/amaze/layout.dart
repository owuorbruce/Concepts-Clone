import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/views/edit.dart';
import 'package:butterfly/views/toolbar/view.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'dock.dart';
import 'tool_wheel.dart';
import 'style.dart';

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
  // The wheel is the primary drawing control. Legacy tool and zoom panels
  // remain one tap away instead of consuming canvas space all the time.
  bool _showAdvancedControls = false;
  bool _showZoomControls = false;

  void _toggleAllTools() => setState(() => _showAllTools = !_showAllTools);

  @override
  Widget build(BuildContext context) {
    final chrome = widget.showChrome;
    final tools = chrome && widget.editable;
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
                    if (chrome && _showAdvancedControls)
                      const Padding(
                        padding: EdgeInsets.only(top: 56),
                        child: ToolbarView(),
                      ),
                    Expanded(
                      child: Stack(
                        children: [
                          if (_showZoomControls || !chrome)
                            Padding(
                              padding: EdgeInsets.only(top: 56),
                              child: widget.zoom,
                            ),
                          widget.property,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (chrome)
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 12),
                child: AmazeSurface(
                  radius: 18,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('amaze-advanced-controls-toggle'),
                        tooltip: 'Advanced tool controls',
                        color: _showAdvancedControls
                            ? AmazeStyle.of(context).accent
                            : AmazeStyle.of(context).onSurface,
                        icon: const PhosphorIcon(
                          PhosphorIconsLight.slidersHorizontal,
                        ),
                        onPressed: () => setState(
                          () => _showAdvancedControls = !_showAdvancedControls,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('amaze-zoom-toggle'),
                        tooltip: 'Zoom controls',
                        color: _showZoomControls
                            ? AmazeStyle.of(context).accent
                            : AmazeStyle.of(context).onSurface,
                        icon: const PhosphorIcon(
                          PhosphorIconsLight.magnifyingGlass,
                        ),
                        onPressed: () => setState(
                          () => _showZoomControls = !_showZoomControls,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
