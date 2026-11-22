import 'package:butterfly_api/butterfly_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library.dart';
import 'tool_slots.dart';

/// Number of presets per tool kind and adjustment.
const kPresetCount = 4;

/// aMaze's default presets, clamped to each tool's range when used.
const _defaults = {
  ToolAdjustment.size: [2.0, 5.0, 10.0, 25.0],
  ToolAdjustment.opacity: [0.25, 0.5, 0.75, 1.0],
  ToolAdjustment.smoothing: [0.0, 0.25, 0.5, 0.75],
};

/// The kind of [tool] that presets are shared by.
///
/// It is the brush library entry the tool was made from (or the entry that
/// matches a built-in tool), so two Pen slots share presets while Pen and
/// Fixed Width do not. Tools the library does not know use their tool type
/// from the document format, like `eraser`.
String presetToolKey(Tool tool) {
  final entry = libraryEntryOf(tool);
  if (entry != null) return entry.name;
  final type = tool.toJson()['type'];
  return type is String && type.isNotEmpty ? type : 'tool';
}

String _prefsKey(Tool tool, ToolAdjustment adjustment) {
  return 'amaze.presets.${presetToolKey(tool)}.${adjustment.name}';
}

/// The default presets of [adjustment] for [tool].
List<double> defaultPresets(Tool tool, ToolAdjustment adjustment) {
  final range = tool.adjustmentRange(adjustment);
  return [for (final value in _defaults[adjustment]!) range.clamp(value)];
}

/// Parses saved presets: exactly [kPresetCount] numbers, or null.
List<double>? _parse(Object? saved) {
  if (saved is! List || saved.length != kPresetCount) return null;
  final values = <double>[];
  for (final item in saved) {
    final value = switch (item) {
      num() => item.toDouble(),
      String() => double.tryParse(item),
      _ => null,
    };
    if (value == null || !value.isFinite) return null;
    values.add(value);
  }
  return values;
}

/// Loads the presets of [adjustment] for the kind of [tool]. Missing or
/// invalid data gives the defaults, and values are clamped to the tool's
/// range.
Future<List<double>> loadPresets(Tool tool, ToolAdjustment adjustment) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = _parse(prefs.get(_prefsKey(tool, adjustment)));
  if (saved == null) return defaultPresets(tool, adjustment);
  final range = tool.adjustmentRange(adjustment);
  return [for (final value in saved) range.clamp(value)];
}

/// Saves the presets of [adjustment] for the kind of [tool].
Future<void> savePresets(
  Tool tool,
  ToolAdjustment adjustment,
  List<double> presets,
) async {
  assert(presets.length == kPresetCount);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_prefsKey(tool, adjustment), [
    for (final value in presets) value.toString(),
  ]);
}

/// Whether [preset] equals [value] within 0.5%.
bool presetMatches(double preset, double value) {
  final scale = value.abs() > preset.abs() ? value.abs() : preset.abs();
  if (scale < 1e-9) return true;
  return (preset - value).abs() <= scale * 0.005;
}
