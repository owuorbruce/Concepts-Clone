import 'dart:async';
import 'dart:math';

import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/helpers/color.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/visualizer/tool.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, RenderProxyBox;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'brush_library.dart';
import 'icons.dart';
import 'library.dart';
import 'slot_menu.dart';
import 'style.dart';
import 'tool_slots.dart';
import 'wheel_geometry.dart';
import 'wheel_prefs.dart';

export 'wheel_geometry.dart';

/// Diameter of the collapsed wheel.
const kToolWheelPuckSize = 64.0;

/// Height of the tool bar.
const kToolBarHeight = 64.0;

/// Keeps a box of [size] at [position] fully inside [bounds].
Offset clampToolWheelPosition(Offset position, Size size, Size bounds) {
  final maxX = max(0.0, bounds.width - size.width);
  final maxY = max(0.0, bounds.height - size.height);
  return Offset(position.dx.clamp(0.0, maxX), position.dy.clamp(0.0, maxY));
}

/// The tool the wheel controls: the selected document tool, or the current
/// handler's tool.
Tool? activeWheelTool(DocumentLoadSuccess state, ToolRuntimeState toolState) {
  final index = toolState.index;
  final tools = state.info.tools;
  if (index != null && index >= 0 && index < tools.length) return tools[index];
  final data = toolState.handler.data;
  return data is Tool ? data : null;
}

String _adjustmentName(AppLocalizations loc, ToolAdjustment adjustment) {
  return switch (adjustment) {
    ToolAdjustment.size => loc.size,
    ToolAdjustment.opacity => loc.opacity,
    ToolAdjustment.smoothing => loc.smoothing,
  };
}

AmazeIconData _adjustmentIcon(ToolAdjustment adjustment) {
  return switch (adjustment) {
    ToolAdjustment.size => AmazeIcons.size,
    ToolAdjustment.opacity => AmazeIcons.opacity,
    ToolAdjustment.smoothing => AmazeIcons.smoothing,
  };
}

Future<void> _onSlotTap(BuildContext context, int slot) async {
  final bloc = context.read<DocumentBloc>();
  final state = bloc.state;
  if (state is! DocumentLoadSuccess) return;
  final indices = slotToolIndices(state.info.tools);
  if (slot >= indices.length) return _assignSlot(context, slot);
  final controller = context.read<EditorController>();
  final cubit = controller.toolCubit;
  final index = indices[slot];
  final toolState = cubit.state;
  if (index != toolState.index || toolState.temporaryHandler != null) {
    cubit.resetSelection();
    await cubit.changeTool(controller, bloc, index: index, context: context);
    return;
  }
  cubit.changeSelection(state.info.tools[index], true);
}

/// Puts a tool chosen from the catalog into [slot].
Future<void> _assignSlot(BuildContext context, int slot) async {
  final picked = await showToolSlotCatalog(context);
  if (picked == null || !context.mounted) return;
  await _putToolInSlot(context, slot, picked);
}

/// Puts the tool of a brush library [entry] into [slot]. Unavailable
/// entries are ignored.
Future<void> _putLibraryEntryInSlot(
  BuildContext context,
  int slot,
  LibraryEntry entry,
) async {
  final name = entry.getLocalizedName(AppLocalizations.of(context));
  final tool = entry.createTool(name: name);
  if (tool == null) return;
  await _putToolInSlot(context, slot, tool);
}

/// Puts [tool] into [slot] and activates it. A replacement keeps the id of
/// the slot's tool, so its place on the wheel stays the same.
Future<void> _putToolInSlot(BuildContext context, int slot, Tool tool) async {
  final bloc = context.read<DocumentBloc>();
  final controller = context.read<EditorController>();
  final cubit = controller.toolCubit;
  final state = bloc.state;
  if (state is! DocumentLoadSuccess) return;
  final background = state.page.backgrounds.firstOrNull?.defaultColor;
  final colored = updateToolDefaultColor(tool, background ?? SRGBColor.white);
  final prepared = syncLibraryFill(colored);
  final tools = state.info.tools;
  final indices = slotToolIndices(tools);
  final Tool placed;
  final int index;
  if (slot < indices.length) {
    index = indices[slot];
    placed = prepared.copyWith(id: tools[index].id);
    bloc.add(ToolsChanged([placed]));
  } else {
    index = tools.length;
    placed = prepared.copyWith(id: createUniqueId());
    bloc.add(ToolCreated(placed));
  }
  if (placed.isAction()) return;
  cubit.resetSelection();
  await cubit.changeTool(
    controller,
    bloc,
    index: index,
    context: context,
    handler: Handler.fromTool(placed),
  );
}

/// Opens the menu of [slot]: settings, replace, move and remove.
Future<void> _openSlotMenu(BuildContext context, int slot) async {
  final bloc = context.read<DocumentBloc>();
  final cubit = context.read<ToolCubit>();
  final state = bloc.state;
  if (state is! DocumentLoadSuccess) return;
  final tools = state.info.tools;
  final indices = slotToolIndices(tools);
  if (slot >= indices.length) return _assignSlot(context, slot);
  final tool = tools[indices[slot]];
  final action = await showToolSlotMenu(
    context,
    tool: tool,
    slot: slot,
    filledSlots: indices.length,
  );
  if (action == null) return;
  if (!context.mounted) return;
  switch (action) {
    case ToolSlotAction.configure:
      cubit.changeSelection(tool, true);
    case ToolSlotAction.replace:
      await _assignSlot(context, slot);
    case ToolSlotAction.moveEarlier:
      _moveSlot(bloc, slot, slot - 1);
    case ToolSlotAction.moveLater:
      _moveSlot(bloc, slot, slot + 1);
    case ToolSlotAction.remove:
      final id = tool.id;
      if (id != null) bloc.add(ToolsRemoved([id]));
  }
}

void _moveSlot(DocumentBloc bloc, int from, int to) {
  final state = bloc.state;
  if (state is! DocumentLoadSuccess) return;
  final target = slotMoveTarget(state.info.tools, from, to);
  if (target == null) return;
  bloc.add(ToolReordered(target.$1, target.$2));
}

Future<void> _openColorPicker(BuildContext context) async {
  final bloc = context.read<DocumentBloc>();
  final settings = context.read<SettingsCubit>();
  final handler = context.read<ToolCubit>().state.handler;
  if (handler is! ColoredHandler) return;
  final response = await showDialog<ColorPickerResponse>(
    context: context,
    builder: (context) => ColorPicker(
      value: handler.getColor(),
      suggested: settings.state.recentColors,
    ),
  );
  if (response == null) return;
  final color = response.toSRGB();
  final tool = syncLibraryFill(handler.setColor(color));
  bloc.add(ToolsChanged([tool]));
  settings.addRecentColors(color);
}

void _applyAdjustment(
  BuildContext context,
  ToolAdjustment adjustment,
  double value,
) {
  final bloc = context.read<DocumentBloc>();
  final state = bloc.state;
  if (state is! DocumentLoadSuccess) return;
  final tool = activeWheelTool(state, context.read<ToolCubit>().state);
  if (tool == null || tool.readAdjustment(adjustment) == null) return;
  bloc.add(ToolsChanged([tool.writeAdjustment(adjustment, value)]));
}

/// Document and tool state shared by the wheel and the bar.
class _ToolControls {
  _ToolControls(this.state, this.toolState);

  final DocumentLoadSuccess state;
  final ToolRuntimeState toolState;

  List<Tool> get tools => state.info.tools;

  late final List<int> slots = slotToolIndices(tools);

  late final Tool? active = activeWheelTool(state, toolState);

  /// Color of the active tool, or null if it has none.
  Color? get color {
    final handler = toolState.handler;
    if (handler is! ColoredHandler) return null;
    return handler.getColor().toColor();
  }

  List<ToolAdjustment> get adjustments => active?.adjustments ?? const [];
}

class _ToolControlsBuilder extends StatelessWidget {
  const _ToolControlsBuilder({required this.builder});

  final Widget Function(BuildContext context, _ToolControls controls) builder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentBloc, DocumentState>(
      builder: (context, state) {
        if (state is! DocumentLoadSuccess) return const SizedBox.shrink();
        return BlocBuilder<ToolCubit, ToolRuntimeState>(
          builder: (context, toolState) {
            return builder(context, _ToolControls(state, toolState));
          },
        );
      },
    );
  }
}

class _SlotButton extends StatelessWidget {
  const _SlotButton({
    required this.slot,
    required this.controls,
    required this.style,
    required this.size,
    this.onOpenLibrary,
  });

  final int slot;
  final _ToolControls controls;
  final AmazeStyle style;
  final double size;

  /// Opens the brush library for a slot. Without it, long press opens the
  /// slot menu and an empty slot opens the tool catalog.
  final ValueChanged<int>? onOpenLibrary;

  void _onLongPress(BuildContext context) {
    final open = onOpenLibrary;
    if (open != null) return open(slot);
    _openSlotMenu(context, slot);
  }

  void _onEmptyTap(BuildContext context) {
    final open = onOpenLibrary;
    if (open != null) return open(slot);
    _assignSlot(context, slot);
  }

  @override
  Widget build(BuildContext context) {
    final slots = controls.slots;
    if (slot >= slots.length) return _buildEmpty(context);
    final index = slots[slot];
    final tool = controls.tools[index];
    final toolState = controls.toolState;
    final toggled = toolState.toggleableHandlers.containsKey(index);
    final selected = index == toolState.index || toggled;
    final foreground = selected ? style.onAccent : style.onSurface;
    // Long press opens the library, so the tooltip only shows on hover.
    return Tooltip(
      message: tool.getDisplay(context),
      triggerMode: TooltipTriggerMode.manual,
      child: SizedBox.square(
        dimension: size,
        child: Material(
          key: ValueKey(('amaze-slot', slot)),
          color: selected ? style.accent : style.surfaceVariant,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _onSlotTap(context, slot),
            onLongPress: () => _onLongPress(context),
            child: Center(
              child: AmazeIcon(
                amazeToolIcon(tool),
                filled: selected,
                size: size * 0.52,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final border = BorderSide(color: style.outline, width: 1.5);
    return Tooltip(
      message: AppLocalizations.of(context).emptySlot,
      triggerMode: TooltipTriggerMode.manual,
      child: SizedBox.square(
        dimension: size,
        child: Material(
          key: ValueKey(('amaze-slot', slot)),
          color: Colors.transparent,
          shape: CircleBorder(side: border),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _onEmptyTap(context),
            onLongPress: () => _onEmptyTap(context),
            child: Center(
              child: PhosphorIcon(
                PhosphorIconsLight.plus,
                size: 18,
                color: style.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton({
    required this.redo,
    required this.style,
    required this.size,
  });

  final bool redo;
  final AmazeStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<DocumentBloc>();
    final loc = AppLocalizations.of(context);
    final enabled = redo ? bloc.canSendRedo : bloc.canSendUndo;
    return IconButton(
      key: ValueKey(redo ? 'amaze-redo' : 'amaze-undo'),
      tooltip: redo ? loc.redo : loc.undo,
      onPressed: enabled ? (redo ? bloc.sendRedo : bloc.sendUndo) : null,
      style: IconButton.styleFrom(
        backgroundColor: style.surfaceVariant,
        foregroundColor: style.onSurface,
        disabledForegroundColor: style.muted,
        disabledBackgroundColor: style.surfaceVariant,
        fixedSize: Size.square(size),
        minimumSize: Size.square(size),
        padding: EdgeInsets.zero,
      ),
      iconSize: 20,
      icon: AmazeIcon(redo ? AmazeIcons.redo : AmazeIcons.undo, size: 20),
    );
  }
}

class _AdjustmentButton extends StatelessWidget {
  const _AdjustmentButton({
    required this.adjustment,
    required this.controls,
    required this.style,
    required this.open,
    required this.size,
    this.onTap,
  });

  final ToolAdjustment adjustment;
  final _ToolControls controls;
  final AmazeStyle style;
  final bool open;
  final Size size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final value = controls.active?.readAdjustment(adjustment);
    if (value == null) return SizedBox.fromSize(size: size);
    final loc = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final color = open ? style.onAccent : style.onSurface;
    return Tooltip(
      message: _adjustmentName(loc, adjustment),
      child: SizedBox.fromSize(
        size: size,
        child: Material(
          key: ValueKey(('amaze-adjust', adjustment.name)),
          color: open ? style.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            // Shrinks the content only when a small wheel's button is too
            // short for it.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: .min,
                children: [
                  AmazeIcon(
                    _adjustmentIcon(adjustment),
                    size: 18,
                    color: color,
                  ),
                  Text(
                    formatAdjustment(adjustment, value),
                    style: textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.controls,
    required this.style,
    required this.diameter,
    this.onLongPress,
  });

  final _ToolControls controls;
  final AmazeStyle style;
  final double diameter;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = controls.color;
    final tool = controls.active;
    final loc = AppLocalizations.of(context);
    final Widget content;
    if (color != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: style.surface, width: 3),
        ),
      );
    } else {
      content = Center(
        child: AmazeIcon(
          tool == null ? LibraryEntry.pan.icon : amazeToolIcon(tool),
          filled: true,
          color: style.muted,
        ),
      );
    }
    final name = tool?.getDisplay(context) ?? '';
    return Tooltip(
      message: color == null ? name : loc.toolColor,
      triggerMode: TooltipTriggerMode.manual,
      child: SizedBox.square(
        dimension: diameter,
        child: Material(
          key: const ValueKey('amaze-color'),
          color: style.surfaceVariant,
          shape: CircleBorder(side: BorderSide(color: style.outline)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: color == null ? null : () => _openColorPicker(context),
            onLongPress: onLongPress,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// The three-ring tool wheel.
///
/// The outer ring holds eight tool slots plus undo and redo, the middle
/// ring the size, opacity and smoothing of the active tool, and the center
/// its color. Long-pressing the ring outside the buttons and dragging moves
/// the wheel through the ring callbacks.
class ToolWheel extends StatelessWidget {
  const ToolWheel({
    super.key,
    this.geometry = const ToolWheelGeometry(),
    this.openAdjustment,
    this.onAdjustmentTap,
    this.onCollapse,
    this.onRingLongPressStart,
    this.onRingLongPressMove,
    this.onRingLongPressEnd,
    this.onOpenLibrary,
  });

  final ToolWheelGeometry geometry;
  final ToolAdjustment? openAdjustment;
  final ValueChanged<ToolAdjustment>? onAdjustmentTap;
  final VoidCallback? onCollapse;
  final GestureLongPressStartCallback? onRingLongPressStart;
  final GestureLongPressMoveUpdateCallback? onRingLongPressMove;
  final GestureLongPressEndCallback? onRingLongPressEnd;
  final ValueChanged<int>? onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return _ToolControlsBuilder(builder: _buildWheel);
  }

  Widget _buildWheel(BuildContext context, _ToolControls controls) {
    final style = AmazeStyle.of(context);
    final center = Offset(geometry.radius, geometry.radius);
    final supported = controls.adjustments.toSet();

    /// Places [child] centered at [offset] from the wheel's center. It only
    /// receives pointers inside the visible region of [hit].
    Widget place(Offset offset, Size size, WheelHit hit, Widget child) {
      final topLeft = center + offset - size.center(Offset.zero);
      return Positioned(
        left: topLeft.dx,
        top: topLeft.dy,
        width: size.width,
        height: size.height,
        child: _WheelHitRegion(
          geometry: geometry,
          hit: hit,
          origin: topLeft - center,
          child: child,
        ),
      );
    }

    final slotSize = Size.square(geometry.slotSize);
    final historySize = Size.square(geometry.historySize);
    return SizedBox.square(
      key: const ValueKey('amaze-tool-wheel'),
      dimension: geometry.diameter,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipOval(
              child: GestureDetector(
                key: const ValueKey('amaze-wheel-ring'),
                behavior: HitTestBehavior.opaque,
                onLongPressStart: onRingLongPressStart,
                onLongPressMoveUpdate: onRingLongPressMove,
                onLongPressEnd: onRingLongPressEnd,
                child: CustomPaint(
                  painter: _WheelPainter(
                    style: style,
                    geometry: geometry,
                    supported: supported,
                    open: openAdjustment,
                  ),
                ),
              ),
            ),
          ),
          // A supported adjustment can be tapped anywhere on its segment.
          // Unsupported ones are left to the ring, so they do nothing.
          for (final adjustment in ToolAdjustment.values)
            if (supported.contains(adjustment))
              Positioned.fill(
                child: _WheelHitRegion(
                  geometry: geometry,
                  hit: WheelHit.adjustment(adjustment),
                  origin: -center,
                  child: GestureDetector(
                    key: ValueKey(('amaze-adjust-sector', adjustment.name)),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onAdjustmentTap?.call(adjustment),
                  ),
                ),
              ),
          for (var slot = 0; slot < kToolSlotCount; slot++)
            place(
              geometry.slotCenter(slot),
              slotSize,
              WheelHit.slot(slot),
              _SlotButton(
                slot: slot,
                controls: controls,
                style: style,
                size: geometry.slotSize,
                onOpenLibrary: onOpenLibrary,
              ),
            ),
          place(
            geometry.undoCenter,
            historySize,
            WheelHit.undo,
            _HistoryButton(
              redo: false,
              style: style,
              size: geometry.historySize,
            ),
          ),
          place(
            geometry.redoCenter,
            historySize,
            WheelHit.redo,
            _HistoryButton(
              redo: true,
              style: style,
              size: geometry.historySize,
            ),
          ),
          for (final adjustment in ToolAdjustment.values)
            place(
              geometry.adjustmentCenter(adjustment),
              geometry.adjustmentSize,
              WheelHit.adjustment(adjustment),
              _AdjustmentButton(
                adjustment: adjustment,
                controls: controls,
                style: style,
                open: openAdjustment == adjustment,
                size: geometry.adjustmentSize,
                onTap: () => onAdjustmentTap?.call(adjustment),
              ),
            ),
          place(
            Offset.zero,
            Size.square(geometry.centerRadius * 2),
            WheelHit.center,
            _ColorButton(
              controls: controls,
              style: style,
              diameter: geometry.centerRadius * 2,
              onLongPress: onCollapse,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets [child] receive pointers only inside the visible region of [hit],
/// as defined by [ToolWheelGeometry.controlContains]. [origin] is the
/// child's top left corner relative to the wheel's center.
class _WheelHitRegion extends SingleChildRenderObjectWidget {
  const _WheelHitRegion({
    required this.geometry,
    required this.hit,
    required this.origin,
    super.child,
  });

  final ToolWheelGeometry geometry;
  final WheelHit hit;
  final Offset origin;

  bool _contains(Offset position) {
    return geometry.controlContains(hit, position + origin);
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderWheelHitRegion(_contains);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWheelHitRegion renderObject,
  ) {
    renderObject.contains = _contains;
  }
}

class _RenderWheelHitRegion extends RenderProxyBox {
  _RenderWheelHitRegion(this.contains);

  bool Function(Offset position) contains;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!contains(position)) return false;
    return super.hitTest(result, position: position);
  }
}

/// Paints the wheel: the outer disc with a broken maze rim, and the middle
/// ring split into one segment per adjustment.
class _WheelPainter extends CustomPainter {
  const _WheelPainter({
    required this.style,
    required this.geometry,
    required this.supported,
    required this.open,
  });

  final AmazeStyle style;
  final ToolWheelGeometry geometry;
  final Set<ToolAdjustment> supported;
  final ToolAdjustment? open;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = Rect.fromCircle(center: center, radius: geometry.radius);
    canvas.drawOval(outer, Paint()..color = style.surface);
    canvas.drawOval(
      outer.deflate(0.5),
      Paint()
        ..color = style.outline
        ..style = PaintingStyle.stroke,
    );
    final rim = Paint()
      ..color = style.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rimRect = outer.deflate(5);
    for (var i = 0; i < 10; i++) {
      final start = geometry.ringAngle(i) + pi / 10;
      canvas.drawArc(rimRect, start + 0.1, pi / 5 - 0.2, false, rim);
    }
    // Each segment is drawn as a butt-capped stroke that fills exactly the
    // sector used for hit testing.
    for (final adjustment in ToolAdjustment.values) {
      final active = supported.contains(adjustment);
      final color = adjustment == open
          ? style.accent.withValues(alpha: 0.25)
          : style.surfaceVariant.withValues(alpha: active ? 1 : 0.4);
      final sector = geometry.adjustmentSector(adjustment);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: sector.middleRadius),
        sector.startAngle,
        sector.sweepAngle,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.butt
          ..strokeWidth = sector.width,
      );
    }
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) {
    return oldDelegate.geometry.diameter != geometry.diameter ||
        oldDelegate.style.accent != style.accent ||
        oldDelegate.style.surface != style.surface ||
        oldDelegate.open != open ||
        oldDelegate.supported.length != supported.length ||
        !oldDelegate.supported.containsAll(supported);
  }
}

/// The tool controls as a straight bar: the same slots, undo and redo,
/// adjustments and color as the wheel.
class AmazeToolBar extends StatelessWidget {
  const AmazeToolBar({
    super.key,
    required this.onShowWheel,
    this.openAdjustment,
    this.onAdjustmentTap,
    this.onOpenLibrary,
  });

  final VoidCallback onShowWheel;
  final ToolAdjustment? openAdjustment;
  final ValueChanged<ToolAdjustment>? onAdjustmentTap;
  final ValueChanged<int>? onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return _ToolControlsBuilder(builder: _buildBar);
  }

  Widget _buildBar(BuildContext context, _ToolControls controls) {
    final style = AmazeStyle.of(context);
    final loc = AppLocalizations.of(context);
    final adjustments = controls.adjustments;
    const divider = SizedBox(height: 32, child: VerticalDivider(width: 8));
    return Padding(
      key: const ValueKey('amaze-tool-bar'),
      padding: const EdgeInsets.all(8),
      child: AmazeSurface(
        radius: 32,
        child: SizedBox(
          height: kToolBarHeight,
          child: SingleChildScrollView(
            scrollDirection: .horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              spacing: 3,
              children: [
                IconButton(
                  key: const ValueKey('amaze-bar-show-wheel'),
                  tooltip: loc.showToolWheel,
                  onPressed: onShowWheel,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const PhosphorIcon(PhosphorIconsLight.circle),
                ),
                divider,
                for (var slot = 0; slot < kToolSlotCount; slot++)
                  _SlotButton(
                    slot: slot,
                    controls: controls,
                    style: style,
                    size: 40,
                    onOpenLibrary: onOpenLibrary,
                  ),
                divider,
                _HistoryButton(redo: false, style: style, size: 38),
                _HistoryButton(redo: true, style: style, size: 38),
                if (adjustments.isNotEmpty) divider,
                for (final adjustment in adjustments)
                  _AdjustmentButton(
                    adjustment: adjustment,
                    controls: controls,
                    style: style,
                    open: openAdjustment == adjustment,
                    size: const Size(52, 46),
                    onTap: () => onAdjustmentTap?.call(adjustment),
                  ),
                if (controls.color != null) ...[
                  divider,
                  _ColorButton(controls: controls, style: style, diameter: 38),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slider for one adjustment of the active tool. The tool is updated when
/// the slider is released, so a drag is one undo step.
class _AdjustmentPanel extends StatefulWidget {
  const _AdjustmentPanel({required this.adjustment, required this.onClose});

  final ToolAdjustment adjustment;
  final VoidCallback onClose;

  @override
  State<_AdjustmentPanel> createState() => _AdjustmentPanelState();
}

class _AdjustmentPanelState extends State<_AdjustmentPanel> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return _ToolControlsBuilder(builder: _buildPanel);
  }

  Widget _buildPanel(BuildContext context, _ToolControls controls) {
    final adjustment = widget.adjustment;
    final tool = controls.active;
    final value = tool?.readAdjustment(adjustment);
    if (tool == null || value == null) return const SizedBox.shrink();
    final range = tool.adjustmentRange(adjustment);
    final shown = range.clamp(_dragValue ?? value);
    final loc = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return AmazeSurface(
      key: const ValueKey('amaze-adjustment-panel'),
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          mainAxisSize: .min,
          children: [
            Row(
              children: [
                AmazeIcon(_adjustmentIcon(adjustment), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _adjustmentName(loc, adjustment),
                    style: textTheme.titleSmall,
                  ),
                ),
                Text(
                  formatAdjustment(adjustment, shown),
                  key: const ValueKey('amaze-adjustment-value'),
                  style: textTheme.titleMedium,
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: widget.onClose,
                  icon: const PhosphorIcon(PhosphorIconsLight.x),
                ),
              ],
            ),
            Slider(
              key: const ValueKey('amaze-adjustment-slider'),
              value: shown,
              min: range.min,
              max: range.max,
              onChanged: (next) => setState(() => _dragValue = next),
              onChangeEnd: (next) {
                setState(() => _dragValue = null);
                _applyAdjustment(context, adjustment, next);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The collapsed tool wheel: a small handle that shows the active color or
/// tool.
class ToolWheelPuck extends StatelessWidget {
  const ToolWheelPuck({super.key, this.onExpand, this.onDrag});

  final VoidCallback? onExpand;
  final ValueChanged<Offset>? onDrag;

  @override
  Widget build(BuildContext context) {
    final style = AmazeStyle.of(context);
    final drag = onDrag;
    return _ToolControlsBuilder(
      builder: (context, controls) {
        final color = controls.color;
        final tool = controls.active;
        final Widget content;
        if (color == null) {
          content = AmazeIcon(
            tool == null ? LibraryEntry.pan.icon : amazeToolIcon(tool),
            filled: true,
            color: style.onAccent,
          );
        } else {
          content = DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: style.onAccent),
            ),
            child: const SizedBox.square(dimension: 28),
          );
        }
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
                  child: Center(child: content),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Recognizes a pinch that starts on the wheel: two touch pointers, or a
/// trackpad pinch. A single touch is never claimed, so taps and long presses
/// on the wheel keep working, and a stylus is not supported at all.
class _WheelPinchRecognizer extends OneSequenceGestureRecognizer {
  _WheelPinchRecognizer({super.debugOwner})
    : super(
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.trackpad,
        },
      );

  VoidCallback? onStart;

  /// Called with the scale since the pinch started.
  ValueChanged<double>? onUpdate;

  /// Called when the pinch ends or is cancelled.
  VoidCallback? onEnd;

  final Map<int, Offset> _touches = {};
  double? _startDistance;
  bool _pinching = false;

  double get _distance {
    final points = _touches.values.toList();
    return (points[0] - points[1]).distance;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_touches.length >= 2) return;
    startTrackingPointer(event.pointer, event.transform);
    _touches[event.pointer] = event.position;
    if (_touches.length < 2 || _pinching) return;
    resolve(GestureDisposition.accepted);
    _startDistance = max(_distance, 1.0);
    _begin();
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    if (_touches.isNotEmpty) return;
    startTrackingPointer(event.pointer, event.transform);
  }

  void _begin() {
    _pinching = true;
    onStart?.call();
  }

  void _finish() {
    if (_pinching) onEnd?.call();
    _pinching = false;
    _startDistance = null;
  }

  @override
  void handleEvent(PointerEvent event) {
    final start = _startDistance;
    if (event is PointerMoveEvent && _touches.containsKey(event.pointer)) {
      _touches[event.pointer] = event.position;
      if (_pinching && start != null && _touches.length == 2) {
        onUpdate?.call(_distance / start);
      }
    } else if (event is PointerPanZoomUpdateEvent) {
      // A two-finger trackpad scroll keeps a scale of 1 and is ignored.
      if (!_pinching && (event.scale - 1).abs() > 0.01) {
        resolve(GestureDisposition.accepted);
        _begin();
      }
      if (_pinching) onUpdate?.call(event.scale);
    } else if (event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerPanZoomEndEvent) {
      _touches.remove(event.pointer);
      _finish();
    }
    stopTrackingIfPointerNoLongerDown(event);
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    // Another gesture, like a long press, owns this pointer.
    if (_pinching) return;
    _touches.remove(pointer);
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _finish();
    _touches.clear();
  }

  @override
  String get debugDescription => 'tool wheel pinch';
}

/// Places the tool wheel or the tool bar in the available space.
///
/// Long-press the wheel's ring and drag to move it; dropping it on the dock
/// target turns it into a tool bar. Pinch the wheel, or use Ctrl and the
/// mouse wheel over it, to resize it. The mode, position (as a fraction of
/// the free space, so it survives rotation), size and collapse state are
/// saved.
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
  ToolWheelLayout _layout = const ToolWheelLayout();
  Size _bounds = Size.zero;
  bool _dragging = false;
  bool _overDock = false;
  Offset? _lastPointer;
  ToolAdjustment? _openAdjustment;

  /// The slot the brush library is open for, if it is open.
  int? _librarySlot;

  /// Diameter when the current pinch started.
  double? _pinchStart;

  /// Saves the size shortly after the last Ctrl + scroll step.
  Timer? _scrollSave;

  @override
  void initState() {
    super.initState();
    loadToolWheelLayout().then((layout) {
      if (mounted) setState(() => _layout = layout);
    });
  }

  @override
  void dispose() {
    if (_scrollSave?.isActive ?? false) saveToolWheelLayout(_layout);
    _scrollSave?.cancel();
    super.dispose();
  }

  void _update(ToolWheelLayout layout) {
    setState(() => _layout = layout);
    saveToolWheelLayout(layout);
  }

  /// The diameter the wheel is shown at for a [requested] one: within the
  /// supported range and the layer, but never below the minimum.
  double _fitDiameter(double requested) {
    final fit = _bounds.shortestSide - 16;
    final clamped = clampToolWheelDiameter(requested);
    return max(kToolWheelMinDiameter, min(clamped, fit));
  }

  double get _diameter {
    return _fitDiameter(_layout.diameter ?? widget.geometry.diameter);
  }

  ToolWheelGeometry get _geometry => ToolWheelGeometry(diameter: _diameter);

  Size get _wheelSize {
    if (_layout.collapsed) return const Size.square(kToolWheelPuckSize);
    return Size.square(_diameter);
  }

  Offset get _fraction {
    final saved = _layout.position;
    if (saved != null) return saved;
    final landscape = _bounds.width >= _bounds.height;
    return landscape ? const Offset(0.98, 0.96) : const Offset(0.5, 0.98);
  }

  Offset get _position {
    final size = _wheelSize;
    final freeX = _bounds.width - size.width;
    final freeY = _bounds.height - size.height;
    final position = Offset(freeX * _fraction.dx, freeY * _fraction.dy);
    return clampToolWheelPosition(position, size, _bounds);
  }

  Rect get _dockRect {
    final center = Offset(_bounds.width / 2, _bounds.height - 44);
    return Rect.fromCenter(center: center, width: 280, height: 72);
  }

  Offset _toLocal(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return global;
    return box.globalToLocal(global);
  }

  /// Converts a top left [position] of a box of [size] into a fraction of
  /// the free space.
  Offset _fractionOf(Offset position, Size size) {
    final freeX = _bounds.width - size.width;
    final freeY = _bounds.height - size.height;
    return Offset(
      freeX > 0 ? position.dx / freeX : 0,
      freeY > 0 ? position.dy / freeY : 0,
    );
  }

  void _move(Offset delta, {bool overDock = false}) {
    final size = _wheelSize;
    final moved = _position + delta;
    final position = clampToolWheelPosition(moved, size, _bounds);
    setState(() {
      _layout = _layout.copyWith(position: _fractionOf(position, size));
      _overDock = overDock;
    });
  }

  /// Resizes the expanded wheel around its center, keeping it on screen.
  /// The new size is saved by the caller when the gesture ends.
  void _resize(double requested) {
    if (_layout.collapsed || _layout.mode != ToolWheelMode.wheel) return;
    final center = (_position & _wheelSize).center;
    final diameter = _fitDiameter(requested);
    if (diameter == _diameter) return;
    final size = Size.square(diameter);
    final topLeft = center - size.center(Offset.zero);
    final position = clampToolWheelPosition(topLeft, size, _bounds);
    setState(() {
      _layout = _layout.copyWith(
        diameter: diameter,
        position: _fractionOf(position, size),
      );
    });
  }

  void _onPinchStart() => _pinchStart = _diameter;

  void _onPinchUpdate(double scale) {
    final start = _pinchStart;
    if (start != null) _resize(start * scale);
  }

  /// Also called when the pinch is cancelled: the last size stays.
  void _onPinchEnd() {
    _pinchStart = null;
    saveToolWheelLayout(_layout);
  }

  /// Ctrl + mouse wheel resizes the wheel by one step per notch. A plain
  /// scroll is left alone.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!HardwareKeyboard.instance.isControlPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0) return;
      _resize(_diameter + (dy < 0 ? _scrollStep : -_scrollStep));
      _scrollSave?.cancel();
      _scrollSave = Timer(_scrollSaveDelay, () {
        if (mounted) saveToolWheelLayout(_layout);
      });
    });
  }

  static const _scrollStep = 16.0;
  static const _scrollSaveDelay = Duration(milliseconds: 300);

  void _onRingPressStart(LongPressStartDetails details) {
    setState(() {
      _dragging = true;
      _overDock = false;
      _openAdjustment = null;
      _lastPointer = details.globalPosition;
    });
  }

  void _onRingPressMove(LongPressMoveUpdateDetails details) {
    final pointer = details.globalPosition;
    final last = _lastPointer ?? pointer;
    _lastPointer = pointer;
    _move(pointer - last, overDock: _dockRect.contains(_toLocal(pointer)));
  }

  void _onRingPressEnd(LongPressEndDetails details) {
    final dock = _overDock;
    setState(() {
      _dragging = false;
      _overDock = false;
      _lastPointer = null;
    });
    if (dock) {
      _update(_layout.copyWith(mode: ToolWheelMode.bar));
    } else {
      saveToolWheelLayout(_layout);
    }
  }

  void _toggleAdjustment(ToolAdjustment adjustment) {
    setState(() {
      _openAdjustment = _openAdjustment == adjustment ? null : adjustment;
    });
  }

  void _closeAdjustment() => setState(() => _openAdjustment = null);

  void _showWheel() {
    _update(_layout.copyWith(mode: ToolWheelMode.wheel, collapsed: false));
  }

  void _openLibrary(int slot) {
    setState(() {
      _librarySlot = slot;
      _openAdjustment = null;
    });
  }

  void _closeLibrary() => setState(() => _librarySlot = null);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = _librarySlot;
        return Stack(
          children: [
            Positioned.fill(
              key: const ValueKey('amaze-instrument-layer'),
              child: Theme(
                data: AmazeStyle.instrumentTheme(context),
                child: LayoutBuilder(builder: _buildLayout),
              ),
            ),
            if (slot != null) _buildLibrary(context, constraints, slot),
          ],
        );
      },
    );
  }

  Widget _buildLibrary(
    BuildContext context,
    BoxConstraints constraints,
    int slot,
  ) {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: min(kBrushLibraryWidth, constraints.maxWidth),
      child: BrushLibrarySidebar(
        key: const ValueKey('amaze-brush-library-sidebar'),
        slot: slot,
        onClose: _closeLibrary,
        onSelect: (entry) => _putLibraryEntryInSlot(context, slot, entry),
        onSlotOptions: () => _openSlotMenu(context, slot),
      ),
    );
  }

  Widget _buildLayout(BuildContext context, BoxConstraints constraints) {
    _bounds = constraints.biggest;
    final children = _layout.mode == ToolWheelMode.bar
        ? _buildBar(context)
        : _buildWheel(context);
    return Stack(children: children);
  }

  List<Widget> _buildWheel(BuildContext context) {
    final position = _position;
    // Keys keep the wheel's gesture state when the dock target appears.
    final children = <Widget>[];
    if (_layout.collapsed) {
      children.add(
        Positioned(
          key: const ValueKey('amaze-wheel-position'),
          left: position.dx,
          top: position.dy,
          child: ToolWheelPuck(
            onExpand: () => _update(_layout.copyWith(collapsed: false)),
            onDrag: _move,
          ),
        ),
      );
      return children;
    }
    children.add(
      Positioned(
        key: const ValueKey('amaze-wheel-position'),
        left: position.dx,
        top: position.dy,
        child: Listener(
          onPointerSignal: _onPointerSignal,
          child: RawGestureDetector(
            gestures: {
              _WheelPinchRecognizer:
                  GestureRecognizerFactoryWithHandlers<_WheelPinchRecognizer>(
                    () => _WheelPinchRecognizer(debugOwner: this),
                    (recognizer) => recognizer
                      ..onStart = _onPinchStart
                      ..onUpdate = _onPinchUpdate
                      ..onEnd = _onPinchEnd,
                  ),
            },
            child: ToolWheel(
              geometry: _geometry,
              openAdjustment: _openAdjustment,
              onAdjustmentTap: _toggleAdjustment,
              onCollapse: () => _update(_layout.copyWith(collapsed: true)),
              onRingLongPressStart: _onRingPressStart,
              onRingLongPressMove: _onRingPressMove,
              onRingLongPressEnd: _onRingPressEnd,
              onOpenLibrary: _openLibrary,
            ),
          ),
        ),
      ),
    );
    final adjustment = _openAdjustment;
    if (adjustment != null) {
      final anchor = position & _wheelSize;
      children.add(_buildPanel(adjustment, anchor));
    }
    if (_dragging) children.add(_buildDockTarget(context));
    return children;
  }

  List<Widget> _buildBar(BuildContext context) {
    final adjustment = _openAdjustment;
    return [
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Center(
          child: AmazeToolBar(
            openAdjustment: _openAdjustment,
            onAdjustmentTap: _toggleAdjustment,
            onShowWheel: _showWheel,
            onOpenLibrary: _openLibrary,
          ),
        ),
      ),
      if (adjustment != null)
        _buildPanel(
          adjustment,
          Rect.fromLTWH(0, _bounds.height - kToolBarHeight - 16, 0, 0),
          centered: true,
        ),
    ];
  }

  Widget _buildPanel(
    ToolAdjustment adjustment,
    Rect anchor, {
    bool centered = false,
  }) {
    const width = 300.0;
    const height = 120.0;
    final centerX = centered ? _bounds.width / 2 : anchor.center.dx;
    final maxLeft = max(0.0, _bounds.width - width);
    final left = (centerX - width / 2).clamp(0.0, maxLeft);
    var top = anchor.top - height - 8;
    if (top < 0) top = min(anchor.bottom + 8, _bounds.height - height);
    return Positioned(
      left: left,
      top: max(0.0, top),
      width: width,
      child: _AdjustmentPanel(
        adjustment: adjustment,
        onClose: _closeAdjustment,
      ),
    );
  }

  Widget _buildDockTarget(BuildContext context) {
    final rect = _dockRect;
    final style = AmazeStyle.of(context);
    final active = _overDock;
    final color = active ? style.onAccent : style.onSurface;
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: AnimatedContainer(
          key: const ValueKey('amaze-dock-target'),
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: active ? style.accent : style.surface,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: style.accent, width: 2),
            boxShadow: style.shadows,
          ),
          child: Row(
            mainAxisAlignment: .center,
            spacing: 8,
            children: [
              PhosphorIcon(PhosphorIconsLight.toolbox, color: color),
              Text(
                AppLocalizations.of(context).dropForToolbar,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
