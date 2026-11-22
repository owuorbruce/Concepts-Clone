import 'package:flutter/services.dart';

/// Gives one light tick when a snap engages, not on every frame it holds.
///
/// Call [update] on every move with whether the gesture is snapped now.
class SnapHaptics {
  SnapHaptics({this.enabled = true});

  /// Whether the device buzzes at all. Mirrors the "Buzz on snap" setting.
  bool enabled;

  bool _engaged = false;

  /// How many ticks were given, for tests.
  int ticks = 0;

  /// Whether the last [update] was snapped.
  bool get engaged => _engaged;

  /// Records whether the gesture is snapped and ticks when it starts to be.
  void update(bool snapped) {
    if (snapped && !_engaged) tick();
    _engaged = snapped;
  }

  /// One tick, for events that are not a held snap (a hold to perfect).
  void tick() {
    ticks++;
    if (enabled) HapticFeedback.selectionClick();
  }

  void reset() => _engaged = false;
}
