import 'package:butterfly/models/defaults.dart';
import 'package:butterfly_api/butterfly_api.dart';

/// Number of configurable tool slots on the wheel and the tool bar.
const kToolSlotCount = 8;

/// Whether [tool] can sit in a slot. Undo and redo have their own controls.
bool isSlotTool(Tool tool) => tool is! UndoTool && tool is! RedoTool;

/// Document tool indices shown in the slots, in slot order.
///
/// The slots are the first [kToolSlotCount] tools of the document that are
/// not undo or redo, so the assignment is stored with the document.
List<int> slotToolIndices(List<Tool> tools) {
  final indices = <int>[];
  for (var i = 0; i < tools.length && indices.length < kToolSlotCount; i++) {
    if (isSlotTool(tools[i])) indices.add(i);
  }
  return indices;
}

/// Tools that can be assigned to a slot: the built-in presets without undo
/// and redo.
List<Tool> slotToolCatalog() {
  return DocumentDefaults.createToolPresets().where(isSlotTool).toList();
}

/// The [ToolReordered] target that swaps the tools in [fromSlot] and
/// [toSlot], or null if either slot is empty.
(String id, int newIndex)? slotMoveTarget(
  List<Tool> tools,
  int fromSlot,
  int toSlot,
) {
  final indices = slotToolIndices(tools);
  if (fromSlot < 0 || toSlot < 0) return null;
  if (fromSlot >= indices.length || toSlot >= indices.length) return null;
  final from = indices[fromSlot];
  final to = indices[toSlot];
  final id = tools[from].id;
  if (id == null || from == to) return null;
  // ToolReordered removes the tool first, so moving forward needs one more.
  return (id, from < to ? to + 1 : to);
}

/// Adjustments on the middle ring of the tool wheel.
enum ToolAdjustment { size, opacity, smoothing }

/// Range of an adjustment for a tool.
class ToolAdjustmentRange {
  const ToolAdjustmentRange(this.min, this.max);

  final double min;
  final double max;

  double clamp(double value) => value.clamp(min, max);
}

double? _opacityOf(ElementPaint paint) => switch (paint) {
  SolidElementPaint solid => solid.color.a / 255,
  _ => null,
};

ElementPaint _withOpacity(ElementPaint paint, double opacity) {
  if (paint is! SolidElementPaint) return paint;
  final alpha = (opacity.clamp(0.0, 1.0) * 255).round();
  return paint.copyWith(color: paint.color.withValues(a: alpha));
}

/// Reads and writes the adjustments a tool really supports.
///
/// Size is the stroke width, opacity is the alpha of a solid paint and
/// smoothing is the pen's smoothing. Tools without one of these fields
/// return null, so the wheel does not show a control for it.
extension ToolAdjustments on Tool {
  /// Adjustments this tool supports, in ring order.
  List<ToolAdjustment> get adjustments => [
    for (final adjustment in ToolAdjustment.values)
      if (readAdjustment(adjustment) != null) adjustment,
  ];

  /// Current value, or null if the tool has no such property.
  double? readAdjustment(ToolAdjustment adjustment) {
    return switch (adjustment) {
      ToolAdjustment.size => _readSize(this),
      ToolAdjustment.opacity => _readOpacity(this),
      ToolAdjustment.smoothing => _readSmoothing(this),
    };
  }

  /// Valid range of [adjustment] for this tool.
  ToolAdjustmentRange adjustmentRange(ToolAdjustment adjustment) {
    if (adjustment != ToolAdjustment.size) {
      return const ToolAdjustmentRange(0, 1);
    }
    final tool = this;
    if (tool is PenTool) return const ToolAdjustmentRange(0.1, 70);
    if (tool is EraserTool) return const ToolAdjustmentRange(1, 70);
    return const ToolAdjustmentRange(0.5, 70);
  }

  /// This tool with [adjustment] set to [value], clamped to its range.
  /// Tools without the property are returned unchanged.
  Tool writeAdjustment(ToolAdjustment adjustment, double value) {
    final clamped = adjustmentRange(adjustment).clamp(value);
    return switch (adjustment) {
      ToolAdjustment.size => _writeSize(this, clamped),
      ToolAdjustment.opacity => _writeOpacity(this, clamped),
      ToolAdjustment.smoothing => _writeSmoothing(this, clamped),
    };
  }
}

double? _readSize(Tool tool) => switch (tool) {
  PenTool(:final property) => property.strokeWidth,
  ShapeTool(:final property) => property.strokeWidth,
  PolygonTool(:final property) => property.strokeWidth,
  EraserTool(:final strokeWidth) => strokeWidth,
  LaserTool(:final strokeWidth) => strokeWidth,
  _ => null,
};

double? _readOpacity(Tool tool) => switch (tool) {
  PenTool(:final property) => _opacityOf(property.paint),
  ShapeTool(:final property) => _opacityOf(property.paint),
  PolygonTool(:final property) => _opacityOf(property.paint),
  _ => null,
};

double? _readSmoothing(Tool tool) => switch (tool) {
  PenTool(:final property) => property.smoothing,
  _ => null,
};

Tool _writeSize(Tool tool, double value) {
  if (tool is PenTool) {
    final property = tool.property.copyWith(strokeWidth: value);
    return tool.copyWith(property: property);
  }
  if (tool is ShapeTool) {
    final property = tool.property.copyWith(strokeWidth: value);
    return tool.copyWith(property: property);
  }
  if (tool is PolygonTool) {
    final property = tool.property.copyWith(strokeWidth: value);
    return tool.copyWith(property: property);
  }
  if (tool is EraserTool) return tool.copyWith(strokeWidth: value);
  if (tool is LaserTool) return tool.copyWith(strokeWidth: value);
  return tool;
}

Tool _writeOpacity(Tool tool, double value) {
  if (tool is PenTool) {
    final paint = _withOpacity(tool.property.paint, value);
    return tool.copyWith(property: tool.property.copyWith(paint: paint));
  }
  if (tool is ShapeTool) {
    final paint = _withOpacity(tool.property.paint, value);
    return tool.copyWith(property: tool.property.copyWith(paint: paint));
  }
  if (tool is PolygonTool) {
    final paint = _withOpacity(tool.property.paint, value);
    return tool.copyWith(property: tool.property.copyWith(paint: paint));
  }
  return tool;
}

Tool _writeSmoothing(Tool tool, double value) {
  if (tool is! PenTool) return tool;
  final property = tool.property.copyWith(smoothing: value);
  return tool.copyWith(property: property);
}

/// Short text for an adjustment value, as shown on the wheel.
String formatAdjustment(ToolAdjustment adjustment, double value) {
  if (adjustment != ToolAdjustment.size) return '${(value * 100).round()}%';
  if (value >= 10) return value.round().toString();
  return value.toStringAsFixed(1);
}
