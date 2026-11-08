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
import 'package:flutter/services.dart'
    show HapticFeedback, HardwareKeyboard, LogicalKeyboardKey;
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
import 'wheel_presets.dart';
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

/// Sets [adjustment] of the active tool to [value] with one [ToolsChanged],
/// which is one undo step.
///
/// The wheel's size, opacity, smoothing and color always change the active
/// tool only. They never change selected elements, even while a selection
/// is active. If the active tool does not support [adjustment], nothing is
/// dispatched.
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

/// [_applyAdjustment] for tests.
@visibleForTesting
void applyWheelAdjustment(
  BuildContext context,
  ToolAdjustment adjustment,
  double value,
) => _applyAdjustment(context, adjustment, value);

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
    this.background,
  });

  final bool redo;
  final AmazeStyle style;
  final double size;

  /// Button color; the style's surface variant by default.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<DocumentBloc>();
    final loc = AppLocalizations.of(context);
    final enabled = redo ? bloc.canSendRedo : bloc.canSendUndo;
    final color = background ?? style.surfaceVariant;
    final iconSize = min(20.0, size * 0.55);
    final message = redo ? loc.redo : loc.undo;
    // On the wheel a long press belongs to the wheel, so the tooltip must
    // not claim it.
    final onWheel = background != null;
    final button = IconButton(
      key: ValueKey(redo ? 'amaze-redo' : 'amaze-undo'),
      tooltip: onWheel ? null : message,
      onPressed: enabled ? (redo ? bloc.sendRedo : bloc.sendUndo) : null,
      style: IconButton.styleFrom(
        backgroundColor: color,
        foregroundColor: style.onSurface,
        disabledForegroundColor: style.muted,
        disabledBackgroundColor: color,
        fixedSize: Size.square(size),
        minimumSize: Size.square(size),
        padding: EdgeInsets.zero,
        side: background == null ? null : BorderSide(color: style.outline),
      ),
      iconSize: iconSize,
      icon: AmazeIcon(redo ? AmazeIcons.redo : AmazeIcons.undo, size: iconSize),
    );
    if (!onWheel) return button;
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.manual,
      child: button,
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
  });

  final _ToolControls controls;
  final AmazeStyle style;
  final double diameter;

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
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Places [child] with its center at [offset] from the wheel's center
/// [origin]. It only receives pointers inside the region of [hit], if given.
Widget _placeOnWheel(
  ToolWheelGeometry geometry,
  Offset offset,
  Size size,
  Widget child, {
  WheelHit? hit,
}) {
  final center = Offset(geometry.radius, geometry.radius);
  final topLeft = center + offset - size.center(Offset.zero);
  return Positioned(
    left: topLeft.dx,
    top: topLeft.dy,
    width: size.width,
    height: size.height,
    child: hit == null
        ? child
        : _WheelHitRegion(
            geometry: geometry,
            hit: hit,
            origin: topLeft - center,
            child: child,
          ),
  );
}

/// Covers the whole wheel and only receives pointers inside [hit].
Widget _wheelRegion(ToolWheelGeometry geometry, WheelHit hit, Widget child) {
  return Positioned.fill(
    child: _WheelHitRegion(
      geometry: geometry,
      hit: hit,
      origin: Offset(-geometry.radius, -geometry.radius),
      child: child,
    ),
  );
}

/// Formats a tool size for the wheel: a whole number when the value is
/// whole, one decimal otherwise.
String _formatSize(double size) {
  final fixed = size.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

/// The size of [tool] as shown on its wedge, or null if it has none.
String? _toolSizeLabel(Tool tool) {
  final size = tool.readAdjustment(ToolAdjustment.size);
  if (size == null) return null;
  return _formatSize(size);
}

/// The value of [adjustment] as shown in the center disc.
String _discLabel(
  AppLocalizations loc,
  ToolAdjustment adjustment,
  double value,
) {
  if (adjustment == ToolAdjustment.size) {
    return loc.amazeSizePts(_formatSize(value));
  }
  return formatAdjustment(adjustment, value);
}

/// One slot wedge of the wheel: its surface, the tool icon and the tool's
/// size. The whole wedge is the slot's button. Its long press is handled by
/// the wheel, see [ToolWheel.onHoldStart].
class _WedgeSlot extends StatelessWidget {
  const _WedgeSlot({
    required this.slot,
    required this.controls,
    required this.style,
    required this.geometry,
    this.onOpenLibrary,
  });

  final int slot;
  final _ToolControls controls;
  final AmazeStyle style;
  final ToolWheelGeometry geometry;
  final ValueChanged<int>? onOpenLibrary;

  void _onEmptyTap(BuildContext context) {
    final open = onOpenLibrary;
    if (open != null) return open(slot);
    _assignSlot(context, slot);
  }

  @override
  Widget build(BuildContext context) {
    final slots = controls.slots;
    final index = slot < slots.length ? slots[slot] : null;
    final tool = index == null ? null : controls.tools[index];
    final toolState = controls.toolState;
    final selected =
        index != null &&
        (index == toolState.index ||
            toolState.toggleableHandlers.containsKey(index));
    final surface = style.surface.withValues(alpha: kWheelSurfaceOpacity);
    final fill = selected ? (controls.color ?? style.accent) : surface;
    final opaqueFill = fill.withValues(alpha: 1);
    final light = selected && opaqueFill.computeLuminance() > 0.8;
    final side = light
        ? const BorderSide(color: Color(0xDD000000), width: 1.5)
        : BorderSide(color: style.outline);
    final content = selected ? contrastingContent(opaqueFill) : style.onSurface;
    final VoidCallback onTap = tool == null
        ? () => _onEmptyTap(context)
        : () => _onSlotTap(context, slot);
    final loc = AppLocalizations.of(context);
    final iconSize = geometry.radius * 0.16;
    final label = tool == null ? null : _toolSizeLabel(tool);
    final hit = WheelHit.slot(slot);
    return Stack(
      children: [
        _wheelRegion(
          geometry,
          hit,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: DecoratedBox(
              key: ValueKey(('amaze-wedge', slot)),
              decoration: ShapeDecoration(
                color: fill,
                shape: _SectorBorder(geometry.slotSector(slot), side),
              ),
            ),
          ),
        ),
        _placeOnWheel(
          geometry,
          geometry.slotIconCenter(slot),
          Size.square(geometry.radius * 0.3),
          Tooltip(
            message: tool?.getDisplay(context) ?? loc.emptySlot,
            triggerMode: TooltipTriggerMode.manual,
            child: GestureDetector(
              key: ValueKey(('amaze-slot', slot)),
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Center(
                child: tool == null
                    ? PhosphorIcon(
                        PhosphorIconsLight.plus,
                        size: iconSize * 0.75,
                        color: style.muted,
                      )
                    : AmazeIcon(
                        amazeToolIcon(tool),
                        filled: selected,
                        size: iconSize,
                        color: content,
                      ),
              ),
            ),
          ),
          hit: hit,
        ),
        if (label != null)
          _placeOnWheel(
            geometry,
            geometry.slotLabelCenter(slot),
            Size(geometry.radius * 0.3, geometry.radius * 0.12),
            IgnorePointer(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  key: ValueKey(('amaze-slot-size', slot)),
                  style: TextStyle(
                    color: content,
                    fontSize: geometry.radius * 0.075,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One adjustment sector of the center disc: its icon and value.
///
/// A supported adjustment opens its panel when tapped anywhere on its
/// sector. Pressing and dragging vertically right away (more than 8 px,
/// before a long press fires) scrubs the value: up increases it, and 200 px
/// covers the tool's range, on a log scale for size. A plain mouse wheel
/// steps the value by 1% of the range per 100 px. Both show the value live
/// and change the tool once, at the end of the drag or 300 ms after the
/// last scroll; a cancelled drag changes nothing. An unsupported adjustment
/// is dimmed and left to the ring.
class _DiscAdjustment extends StatefulWidget {
  const _DiscAdjustment({
    required this.adjustment,
    required this.controls,
    required this.style,
    required this.geometry,
    required this.open,
    this.onTap,
  });

  final ToolAdjustment adjustment;
  final _ToolControls controls;
  final AmazeStyle style;
  final ToolWheelGeometry geometry;
  final bool open;
  final VoidCallback? onTap;

  @override
  State<_DiscAdjustment> createState() => _DiscAdjustmentState();
}

class _DiscAdjustmentState extends State<_DiscAdjustment> {
  /// Vertical distance in pixels that covers the whole range.
  static const _scrubDistance = 200.0;

  /// Movement before a press becomes a scrub.
  static const _scrubSlop = 8.0;

  /// The value shown while scrubbing or scrolling, or null.
  double? _preview;

  /// The value and pointer position when the scrub started.
  double? _scrubStart;
  double? _scrubOriginY;

  /// Applies the scrolled value shortly after the last scroll.
  Timer? _scrollCommit;

  @override
  void dispose() {
    _scrollCommit?.cancel();
    super.dispose();
  }

  Tool? get _tool => widget.controls.active;

  double? get _value => _tool?.readAdjustment(widget.adjustment);

  /// [start] moved by [fraction] of the range, on a log scale for size.
  double _shift(double start, double fraction) {
    final range = _tool!.adjustmentRange(widget.adjustment);
    if (widget.adjustment == ToolAdjustment.size) {
      final low = log(max(range.min, 1e-6));
      final high = log(range.max);
      final from = log(max(start, range.min));
      return range.clamp(exp(from + fraction * (high - low)));
    }
    return range.clamp(start + fraction * (range.max - range.min));
  }

  void _commit() {
    final preview = _preview;
    final value = _value;
    setState(() => _preview = null);
    if (preview == null || value == null || preview == value) return;
    _applyAdjustment(context, widget.adjustment, preview);
  }

  void _onScrubStart(DragStartDetails details) {
    final value = _value;
    if (value == null) return;
    _scrollCommit?.cancel();
    setState(() {
      _scrubStart = value;
      _scrubOriginY = details.globalPosition.dy;
      _preview = value;
    });
  }

  void _onScrubUpdate(DragUpdateDetails details) {
    final start = _scrubStart;
    final origin = _scrubOriginY;
    if (start == null || origin == null) return;
    final fraction = (origin - details.globalPosition.dy) / _scrubDistance;
    setState(() => _preview = _shift(start, fraction));
  }

  void _onScrubEnd(DragEndDetails details) {
    if (_scrubStart == null) return;
    // The drag recognizer ends a cancelled drag like a finished one.
    if (_pointerCancelled) return _onScrubCancel();
    _scrubStart = null;
    _scrubOriginY = null;
    _commit();
  }

  /// Whether the current pointer was cancelled, noticed before the drag
  /// recognizer handles the cancel.
  bool _pointerCancelled = false;

  /// A cancelled scrub restores the start value and changes nothing.
  void _onScrubCancel() {
    if (_scrubStart == null) return;
    setState(() {
      _scrubStart = null;
      _scrubOriginY = null;
      _preview = null;
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      final value = _value;
      if (dy == 0 || value == null || _scrubStart != null) return;
      final range = _tool!.adjustmentRange(widget.adjustment);
      final step = -dy / 100 * 0.01 * (range.max - range.min);
      setState(() => _preview = range.clamp((_preview ?? value) + step));
      _scrollCommit?.cancel();
      _scrollCommit = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _commit();
      });
    });
  }

  /// Taps open the panel; an immediate vertical drag scrubs the value.
  Widget _gestures(Widget child, {Key? key}) {
    return RawGestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      gestures: {
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(debugOwner: this),
              (recognizer) => recognizer.onTap = widget.onTap,
            ),
        VerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer(debugOwner: this),
              (recognizer) => recognizer
                ..gestureSettings = const DeviceGestureSettings(
                  touchSlop: _scrubSlop,
                )
                // Measures from where the pointer went down, not from where
                // the drag was recognized.
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = _onScrubStart
                ..onUpdate = _onScrubUpdate
                ..onEnd = _onScrubEnd
                ..onCancel = _onScrubCancel,
            ),
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final adjustment = widget.adjustment;
    final geometry = widget.geometry;
    final style = widget.style;
    final value = _value;
    final shown = _preview ?? value;
    final loc = AppLocalizations.of(context);
    final color = style.onSurface;
    final iconSize = geometry.radius * 0.11;
    final labelSize = Size(geometry.radius * 0.36, geometry.radius * 0.16);
    final label = Row(
      mainAxisSize: .min,
      spacing: geometry.radius * 0.03,
      children: [
        AmazeIcon(_adjustmentIcon(adjustment), size: iconSize, color: color),
        if (shown != null)
          Text(
            _discLabel(loc, adjustment, shown),
            style: TextStyle(
              color: color,
              fontSize: geometry.radius * 0.085,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
      ],
    );
    final offset = geometry.adjustmentLabelCenter(adjustment);
    if (value == null) {
      return Stack(
        children: [
          _placeOnWheel(
            geometry,
            offset,
            labelSize,
            IgnorePointer(
              child: Opacity(
                opacity: 0.4,
                child: FittedBox(fit: BoxFit.scaleDown, child: label),
              ),
            ),
          ),
        ],
      );
    }
    final hit = WheelHit.adjustment(adjustment);
    return Listener(
      onPointerSignal: _onPointerSignal,
      onPointerDown: (_) => _pointerCancelled = false,
      onPointerCancel: (_) => _pointerCancelled = true,
      child: Stack(
        children: [
          _wheelRegion(
            geometry,
            hit,
            _gestures(
              key: ValueKey(('amaze-adjust-sector', adjustment.name)),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: widget.open
                      ? style.accent.withValues(alpha: 0.25)
                      : Colors.transparent,
                  shape: _SectorBorder(
                    geometry.adjustmentSector(adjustment),
                    BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          _placeOnWheel(
            geometry,
            offset,
            labelSize,
            Tooltip(
              message: _adjustmentName(loc, adjustment),
              triggerMode: TooltipTriggerMode.manual,
              child: _gestures(
                key: ValueKey(('amaze-adjust', adjustment.name)),
                FittedBox(fit: BoxFit.scaleDown, child: label),
              ),
            ),
            hit: hit,
          ),
        ],
      ),
    );
  }
}

/// The outline of a [WheelSector], centered in the box it decorates.
class _SectorBorder extends ShapeBorder {
  const _SectorBorder(this.sector, this.side);

  final WheelSector sector;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return sector.toPath(rect.center);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return getOuterPath(rect, textDirection: textDirection);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => _SectorBorder(sector, side.scale(t));

  @override
  bool operator ==(Object other) {
    return other is _SectorBorder &&
        other.side == side &&
        other.sector.innerRadius == sector.innerRadius &&
        other.sector.outerRadius == sector.outerRadius &&
        other.sector.startAngle == sector.startAngle &&
        other.sector.sweepAngle == sector.sweepAngle;
  }

  @override
  int get hashCode => Object.hash(
    side,
    sector.innerRadius,
    sector.outerRadius,
    sector.startAngle,
    sector.sweepAngle,
  );
}

/// The tool wheel.
///
/// Eight wedge slots cover the outer band, with undo and redo in the gap on
/// the left. The center disc shows the size, opacity and smoothing of the
/// active tool around its color.
///
/// Taps go to the control under the pointer. A long press anywhere on the
/// wheel is reported through the hold callbacks with the spot it started
/// on; the owner decides whether it becomes a drag or that spot's long
/// press action.
class ToolWheel extends StatelessWidget {
  const ToolWheel({
    super.key,
    this.geometry = const ToolWheelGeometry(),
    this.openAdjustment,
    this.onAdjustmentTap,
    this.onHoldStart,
    this.onHoldMove,
    this.onHoldEnd,
    this.holding = false,
    this.onOpenLibrary,
  });

  final ToolWheelGeometry geometry;
  final ToolAdjustment? openAdjustment;
  final ValueChanged<ToolAdjustment>? onAdjustmentTap;

  /// Called when a long press fires, with the spot it started on.
  final void Function(LongPressStartDetails details, WheelHit spot)?
  onHoldStart;
  final GestureLongPressMoveUpdateCallback? onHoldMove;
  final GestureLongPressEndCallback? onHoldEnd;

  /// Whether a long press is being held, which highlights the wheel.
  final bool holding;

  /// Opens the brush library for an empty slot that is tapped.
  final ValueChanged<int>? onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return _ToolControlsBuilder(builder: _buildWheel);
  }

  Widget _buildWheel(BuildContext context, _ToolControls controls) {
    final style = AmazeStyle.of(context);
    final surface = style.surface.withValues(alpha: kWheelSurfaceOpacity);
    final historySize = Size.square(geometry.historyRadius * 2);
    final center = Offset(geometry.radius, geometry.radius);
    final holdStart = onHoldStart;
    return SizedBox.square(
      key: const ValueKey('amaze-tool-wheel'),
      dimension: geometry.diameter,
      child: GestureDetector(
        key: const ValueKey('amaze-wheel-hold'),
        onLongPressStart: holdStart == null
            ? null
            : (details) => holdStart(
                details,
                geometry.hitTest(details.localPosition - center),
              ),
        onLongPressMoveUpdate: onHoldMove,
        onLongPressEnd: onHoldEnd,
        child: _buildStack(controls, style, surface, historySize),
      ),
    );
  }

  Widget _buildStack(
    _ToolControls controls,
    AmazeStyle style,
    Color surface,
    Size historySize,
  ) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipOval(
            child: GestureDetector(
              key: const ValueKey('amaze-wheel-ring'),
              behavior: HitTestBehavior.opaque,
              child: CustomPaint(
                painter: _WheelPainter(
                  style: style,
                  geometry: geometry,
                  holding: holding,
                ),
              ),
            ),
          ),
        ),
        _placeOnWheel(
          geometry,
          Offset.zero,
          Size.square(geometry.discRadius * 2),
          IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('amaze-wheel-disc'),
              decoration: BoxDecoration(
                color: surface,
                shape: BoxShape.circle,
                border: Border.all(color: style.outline),
              ),
            ),
          ),
        ),
        for (var slot = 0; slot < kToolSlotCount; slot++)
          Positioned.fill(
            child: _WedgeSlot(
              slot: slot,
              controls: controls,
              style: style,
              geometry: geometry,
              onOpenLibrary: onOpenLibrary,
            ),
          ),
        for (final adjustment in ToolAdjustment.values)
          Positioned.fill(
            child: _DiscAdjustment(
              adjustment: adjustment,
              controls: controls,
              style: style,
              geometry: geometry,
              open: openAdjustment == adjustment,
              onTap: () => onAdjustmentTap?.call(adjustment),
            ),
          ),
        _placeOnWheel(
          geometry,
          geometry.undoCenter,
          historySize,
          _HistoryButton(
            redo: false,
            style: style,
            size: historySize.width,
            background: surface,
          ),
          hit: WheelHit.undo,
        ),
        _placeOnWheel(
          geometry,
          geometry.redoCenter,
          historySize,
          _HistoryButton(
            redo: true,
            style: style,
            size: historySize.width,
            background: surface,
          ),
          hit: WheelHit.redo,
        ),
        _placeOnWheel(
          geometry,
          Offset.zero,
          Size.square(geometry.centerRadius * 2),
          _ColorButton(
            controls: controls,
            style: style,
            diameter: geometry.centerRadius * 2,
          ),
          hit: WheelHit.center,
        ),
      ],
    );
  }
}

/// Takes the wheel out of hit testing while a plain scroll is passed on to
/// the canvas underneath, see [_AmazeToolWheelLayerState._passToCanvas].
class _WheelPassThrough extends SingleChildRenderObjectWidget {
  const _WheelPassThrough({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderWheelPassThrough();
  }
}

class _RenderWheelPassThrough extends RenderProxyBox {
  /// Whether an event is being passed through the wheel right now.
  static bool passing = false;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (passing) return false;
    return super.hitTest(result, position: position);
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

/// Paints the wheel's outline across the undo and redo gap, so the gap
/// reads as part of the wheel. Wedges and the disc paint themselves.
class _WheelPainter extends CustomPainter {
  const _WheelPainter({
    required this.style,
    required this.geometry,
    this.holding = false,
  });

  final AmazeStyle style;
  final ToolWheelGeometry geometry;

  /// Highlights the rim while a long press is held.
  final bool holding;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final end = geometry.slotStartAngle(kToolSlotCount);
    final gap = geometry.slotStartAngle(0) + 2 * pi - end;
    // The gap behind undo and redo is part of the wheel and its drag area.
    final gapSector = WheelSector(
      innerRadius: geometry.wedgeInnerRadius,
      outerRadius: geometry.radius,
      startAngle: end,
      sweepAngle: gap,
    );
    canvas.drawPath(
      gapSector.toPath(center),
      Paint()
        ..color = style.surface.withValues(alpha: kWheelSurfaceOpacity / 2),
    );
    final outline = Paint()
      ..color = style.outline
      ..style = PaintingStyle.stroke;
    for (final radius in [geometry.radius - 0.5, geometry.wedgeInnerRadius]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        end,
        gap,
        false,
        outline,
      );
    }
    if (holding) {
      canvas.drawCircle(
        center,
        geometry.radius - 1.5,
        Paint()
          ..color = style.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) {
    return oldDelegate.geometry.diameter != geometry.diameter ||
        oldDelegate.style.outline != style.outline ||
        oldDelegate.style.surface != style.surface ||
        oldDelegate.style.accent != style.accent ||
        oldDelegate.holding != holding;
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

/// The adjustment panel: four presets, the slider and a value field.
///
/// The slider shows its value live while dragging and changes the tool once,
/// when the drag ends, so one gesture is one undo step. A cancelled drag
/// changes nothing. Tapping a preset applies it; holding a preset saves the
/// current value into it.
class _AdjustmentPanelState extends State<_AdjustmentPanel> {
  /// The value while the slider is dragged, or null.
  double? _dragValue;

  /// Whether the current slider pointer was cancelled.
  bool _cancelled = false;

  /// The presets of the active tool's kind, once loaded.
  List<double>? _presets;

  /// The tool kind and adjustment [_presets] belong to.
  String? _presetsFor;

  final _field = TextEditingController();
  final _fieldFocus = FocusNode();
  String? _fieldError;

  /// The tool and value the panel was last built with.
  Tool? _tool;
  double? _value;

  @override
  void initState() {
    super.initState();
    _fieldFocus.addListener(() {
      if (!_fieldFocus.hasFocus) _submitField();
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _loadPresets(Tool tool) {
    final key = '${presetToolKey(tool)}.${widget.adjustment.name}';
    if (key == _presetsFor) return;
    _presetsFor = key;
    _presets = null;
    loadPresets(tool, widget.adjustment).then((presets) {
      if (mounted && _presetsFor == key) setState(() => _presets = presets);
    });
  }

  /// [value] in the field's units: points, or percent.
  String _fieldText(double value) {
    if (widget.adjustment == ToolAdjustment.size) return _formatSize(value);
    return _formatSize(value * 100);
  }

  double _fromField(double entered) {
    if (widget.adjustment == ToolAdjustment.size) return entered;
    return entered / 100;
  }

  /// Shows [value] in the field unless the user is editing it.
  void _syncField(double value) {
    if (_fieldFocus.hasFocus) return;
    final text = _fieldText(value);
    if (_field.text != text) _field.text = text;
  }

  /// Restores the field to the current value and drops any error.
  void _resetField() {
    final value = _value;
    if (value != null) _field.text = _fieldText(value);
    setState(() => _fieldError = null);
  }

  /// Applies the field's value if it is a number in the tool's range, and
  /// shows an error otherwise.
  void _submitField() {
    final tool = _tool;
    final value = _value;
    if (tool == null || value == null || !mounted) return;
    if (_field.text.trim() == _fieldText(value)) {
      if (_fieldError != null) setState(() => _fieldError = null);
      return;
    }
    final range = tool.adjustmentRange(widget.adjustment);
    final entered = double.tryParse(_field.text.trim().replaceAll(',', '.'));
    final next = entered == null ? null : _fromField(entered);
    if (next == null || next < range.min || next > range.max) {
      final loc = AppLocalizations.of(context);
      setState(() {
        _fieldError = loc.amazeValueRangeError(
          _fieldText(range.min),
          _fieldText(range.max),
        );
      });
      return;
    }
    setState(() => _fieldError = null);
    // Enter and the focus loss that follows it submit the same text.
    if (next == value || next == _applied) return;
    _applied = next;
    _applyAdjustment(context, widget.adjustment, next);
  }

  /// The value the field last applied, until the tool shows it.
  double? _applied;

  void _applyPreset(double preset, double value) {
    if (preset == value) return;
    _applyAdjustment(context, widget.adjustment, preset);
  }

  void _savePreset(Tool tool, int index, double value) {
    final presets = _presets;
    if (presets == null) return;
    final next = [...presets]..[index] = value;
    setState(() => _presets = next);
    savePresets(tool, widget.adjustment, next);
  }

  String _presetLabel(AppLocalizations loc, double value) {
    if (widget.adjustment == ToolAdjustment.size) {
      return loc.amazeSizePts(_formatSize(value));
    }
    return formatAdjustment(widget.adjustment, value);
  }

  @override
  Widget build(BuildContext context) {
    return _ToolControlsBuilder(builder: _buildPanel);
  }

  Widget _buildPresets(Tool tool, double value, AmazeStyle style) {
    final presets = _presets;
    final loc = AppLocalizations.of(context);
    return Row(
      spacing: 6,
      children: [
        for (var index = 0; index < kPresetCount; index++)
          Expanded(
            child: Tooltip(
              message: loc.amazePresetHint,
              triggerMode: TooltipTriggerMode.manual,
              child: _PresetChip(
                key: ValueKey(('amaze-preset', index)),
                label: presets == null ? '' : _presetLabel(loc, presets[index]),
                selected:
                    presets != null && presetMatches(presets[index], value),
                style: style,
                onTap: presets == null
                    ? null
                    : () => _applyPreset(presets[index], value),
                onLongPress: presets == null
                    ? null
                    : () => _savePreset(tool, index, value),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPanel(BuildContext context, _ToolControls controls) {
    final adjustment = widget.adjustment;
    final tool = controls.active;
    final value = tool?.readAdjustment(adjustment);
    if (tool == null || value == null) return const SizedBox.shrink();
    _tool = tool;
    _value = value;
    if (_applied == value) _applied = null;
    _loadPresets(tool);
    final range = tool.adjustmentRange(adjustment);
    final shown = range.clamp(_dragValue ?? value);
    _syncField(shown);
    final loc = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final style = AmazeStyle.of(context);
    return AmazeSurface(
      key: const ValueKey('amaze-adjustment-panel'),
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
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
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildPresets(tool, value, style),
            ),
            // The slider ends a cancelled drag like a finished one, so the
            // cancel is noticed here, before the slider handles it.
            Listener(
              onPointerDown: (_) => _cancelled = false,
              onPointerCancel: (_) => _cancelled = true,
              child: Slider(
                key: const ValueKey('amaze-adjustment-slider'),
                value: shown,
                min: range.min,
                max: range.max,
                onChanged: (next) => setState(() => _dragValue = next),
                onChangeEnd: (next) {
                  setState(() => _dragValue = null);
                  if (_cancelled) {
                    _cancelled = false;
                    return;
                  }
                  if (next == value) return;
                  _applyAdjustment(context, adjustment, next);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): _resetField,
                },
                child: TextField(
                  key: const ValueKey('amaze-adjustment-field'),
                  controller: _field,
                  focusNode: _fieldFocus,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submitField(),
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixText: adjustment == ToolAdjustment.size
                        ? loc.amazeUnitPts
                        : '%',
                    errorText: _fieldError,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One preset of the adjustment panel.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    super.key,
    required this.label,
    required this.selected,
    required this.style,
    this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final AmazeStyle style;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = selected ? style.onAccent : style.onSurface;
    return Material(
      color: selected ? style.accent : style.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: 36,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
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

  /// Where the current hold started, or null if the wheel is not held.
  Offset? _holdStart;

  /// The spot the current hold started on.
  WheelHit? _holdSpot;

  /// Cancels a hold when the app loses focus.
  AppLifecycleListener? _lifecycle;
  bool _overDock = false;
  Offset? _lastPointer;
  ToolAdjustment? _openAdjustment;

  /// The slot the brush library is open for, if it is open.
  int? _librarySlot;

  /// Diameter when the current pinch started.
  double? _pinchStart;

  /// Saves the size shortly after the last Ctrl + scroll step.
  Timer? _scrollSave;

  /// Pointers that went down off the wheel, and whether each is currently
  /// near the wheel.
  final Map<int, bool> _strokes = {};

  /// Whether the wheel is faded because a stroke passes underneath.
  bool _faded = false;

  /// Restores the wheel shortly after the last stroke leaves it.
  Timer? _unfade;

  @override
  void initState() {
    super.initState();
    loadToolWheelLayout().then((layout) {
      if (mounted) setState(() => _layout = layout);
    });
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) _cancelHold();
      },
    );
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    _lifecycle?.dispose();
    _unfade?.cancel();
    if (_scrollSave?.isActive ?? false) saveToolWheelLayout(_layout);
    _scrollSave?.cancel();
    super.dispose();
  }

  /// The expanded wheel's rectangle in global coordinates, or null if it is
  /// not shown.
  Rect? get _globalWheelRect {
    if (_layout.mode != ToolWheelMode.wheel || _layout.collapsed) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(_position) & _wheelSize;
  }

  /// Watches every pointer without taking part in gestures, so canvas input
  /// is never blocked. A pointer that went down off the wheel and moves near
  /// it fades the wheel.
  void _onGlobalPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      final rect = _globalWheelRect;
      final onWheel =
          rect != null &&
          (event.position - rect.center).distance <= rect.width / 2;
      if (!onWheel) _strokes[event.pointer] = false;
      return;
    }
    if (!_strokes.containsKey(event.pointer)) return;
    if (event is PointerMoveEvent) {
      final rect = _globalWheelRect;
      final near =
          rect != null &&
          (event.position - rect.center).distance <= rect.width / 2 + 12;
      _strokes[event.pointer] = near;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _strokes.remove(event.pointer);
    } else {
      return;
    }
    _updateFade();
  }

  void _updateFade() {
    final near = _strokes.values.any((value) => value);
    if (near) {
      _unfade?.cancel();
      _unfade = null;
      if (!_faded) setState(() => _faded = true);
    } else if (_faded && _unfade == null) {
      _unfade = Timer(const Duration(milliseconds: 150), () {
        _unfade = null;
        if (mounted) setState(() => _faded = false);
      });
    }
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

  /// Ctrl + scroll over the wheel resizes it by the scroll distance: a
  /// 100 px mouse notch is 16 px, and small trackpad steps resize smoothly.
  /// A plain scroll is passed on to the canvas underneath.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!HardwareKeyboard.instance.isControlPressed) {
      // Over a disc sector, a plain scroll steps that adjustment instead.
      final geometry = _geometry;
      final center = Offset(geometry.radius, geometry.radius);
      final spot = geometry.hitTest(event.localPosition - center);
      if (spot.type != WheelHitType.adjustment) _passToCanvas(event);
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0) return;
      _resize(_diameter - dy * _scrollScale);
      _scrollSave?.cancel();
      _scrollSave = Timer(_scrollSaveDelay, () {
        if (mounted) saveToolWheelLayout(_layout);
      });
    });
  }

  /// Dispatches [event] again with the wheel left out of hit testing, so
  /// whatever lies under the wheel receives it.
  void _passToCanvas(PointerSignalEvent event) {
    if (_RenderWheelPassThrough.passing) return;
    _RenderWheelPassThrough.passing = true;
    try {
      GestureBinding.instance.handlePointerEvent(event.original ?? event);
    } finally {
      _RenderWheelPassThrough.passing = false;
    }
  }

  /// Diameter change per pixel of scroll distance.
  static const _scrollScale = 0.16;
  static const _scrollSaveDelay = Duration(milliseconds: 300);

  /// Distance a held pointer has to move before the wheel is dragged.
  static const _dragSlop = 8.0;

  /// A long press fired: the wheel is held. It becomes a drag once the
  /// pointer moves; released in place it runs [spot]'s long press action.
  void _onHoldStart(LongPressStartDetails details, WheelHit spot) {
    HapticFeedback.lightImpact();
    setState(() {
      _holdSpot = spot;
      _holdStart = details.globalPosition;
      _lastPointer = details.globalPosition;
      _overDock = false;
    });
  }

  void _onHoldMove(LongPressMoveUpdateDetails details) {
    final start = _holdStart;
    if (start == null) return;
    final pointer = details.globalPosition;
    if (!_dragging) {
      if ((pointer - start).distance <= _dragSlop) return;
      setState(() {
        _dragging = true;
        _openAdjustment = null;
      });
    }
    final last = _lastPointer ?? pointer;
    _lastPointer = pointer;
    _move(pointer - last, overDock: _dockRect.contains(_toLocal(pointer)));
  }

  void _onHoldEnd(LongPressEndDetails details) {
    if (_holdStart == null) return;
    final dragging = _dragging;
    final dock = _overDock;
    final spot = _holdSpot;
    _endHold();
    if (!dragging) {
      if (spot != null) _runHoldAction(spot);
    } else if (dock) {
      _update(_layout.copyWith(mode: ToolWheelMode.bar));
    } else {
      saveToolWheelLayout(_layout);
    }
  }

  /// Ends a hold that was interrupted: the wheel stays where it was last
  /// placed, that position is saved and nothing opens.
  void _cancelHold() {
    if (_holdStart == null) return;
    _endHold();
    saveToolWheelLayout(_layout);
  }

  void _endHold() {
    setState(() {
      _holdStart = null;
      _holdSpot = null;
      _dragging = false;
      _overDock = false;
      _lastPointer = null;
    });
  }

  /// The long press action of the spot a hold started on, run when it is
  /// released without moving.
  void _runHoldAction(WheelHit spot) {
    switch (spot.type) {
      case WheelHitType.slot:
        _openLibrary(spot.slot!);
      case WheelHitType.center:
        _update(_layout.copyWith(collapsed: true));
      default:
        break;
    }
  }

  /// Watches pointers on the wheel for interruptions of a hold: a second
  /// pointer (which turns it into a pinch) or a cancelled pointer.
  void _onWheelPointer(PointerEvent event) {
    if (_holdStart == null) return;
    if (event is PointerDownEvent || event is PointerCancelEvent) {
      _cancelHold();
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
        child: AnimatedOpacity(
          key: const ValueKey('amaze-wheel-fade'),
          opacity: _faded ? kWheelFadedOpacity : 1,
          duration: const Duration(milliseconds: 120),
          child: _buildWheelGestures(),
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

  /// The wheel with its pinch and Ctrl + scroll resizing.
  Widget _buildWheelGestures() {
    return _WheelPassThrough(
      child: Listener(
        onPointerSignal: _onPointerSignal,
        onPointerDown: _onWheelPointer,
        onPointerCancel: _onWheelPointer,
        child: _buildPinch(),
      ),
    );
  }

  Widget _buildPinch() {
    return RawGestureDetector(
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
        onHoldStart: _onHoldStart,
        onHoldMove: _onHoldMove,
        onHoldEnd: _onHoldEnd,
        holding: _holdStart != null,
        onOpenLibrary: _openLibrary,
      ),
    );
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
    const height = 230.0;
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
