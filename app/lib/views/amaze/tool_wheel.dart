import 'dart:math';

import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/visualizer/tool.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'style.dart';

/// Number of tool slots on one page of the wheel.
const kToolWheelSlots = 8;

/// Diameter of the collapsed wheel.
const kToolWheelPuckSize = 64.0;

/// Layout math for the tool wheel.
class ToolWheelGeometry {
  const ToolWheelGeometry({this.diameter = 248});

  /// Outer diameter of the open wheel.
  final double diameter;

  double get radius => diameter / 2;

  /// Diameter of one tool slot.
  double get slotSize => 50;

  /// Distance from the wheel center to the center of each slot.
  double get slotDistance => radius - slotSize / 2 - 8;

  /// Radius of the center hub.
  double get hubRadius => 60;

  /// Offset of [slot] from the wheel center. Slot 0 is at the top and the
  /// slots continue clockwise.
  Offset slotCenter(int slot) {
    final angle = -pi / 2 + 2 * pi * slot / kToolWheelSlots;
    return Offset(cos(angle), sin(angle)) * slotDistance;
  }
}

/// Number of wheel pages needed for [toolCount] tools.
int toolWheelPageCount(int toolCount) {
  final pages = (toolCount + kToolWheelSlots - 1) ~/ kToolWheelSlots;
  return max(1, pages);
}

/// Tool indices shown on [page], which is clamped to the available pages.
List<int> toolWheelPage(int toolCount, int page) {
  final last = toolWheelPageCount(toolCount) - 1;
  final start = page.clamp(0, last) * kToolWheelSlots;
  final end = min(toolCount, start + kToolWheelSlots);
  return [for (var i = start; i < end; i++) i];
}

/// Page of the wheel that shows the tool at [index].
int toolWheelPageOf(int index) => max(0, index) ~/ kToolWheelSlots;

/// Keeps a box of [size] at [position] fully inside [bounds].
Offset clampToolWheelPosition(Offset position, Size size, Size bounds) {
  final maxX = max(0.0, bounds.width - size.width);
  final maxY = max(0.0, bounds.height - size.height);
  return Offset(position.dx.clamp(0.0, maxX), position.dy.clamp(0.0, maxY));
}

Color? _handlerColor(Handler handler) {
  if (handler is ColoredHandler) return handler.getColor().toColor();
  return null;
}

/// Radial tool picker bound to the document's tools.
///
/// The ring selects tools, the hub shows the current tool and holds undo and
/// redo. Dragging the hub reports the movement through [onDrag].
class ToolWheel extends StatelessWidget {
  const ToolWheel({
    super.key,
    this.geometry = const ToolWheelGeometry(),
    this.page = 0,
    this.onPageChanged,
    this.onCollapse,
    this.onDrag,
  });

  final ToolWheelGeometry geometry;
  final int page;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onCollapse;
  final ValueChanged<Offset>? onDrag;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentBloc, DocumentState>(
      builder: (context, state) {
        if (state is! DocumentLoadSuccess) return const SizedBox.shrink();
        return BlocBuilder<ToolCubit, ToolRuntimeState>(
          builder: (context, toolState) {
            return _buildWheel(context, state, toolState);
          },
        );
      },
    );
  }

  Widget _buildWheel(
    BuildContext context,
    DocumentLoadSuccess state,
    ToolRuntimeState toolState,
  ) {
    final style = AmazeStyle.of(context);
    final tools = state.info.tools;
    final pages = toolWheelPageCount(tools.length);
    final current = page.clamp(0, pages - 1);
    final indices = toolWheelPage(tools.length, current);
    final center = Offset(geometry.radius, geometry.radius);
    final half = geometry.slotSize / 2;
    final slots = <Widget>[];
    for (var slot = 0; slot < indices.length; slot++) {
      final index = indices[slot];
      final offset = center + geometry.slotCenter(slot);
      slots.add(
        Positioned(
          left: offset.dx - half,
          top: offset.dy - half,
          width: geometry.slotSize,
          height: geometry.slotSize,
          child: _ToolSlot(
            index: index,
            tool: tools[index],
            toolState: toolState,
            style: style,
          ),
        ),
      );
    }
    return SizedBox.square(
      key: const ValueKey('amaze-tool-wheel'),
      dimension: geometry.diameter,
      child: Stack(
        children: [
          Positioned.fill(child: _WheelBackground(style: style)),
          ...slots,
          Center(
            child: _WheelHub(
              geometry: geometry,
              style: style,
              toolState: toolState,
              tools: tools,
              page: current,
              pages: pages,
              onPageChanged: onPageChanged,
              onCollapse: onCollapse,
              onDrag: onDrag,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolSlot extends StatelessWidget {
  const _ToolSlot({
    required this.index,
    required this.tool,
    required this.toolState,
    required this.style,
  });

  final int index;
  final Tool tool;
  final ToolRuntimeState toolState;
  final AmazeStyle style;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<EditorController>();
    final bloc = context.read<DocumentBloc>();
    final editable = controller.saveCubit.state.embedding?.editable != false;
    return controller.toolCubit.useHandler(
      bloc,
      index,
      (handler) => _buildButton(context, handler, bloc),
      editable: editable,
    );
  }

  Widget _buildButton(
    BuildContext context,
    Handler<Tool> handler,
    DocumentBloc bloc,
  ) {
    final toggled = toolState.toggleableHandlers.containsKey(index);
    final selected = index == toolState.index || toggled;
    final selection = toolState.selection?.selected ?? const [];
    final highlighted = selection.any((e) => e is Tool && e.id == tool.id);
    final status = handler.getStatus(bloc);
    final icon = handler.getIcon(bloc) ?? tool.icon(filled: selected);
    final color = switch (status) {
      .disabled => Theme.of(context).disabledColor,
      _ => selected ? style.onAccent : style.onSurface,
    };
    final border = highlighted
        ? CircleBorder(side: BorderSide(color: style.accent, width: 2))
        : const CircleBorder();
    // Long press opens the tool's options, so the tooltip only shows on hover.
    return Tooltip(
      message: tool.getDisplay(context),
      triggerMode: TooltipTriggerMode.manual,
      child: Material(
        key: ValueKey(('amaze-tool-wheel-slot', index)),
        color: selected ? style.accent : Colors.transparent,
        shape: border,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _select(context, bloc),
          onLongPress: () => context.read<ToolCubit>().changeSelection(tool),
          child: Center(child: PhosphorIcon(icon, size: 24, color: color)),
        ),
      ),
    );
  }

  void _select(BuildContext context, DocumentBloc bloc) {
    final controller = context.read<EditorController>();
    final cubit = controller.toolCubit;
    if (index != toolState.index || toolState.temporaryHandler != null) {
      cubit.resetSelection();
      cubit.changeTool(controller, bloc, index: index, context: context);
      return;
    }
    cubit.changeSelection(tool, true);
  }
}

class _WheelHub extends StatelessWidget {
  const _WheelHub({
    required this.geometry,
    required this.style,
    required this.toolState,
    required this.tools,
    required this.page,
    required this.pages,
    this.onPageChanged,
    this.onCollapse,
    this.onDrag,
  });

  final ToolWheelGeometry geometry;
  final AmazeStyle style;
  final ToolRuntimeState toolState;
  final List<Tool> tools;
  final int page;
  final int pages;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onCollapse;
  final ValueChanged<Offset>? onDrag;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<DocumentBloc>();
    final loc = AppLocalizations.of(context);
    final size = geometry.hubRadius * 2;
    final drag = onDrag;
    final changePage = onPageChanged;
    final dark = Color.lerp(style.accent, const Color(0xFF000000), 0.3)!;
    return GestureDetector(
      key: const ValueKey('amaze-tool-wheel-hub'),
      behavior: HitTestBehavior.opaque,
      onPanUpdate: drag == null ? null : (details) => drag(details.delta),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [style.accent, dark],
          ),
        ),
        child: Stack(
          children: [
            Center(child: _buildCurrentTool(context)),
            Align(
              alignment: Alignment.centerLeft,
              child: _buildHubButton(
                key: const ValueKey('amaze-tool-wheel-undo'),
                icon: PhosphorIconsLight.arrowCounterClockwise,
                tooltip: loc.undo,
                onPressed: bloc.canSendUndo ? bloc.sendUndo : null,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _buildHubButton(
                key: const ValueKey('amaze-tool-wheel-redo'),
                icon: PhosphorIconsLight.arrowClockwise,
                tooltip: loc.redo,
                onPressed: bloc.canSendRedo ? bloc.sendRedo : null,
              ),
            ),
            if (pages > 1 && changePage != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: TextButton(
                  key: const ValueKey('amaze-tool-wheel-page'),
                  style: TextButton.styleFrom(
                    foregroundColor: style.onAccent,
                    minimumSize: const Size(40, 24),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => changePage((page + 1) % pages),
                  child: Text('${page + 1}/$pages'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTool(BuildContext context) {
    final index = toolState.index;
    final tool = index == null ? null : tools.elementAtOrNull(index);
    final ring = _handlerColor(toolState.handler) ?? style.outline;
    final icon = tool?.icon(filled: true) ?? PhosphorIconsFill.hand;
    final cubit = context.read<ToolCubit>();
    return Tooltip(
      message: tool?.getDisplay(context) ?? '',
      triggerMode: TooltipTriggerMode.manual,
      child: Material(
        key: const ValueKey('amaze-tool-wheel-current'),
        color: style.surface,
        shape: CircleBorder(side: BorderSide(color: ring, width: 3)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: tool == null ? null : () => cubit.changeSelection(tool, true),
          onLongPress: onCollapse,
          child: SizedBox.square(
            dimension: 46,
            child: Center(child: PhosphorIcon(icon, color: style.onSurface)),
          ),
        ),
      ),
    );
  }

  Widget _buildHubButton({
    required Key key,
    required PhosphorIconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      color: style.onAccent,
      disabledColor: style.onAccent.withValues(alpha: 0.38),
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      icon: PhosphorIcon(icon),
    );
  }
}

class _WheelBackground extends StatelessWidget {
  const _WheelBackground({required this.style});

  final AmazeStyle style;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.surface,
        shape: BoxShape.circle,
        border: Border.all(color: style.outline),
        boxShadow: style.shadows,
      ),
      child: CustomPaint(painter: _MazeRingPainter(style.outline)),
    );
  }
}

/// Paints broken concentric rings, like the walls of a maze.
class _MazeRingPainter extends CustomPainter {
  const _MazeRingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final outer = Rect.fromCircle(center: center, radius: size.width / 2 - 5);
    final inner = Rect.fromCircle(center: center, radius: 64);
    for (var i = 0; i < kToolWheelSlots; i++) {
      final start = i * pi / 4 + pi / 8;
      canvas.drawArc(outer, start + 0.12, pi / 4 - 0.24, false, paint);
      if (i.isEven) canvas.drawArc(inner, start, pi / 4, false, paint);
    }
  }

  @override
  bool shouldRepaint(_MazeRingPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The collapsed tool wheel: a small handle that shows the current tool.
class ToolWheelPuck extends StatelessWidget {
  const ToolWheelPuck({super.key, this.onExpand, this.onDrag});

  final VoidCallback? onExpand;
  final ValueChanged<Offset>? onDrag;

  @override
  Widget build(BuildContext context) {
    final style = AmazeStyle.of(context);
    final drag = onDrag;
    return BlocBuilder<ToolCubit, ToolRuntimeState>(
      builder: (context, toolState) {
        final data = toolState.handler.data;
        final icon = data is Tool
            ? data.icon(filled: true)
            : PhosphorIconsFill.hand;
        return GestureDetector(
          key: const ValueKey('amaze-tool-wheel-puck'),
          onPanUpdate: drag == null ? null : (details) => drag(details.delta),
          child: Tooltip(
            message: AppLocalizations.of(context).toolWheel,
            child: Material(
              color: style.accent,
              shape: const CircleBorder(),
              elevation: 6,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onExpand,
                child: SizedBox.square(
                  dimension: kToolWheelPuckSize,
                  child: Center(
                    child: PhosphorIcon(icon, color: style.onAccent),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Places a [ToolWheel] in the available space and lets the user move,
/// collapse and expand it.
///
/// The position is kept as a fraction of the free space, so the wheel stays
/// in the same corner when the screen rotates.
class AmazeToolWheelLayer extends StatefulWidget {
  const AmazeToolWheelLayer({
    super.key,
    this.geometry = const ToolWheelGeometry(),
  });

  final ToolWheelGeometry geometry;

  @override
  State<AmazeToolWheelLayer> createState() => _AmazeToolWheelLayerState();
}

class _AmazeToolWheelLayerState extends State<AmazeToolWheelLayer> {
  Offset? _fraction;
  Size _bounds = Size.zero;
  bool _collapsed = false;
  int? _page;

  Size get _size {
    if (_collapsed) return const Size.square(kToolWheelPuckSize);
    return Size.square(widget.geometry.diameter);
  }

  Offset _defaultFraction(Size bounds) {
    final landscape = bounds.width >= bounds.height;
    return landscape ? const Offset(0.98, 0.96) : const Offset(0.5, 0.98);
  }

  Offset _positionFor(Offset fraction, Size bounds) {
    final size = _size;
    final freeX = bounds.width - size.width;
    final freeY = bounds.height - size.height;
    final position = Offset(freeX * fraction.dx, freeY * fraction.dy);
    return clampToolWheelPosition(position, size, bounds);
  }

  void _move(Offset delta) {
    final size = _size;
    final fraction = _fraction ?? _defaultFraction(_bounds);
    final moved = _positionFor(fraction, _bounds) + delta;
    final position = clampToolWheelPosition(moved, size, _bounds);
    final freeX = _bounds.width - size.width;
    final freeY = _bounds.height - size.height;
    setState(() {
      _fraction = Offset(
        freeX > 0 ? position.dx / freeX : 0,
        freeY > 0 ? position.dy / freeY : 0,
      );
    });
  }

  int _currentPage() {
    final page = _page;
    if (page != null) return page;
    final index = context.read<ToolCubit>().state.index;
    return toolWheelPageOf(index ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _bounds = constraints.biggest;
        final fraction = _fraction ?? _defaultFraction(_bounds);
        final position = _positionFor(fraction, _bounds);
        return Stack(
          children: [
            Positioned(
              left: position.dx,
              top: position.dy,
              child: _collapsed ? _buildPuck() : _buildWheel(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWheel() {
    return ToolWheel(
      geometry: widget.geometry,
      page: _currentPage(),
      onPageChanged: (page) => setState(() => _page = page),
      onCollapse: () => setState(() => _collapsed = true),
      onDrag: _move,
    );
  }

  Widget _buildPuck() {
    return ToolWheelPuck(
      onExpand: () => setState(() => _collapsed = false),
      onDrag: _move,
    );
  }
}
