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

/// Start of slot 0 in degrees (screen coordinates: 0° is right, angles grow
/// clockwise).
const _slotStartDegrees = 210.0;

/// Angle covered by one slot wedge in degrees.
const _slotSweepDegrees = 37.5;

/// Angle covered by one adjustment sector of the center disc in degrees.
const _adjustmentSweepDegrees = 120.0;

/// Center angles of the adjustment sectors in degrees.
const _adjustmentDegrees = {
  ToolAdjustment.size: 270.0,
  ToolAdjustment.opacity: 30.0,
  ToolAdjustment.smoothing: 150.0,
};

double _radians(double degrees) => degrees * pi / 180;

/// [angle] in degrees, normalized to 0 (inclusive) to 360 (exclusive).
double _normalizedDegrees(double angle) => (angle * 180 / pi) % 360;

/// What a point on the tool wheel belongs to.
enum WheelHitType { slot, undo, redo, adjustment, center, ring, outside }

/// The result of [ToolWheelGeometry.hitTest].
@immutable
class WheelHit {
  const WheelHit._(this.type, {this.slot, this.adjustment});

  /// Tool slot [slot] (0 to 7).
  const WheelHit.slot(int slot) : this._(WheelHitType.slot, slot: slot);

  /// The center disc sector of [adjustment].
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

  double get middleAngle => startAngle + sweepAngle / 2;

  /// The point halfway through the sector, relative to the center.
  Offset get middle => polarOffset(middleAngle, middleRadius);

  /// The outline of the sector around [center].
  Path toPath(Offset center) {
    final outer = Rect.fromCircle(center: center, radius: outerRadius);
    final inner = Rect.fromCircle(center: center, radius: innerRadius);
    return Path()
      ..arcTo(outer, startAngle, sweepAngle, true)
      ..arcTo(inner, startAngle + sweepAngle, -sweepAngle, false)
      ..close();
  }
}

/// The point at [angle] (radians) and [distance] from the center.
Offset polarOffset(double angle, double distance) {
  return Offset(cos(angle), sin(angle)) * distance;
}

/// Layout math for the tool wheel.
///
/// The outer band holds eight wedge slots covering 300° clockwise from the
/// upper left, leaving a 60° gap on the left for undo and redo. The center
/// disc holds the size, opacity and smoothing sectors around the color dot.
/// Every length is a fraction of [radius], so the layout scales with
/// [diameter].
@immutable
class ToolWheelGeometry {
  const ToolWheelGeometry({this.diameter = kToolWheelDefaultDiameter});

  /// Outer diameter of the wheel. The supported range is
  /// [kToolWheelMinDiameter] to [kToolWheelMaxDiameter].
  final double diameter;

  double get radius => diameter / 2;

  /// Inner radius of the slot wedges.
  double get wedgeInnerRadius => radius * 0.60;

  /// Radius of the center disc.
  double get discRadius => radius * 0.57;

  /// Inner radius of the adjustment sectors.
  double get adjustmentInnerRadius => radius * 0.23;

  /// Radius of the color dot in the center.
  double get centerRadius => radius * 0.20;

  /// Radius of the undo and redo buttons.
  double get historyRadius => radius * 0.12;

  /// Distance from the center to the undo and redo buttons.
  double get historyDistance => radius * 0.80;

  /// Distance from the center to a wedge's icon.
  double get wedgeIconDistance => radius * 0.78;

  /// Distance from the center to a wedge's size number.
  double get wedgeLabelDistance => radius * 0.92;

  /// Start angle of [slot] (0 to 7) in radians. Slot 0 is at the upper left
  /// and the slots continue clockwise.
  double slotStartAngle(int slot) {
    return _radians(_slotStartDegrees + _slotSweepDegrees * slot);
  }

  /// The wedge of [slot] (0 to 7).
  WheelSector slotSector(int slot) {
    return WheelSector(
      innerRadius: wedgeInnerRadius,
      outerRadius: radius,
      startAngle: slotStartAngle(slot),
      sweepAngle: _radians(_slotSweepDegrees),
    );
  }

  /// Offset of the icon of [slot] from the center.
  Offset slotIconCenter(int slot) {
    return polarOffset(slotSector(slot).middleAngle, wedgeIconDistance);
  }

  /// Offset of the size number of [slot] from the center.
  Offset slotLabelCenter(int slot) {
    return polarOffset(slotSector(slot).middleAngle, wedgeLabelDistance);
  }

  /// Offset of the undo button from the center.
  Offset get undoCenter => polarOffset(_radians(195), historyDistance);

  /// Offset of the redo button from the center.
  Offset get redoCenter => polarOffset(_radians(165), historyDistance);

  /// Center angle of the sector of [adjustment] in radians.
  double adjustmentAngle(ToolAdjustment adjustment) {
    return _radians(_adjustmentDegrees[adjustment]!);
  }

  /// The center disc sector of [adjustment].
  WheelSector adjustmentSector(ToolAdjustment adjustment) {
    final sweep = _radians(_adjustmentSweepDegrees);
    return WheelSector(
      innerRadius: adjustmentInnerRadius,
      outerRadius: discRadius,
      startAngle: adjustmentAngle(adjustment) - sweep / 2,
      sweepAngle: sweep,
    );
  }

  /// Offset of the label of [adjustment] from the center.
  Offset adjustmentLabelCenter(ToolAdjustment adjustment) {
    return adjustmentSector(adjustment).middle;
  }

  /// The slot whose wedge covers [angle] (radians), or null in the gap.
  int? _slotAt(double angle) {
    final relative = (_normalizedDegrees(angle) - _slotStartDegrees) % 360;
    final slot = relative ~/ _slotSweepDegrees;
    return slot < kToolSlotCount ? slot : null;
  }

  /// The adjustment whose sector covers [angle] (radians).
  ToolAdjustment _adjustmentAt(double angle) {
    final degrees = _normalizedDegrees(angle);
    for (final MapEntry(key: adjustment, value: center)
        in _adjustmentDegrees.entries) {
      final start = center - _adjustmentSweepDegrees / 2;
      final relative = (degrees - start) % 360;
      if (relative < _adjustmentSweepDegrees) return adjustment;
    }
    // The sectors cover the full circle; rounding can only land on an edge.
    return ToolAdjustment.size;
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
      WheelHitType.slot => slotSector(control.slot!).middle,
      WheelHitType.undo => undoCenter,
      WheelHitType.redo => redoCenter,
      WheelHitType.adjustment => adjustmentLabelCenter(control.adjustment!),
      _ => Offset.zero,
    };
  }

  /// Whether [fromCenter] lies inside the region of [control].
  bool controlContains(WheelHit control, Offset fromCenter) {
    final distance = fromCenter.distance;
    final angle = atan2(fromCenter.dy, fromCenter.dx);
    bool inCircle(Offset center) {
      return (fromCenter - center).distance <= historyRadius;
    }

    return switch (control.type) {
      WheelHitType.slot =>
        distance >= wedgeInnerRadius &&
            distance <= radius &&
            _slotAt(angle) == control.slot,
      WheelHitType.undo => inCircle(undoCenter),
      WheelHitType.redo => inCircle(redoCenter),
      WheelHitType.adjustment =>
        distance >= adjustmentInnerRadius &&
            distance <= discRadius &&
            _adjustmentAt(angle) == control.adjustment,
      WheelHitType.center => distance <= centerRadius,
      WheelHitType.ring => distance <= radius && hitTest(fromCenter) == control,
      WheelHitType.outside => distance > radius,
    };
  }

  /// What the point [fromCenter] (relative to the wheel's center) belongs
  /// to. Slots own their whole wedge, adjustments their whole disc sector,
  /// undo and redo their circle and the center its dot. Everything else
  /// inside the outer circle, including the gap, is [WheelHit.ring].
  WheelHit hitTest(Offset fromCenter) {
    if (fromCenter.distance > radius) return WheelHit.outside;
    for (final control in controls) {
      if (controlContains(control, fromCenter)) return control;
    }
    return WheelHit.ring;
  }
}
