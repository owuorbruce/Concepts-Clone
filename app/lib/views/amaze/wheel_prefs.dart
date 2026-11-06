import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the tool controls are shown.
enum ToolWheelMode { wheel, bar }

/// Layout of the tool wheel that is kept between editor sessions.
@immutable
class ToolWheelLayout {
  const ToolWheelLayout({
    this.mode = ToolWheelMode.wheel,
    this.position,
    this.collapsed = false,
  });

  final ToolWheelMode mode;

  /// Position of the wheel as a fraction of the free space, or null for the
  /// default corner.
  final Offset? position;

  final bool collapsed;

  ToolWheelLayout copyWith({
    ToolWheelMode? mode,
    Offset? position,
    bool? collapsed,
  }) {
    return ToolWheelLayout(
      mode: mode ?? this.mode,
      position: position ?? this.position,
      collapsed: collapsed ?? this.collapsed,
    );
  }
}

const _modeKey = 'amaze.toolWheel.mode';
const _xKey = 'amaze.toolWheel.x';
const _yKey = 'amaze.toolWheel.y';
const _collapsedKey = 'amaze.toolWheel.collapsed';

/// Loads the saved tool wheel layout.
Future<ToolWheelLayout> loadToolWheelLayout() async {
  final prefs = await SharedPreferences.getInstance();
  final mode = prefs.getString(_modeKey) == ToolWheelMode.bar.name
      ? ToolWheelMode.bar
      : ToolWheelMode.wheel;
  final x = prefs.getDouble(_xKey);
  final y = prefs.getDouble(_yKey);
  return ToolWheelLayout(
    mode: mode,
    position: x == null || y == null ? null : Offset(x, y),
    collapsed: prefs.getBool(_collapsedKey) ?? false,
  );
}

/// Saves the tool wheel layout.
Future<void> saveToolWheelLayout(ToolWheelLayout layout) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_modeKey, layout.mode.name);
  await prefs.setBool(_collapsedKey, layout.collapsed);
  final position = layout.position;
  if (position == null) return;
  await prefs.setDouble(_xKey, position.dx);
  await prefs.setDouble(_yKey, position.dy);
}

const _toolOptionsKey = 'amaze.shell.toolOptions';
const _zoomKey = 'amaze.shell.zoom';

/// Which optional editor panels the dock has turned on.
typedef AmazePanels = ({bool toolOptions, bool zoom});

/// Loads which optional panels are shown. Both start hidden.
Future<AmazePanels> loadAmazePanels() async {
  final prefs = await SharedPreferences.getInstance();
  return (
    toolOptions: prefs.getBool(_toolOptionsKey) ?? false,
    zoom: prefs.getBool(_zoomKey) ?? false,
  );
}

/// Saves which optional panels are shown.
Future<void> saveAmazePanels(AmazePanels panels) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_toolOptionsKey, panels.toolOptions);
  await prefs.setBool(_zoomKey, panels.zoom);
}
