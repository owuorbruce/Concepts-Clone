import 'dart:async';
import 'dart:ui';

/// How long the pointer must stay still for [HoldToPerfect].
const kHoldToPerfectDelay = Duration(milliseconds: 450);

/// How far, in screen pixels, the pointer may drift and still be still.
const kHoldToPerfectSlop = 4.0;

/// Fires [onHold] once when the pointer stays within [slop] screen pixels
/// for [delay] during a drag. Moving farther restarts the wait.
class HoldToPerfect {
  HoldToPerfect({
    required this.onHold,
    this.delay = kHoldToPerfectDelay,
    this.slop = kHoldToPerfectSlop,
  });

  final VoidCallback onHold;
  final Duration delay;
  final double slop;

  Timer? _timer;
  Offset? _anchor;
  bool _fired = false;

  /// Whether the hold fired during this drag.
  bool get fired => _fired;

  /// Call on every pointer move with its screen position.
  void move(Offset screen) {
    final anchor = _anchor;
    if (anchor != null && (screen - anchor).distance <= slop) {
      _timer ??= Timer(delay, _fire);
      return;
    }
    _anchor = screen;
    _timer?.cancel();
    _timer = Timer(delay, _fire);
  }

  void _fire() {
    _timer = null;
    if (_fired) return;
    _fired = true;
    onHold();
  }

  /// Stops waiting, for the end of a drag.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _anchor = null;
    _fired = false;
  }
}
