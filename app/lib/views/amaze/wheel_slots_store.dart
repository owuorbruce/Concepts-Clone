import 'dart:convert';

import 'package:butterfly_api/butterfly_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tool_slots.dart';

/// Preferences key of the wheel's slot tools, shared by every drawing.
const kWheelSlotsKey = 'amaze.wheel.slots';

/// Parses saved slots: a JSON list of exactly [kToolSlotCount] entries, each
/// a tool or null for an empty slot. Anything else gives null.
List<Tool?>? parseWheelSlots(String? saved) {
  if (saved == null) return null;
  try {
    final list = jsonDecode(saved);
    if (list is! List || list.length != kToolSlotCount) return null;
    final slots = <Tool?>[];
    for (final item in list) {
      if (item == null) {
        slots.add(null);
        continue;
      }
      if (item is! Map<String, dynamic>) return null;
      final tool = Tool.fromJson(item);
      if (!isSlotTool(tool)) return null;
      slots.add(tool);
    }
    return slots;
  } catch (_) {
    return null;
  }
}

/// Encodes [slots] for [kWheelSlotsKey].
String encodeWheelSlots(List<Tool?> slots) {
  assert(slots.length == kToolSlotCount);
  return jsonEncode([for (final tool in slots) tool?.toJson()]);
}

/// Loads the wheel's slots, or null if none are saved or the saved data is
/// invalid.
Future<List<Tool?>?> loadWheelSlots() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.get(kWheelSlotsKey);
  return parseWheelSlots(saved is String ? saved : null);
}

/// Saves the wheel's slots.
Future<void> saveWheelSlots(List<Tool?> slots) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kWheelSlotsKey, encodeWheelSlots(slots));
}
