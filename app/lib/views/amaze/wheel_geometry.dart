import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'tool_slots.dart';

/// Default diameter of the tool wheel.
const kToolWheelDefaultDiameter = 320.0;

/// Smallest supported diameter of the tool wheel.
const kToolWheelMinDiameter = 240.0;

/// Largest supported diameter of the tool wheel.
const kToolWheelMaxDiameter = 480.0;

/// Angle trimmed from each end of a middle ring sector, in radians. It
/// leaves a visible gap between neighbouring adjustments.
const _adjustmentSectorGap = 0.04;

/// What a point on the tool wheel belongs to.
enum WheelHitType { slot, undo, redo, adjustment, center, ring, outside }

/// The result of [ToolWheelGeometry.hitTest].
@immutable
class WheelHit {
  const WheelHit._(this.type, {this.slot, this.adjustment});

  /// Tool slot [slot] (0 to 7).
  const WheelHit.slot(int slot) : this._(WheelHitType.slot, slot: slot);

  /// The middle ring segment of [adjustment].
  const WheelHit.adjustment(ToolAdjustment adjustment)
    : this._(WheelHitType.adjustment, adjustment: adjustment);

  static const undo = WheelHit._(WheelHitType.undo);
  static const redo = WheelHit._(WheelHitType.redo);
  static const center = WheelHit._(WheelHitType.center);

  /// Wheel background that no control owns.
  static const ring = WheelHit._(WheelHitType.ring);

  /// Beyond the wheel's rim.
  static const outside = WheelHit._(WheelHitType.outside);

  final WheelHitType type;
  final int? slot;
  final ToolAdjustment? adjustment;

  @override
  bool operator ==(Object other) {
    return other is WheelHit &&
        other.type == type &&
        other.slot == slot &&
        other.adjustment == adjustment;
  }

  @override
  int get hashCode => Object.hash(type, slot, adjustment);

  @override
  String toString() {
    return switch (type) {
      WheelHitType.slot => 'WheelHit.slot($slot)',
      WheelHitType.adjustment => 'WheelHit.adjustment(${adjustment?.name})',
      _ => 'WheelHit.${type.name}',
    };
  }
}

/// Part of a ring between two radii and two angles, centered on the
/// wheel's center.
@immutable
class WheelSector {
  const WheelSector({
    required this.innerRadius,
    required this.outerRadius,
    required this.startAngle,
    required this.sweepAngle,
  });

  final double innerRadius;
  final double outerRadius;

  /// Start angle in radians, clockwise from the positive x axis.
  final double startAngle;

  /// Angle covered by the sector in radians.
  final double sweepAngle;

  double get middleRadius => (innerRadius + outerRadius) / 2;

  double get width => outerRadius - innerRadius;

  /// Whether [fromCenter] lies inside the sector.
  bool contains(Offset fromCenter) {
    final distance = fromCenter.distance;
    if (distance < innerRadius || distance > outerRadius) return false;
    final angle = atan2(fromCenter.dy, fromCenter.dx);
    final delta = (angle - startAngle) % (2 * pi);
    return delta <= sweepAngle;
  }
}

/// Layout math for the three-ring tool wheel.
///
/// The outer ring has ten positions: the eight tool slots and, at the
/// bottom, undo and redo. The middle ring holds the adjustments and the
/// center shows the active color. Every size is proportional to [diameter];
/// the reference values are the ones at [kToolWheelDefaultDiameter].
@immutable
class ToolWheelGeometry {
  const ToolWheelGeometry({this.diameter = kToolWheelDefaultDiameter});

  /// Outer diameter of the wheel. The supported range is
  /// [kToolWheelMinDiameter] to [kToolWheelMaxDiameter].
  final double diameter;

  /// Scales a length given at the default diameter.
  double _scale(double reference) {
    return diameter * reference / kToolWheelDefaultDiameter;
  }

  double get radius => diameter / 2;

  /// Diameter of a tool slot.
  double get slotSize => _scale(46);

  /// Diameter of the undo and redo buttons.
  double get historySize => _scale(40);

  /// Distance from the center to the slots, undo and redo.
  double get slotDistance => _scale(130);

  /// Outer radius of the middle ring.
  double get middleRadius => _scale(104);

  /// Radius of the color disc in the center.
  double get centerRadius => _scale(30);

  /// Gap between the color disc and the middle ring.
  double get middleGap => _scale(6);

  /// Inner radius of the middle ring.
  double get middleInnerRadius => centerRadius + middleGap;

  /// Distance from the center to the adjustment buttons.
  double get adjustmentDistance => _scale(68);

  /// Size of an adjustment button.
  Size get adjustmentSize => Size(_scale(60), _scale(40));

  /// Angle of outer ring position [index] (0 to 9) in radians. Position 0 is
  /// at the bottom left and the positions continue clockwise.
  double ringAngle(int index) {
    return (108 + 36 * index) * pi / 180;
  }

  /// The 36° part of the outer band around position [index] (0 to 9).
  WheelSector ringSector(int index) {
    return WheelSector(
      innerRadius: middleRadius,
      outerRadius: radius,
      startAngle: ringAngle(index) - pi / 10,
      sweepAngle: pi / 5,
    );
  }

  /// Offset of [slot] (0 to 7) from the center.
  Offset slotCenter(int slot) => _polar(ringAngle(slot + 1), slotDistance);

  /// Offset of the undo button from the center.
  Offset get undoCenter => _polar(ringAngle(0), slotDistance);

  /// Offset of the redo button from the center.
  Offset get redoCenter => _polar(ringAngle(9), slotDistance);

  /// Angle of the middle ring segment of [adjustment] in radians.
  double adjustmentAngle(ToolAdjustment adjustment) {
    return (-90 + 120 * adjustment.index) * pi / 180;
  }

  /// The visible middle ring segment of [adjustment].
  WheelSector adjustmentSector(ToolAdjustment adjustment) {
    return WheelSector(
      innerRadius: middleInnerRadius,
      outerRadius: middleRadius,
      startAngle: adjustmentAngle(adjustment) - pi / 3 + _adjustmentSectorGap,
      sweepAngle: 2 * pi / 3 - 2 * _adjustmentSectorGap,
    );
  }

  /// Offset of the [adjustment] button from the center.
  Offset adjustmentCenter(ToolAdjustment adjustment) {
    return _polar(adjustmentAngle(adjustment), adjustmentDistance);
  }

  /// Every control on the wheel.
  List<WheelHit> get controls => [
    for (var slot = 0; slot < kToolSlotCount; slot++) WheelHit.slot(slot),
    WheelHit.undo,
    WheelHit.redo,
    for (final adjustment in ToolAdjustment.values)
      WheelHit.adjustment(adjustment),
    WheelHit.center,
  ];

  /// A point that belongs to [control].
  Offset controlCenter(WheelHit control) {
    return switch (control.type) {
      WheelHitType.slot => slotCenter(control.slot!),
      WheelHitType.undo => undoCenter,
      WheelHitType.redo => redoCenter,
      WheelHitType.adjustment => adjustmentCenter(control.adjustment!),
      _ => Offset.zero,
    };
  }

  /// Whether [fromCenter] lies inside the visible region of [control].
  bool controlContains(WheelHit control, Offset fromCenter) {
    bool inCircle(Offset center, double diameter) {
      return (fromCenter - center).distance <= diameter / 2;
    }

    return switch (control.type) {
      WheelHitType.slot => inCircle(slotCenter(control.slot!), slotSize),
      WheelHitType.undo => inCircle(undoCenter, historySize),
      WheelHitType.redo => inCircle(redoCenter, historySize),
      WheelHitType.adjustment => adjustmentSector(
        control.adjustment!,
      ).contains(fromCenter),
      WheelHitType.center => fromCenter.distance <= centerRadius,
      WheelHitType.ring =>
        _inRing(fromCenter) && hitTest(fromCenter) == control,
      WheelHitType.outside => !_inRing(fromCenter),
    };
  }

  bool _inRing(Offset fromCenter) => fromCenter.distance <= radius;

  /// What the point [fromCenter] (relative to the wheel's center) belongs
  /// to. Slots, undo and redo only own their visible circle; adjustments own
  /// their whole visible middle ring segment.
  WheelHit hitTest(Offset fromCenter) {
    if (!_inRing(fromCenter)) return WheelHit.outside;
    for (final control in controls) {
      if (controlContains(control, fromCenter)) return control;
    }
    return WheelHit.ring;
  }
}

Offset _polar(double angle, double distance) {
  return Offset(cos(angle), sin(angle)) * distance;
}
