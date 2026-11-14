import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:butterfly/models/marker_palette.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hue families, clockwise from 12 o'clock.
const kMarkerHueFamilies = [
  'YR',
  'E',
  'Y',
  'YG',
  'G',
  'BG',
  'B',
  'BV',
  'V',
  'RV',
  'R',
];

/// Gray families, clockwise from 9 o'clock.
const kMarkerGrayFamilies = ['W', 'C', 'N', 'T'];

/// Fluorescent families, clockwise from 3 o'clock.
const _fluorescentOrder = ['FRV', 'FYR', 'FY', 'FYG', 'FG', 'FBG', 'FB', 'FV'];

/// Smallest short side of a swatch, in logical pixels.
const kMarkerMinSwatchSide = 28.0;

/// Smallest font size of the code painted on a swatch.
const kMarkerMinLabelSize = 9.0;

/// Inner radius of the gray ring, in tool wheel radii, when there is room.
const kMarkerRingRatio = 3.0;

/// Preference holding the wheel's angle in radians.
const kAmazeColorAnglePreference = 'amaze.color.angle';

Future<double> loadAmazeColorAngle({SharedPreferences? preferences}) async {
  final prefs = preferences ?? await SharedPreferences.getInstance();
  final angle = prefs.getDouble(kAmazeColorAnglePreference) ?? 0;
  return angle.isFinite ? angle : 0;
}

Future<void> saveAmazeColorAngle(
  double angle, {
  SharedPreferences? preferences,
}) async {
  final prefs = preferences ?? await SharedPreferences.getInstance();
  await prefs.setDouble(kAmazeColorAnglePreference, angle % (2 * math.pi));
}

/// [angle] wrapped to -π..π.
double wrapAngle(double angle) {
  final wrapped = (angle + math.pi) % (2 * math.pi) - math.pi;
  return wrapped == -math.pi ? math.pi : wrapped;
}

/// One swatch: an annular sector around the wheel's center, before the
/// wheel's rotation. Angles are in radians in screen coordinates (0 is
/// right, angles grow clockwise).
class MarkerSwatchGeometry {
  MarkerSwatchGeometry(
    this.marker,
    this.innerRadius,
    this.outerRadius,
    this.start,
    this.sweep,
  );

  final MarkerColor marker;
  final double innerRadius;
  final double outerRadius;
  final double start;
  final double sweep;

  double get midAngle => start + sweep / 2;

  double get midRadius => (innerRadius + outerRadius) / 2;

  /// Center of the swatch relative to the wheel's center.
  Offset get center => Offset.fromDirection(midAngle, midRadius);

  /// The smaller of the radial length and the width of the inner edge.
  double get shortSide => math.min(
    outerRadius - innerRadius,
    2 * innerRadius * math.sin(sweep / 2),
  );

  /// Whether the polar point is inside the swatch.
  bool containsPolar(double radius, double angle) {
    if (radius < innerRadius || radius > outerRadius) return false;
    return (angle - start) % (2 * math.pi) <= sweep;
  }

  /// Whether this swatch and [other] share any area.
  bool overlaps(MarkerSwatchGeometry other) {
    if (innerRadius >= other.outerRadius || other.innerRadius >= outerRadius) {
      return false;
    }
    final offset = (other.start - start) % (2 * math.pi);
    return offset < sweep || offset > 2 * math.pi - other.sweep;
  }

  late final Path path = Path()
    ..arcTo(
      Rect.fromCircle(center: Offset.zero, radius: outerRadius),
      start,
      sweep,
      true,
    )
    ..arcTo(
      Rect.fromCircle(center: Offset.zero, radius: innerRadius),
      start + sweep,
      -sweep,
      false,
    )
    ..close();

  /// Points whose convex hull covers the swatch, for a wheel at [center]
  /// turned by [rotation].
  List<Offset> hull(Offset center, double rotation) {
    final a = start + rotation;
    // The outer arc bulges past the chord between samples; the samples
    // are pushed out to cover it.
    const samples = 4;
    final outer = outerRadius / math.cos(sweep / (2 * samples));
    return [
      center + Offset.fromDirection(a, innerRadius),
      center + Offset.fromDirection(a + sweep, innerRadius),
      for (var i = 0; i <= samples; i++)
        center + Offset.fromDirection(a + sweep * i / samples, outer),
    ];
  }
}

/// The fixed radial layout of every marker color, shared by painting and
/// hit testing. Its radii are multiples of the tool wheel's radius.
///
/// The gray families form a ring whose inner edge is [ringRatio] tool wheel
/// radii out; their darkest shades are thicker. Fluorescent and other
/// non-hue colors form a thinner arc just inside it. Each hue family is a
/// block of radial columns outside the ring, one column per first digit of
/// the code, with the darkest color nearest the center.
class MarkerRingGeometry {
  MarkerRingGeometry(
    MarkerPalette palette, {
    this.innerRadius = 160,
    this.ringRatio = kMarkerRingRatio,
    this.spread = 1,
  }) {
    _layoutRing(palette);
    _layoutInnerArc(palette);
    _layoutBars(palette);
  }

  /// Radius of the tool wheel the colors are drawn around.
  final double innerRadius;

  /// Inner radius of the gray ring in tool wheel radii.
  final double ringRatio;

  /// How deep swatches are: 1 for the full size, 0 for the smallest.
  final double spread;

  final List<MarkerSwatchGeometry> swatches = [];

  /// The hue families of the palette, clockwise.
  final List<String> families = [];

  /// Start angle and sweep of each hue family's block.
  final Map<String, (double, double)> familySpans = {};

  /// Inner and outer radius of the thin segments of the gray ring.
  late final double ringInner = ringRatio * innerRadius;
  late final double ringOuter = ringInner + _ringDepth;

  /// Radius inside which nothing is drawn but the light disc.
  late double discInner = ringInner - _thickExtra;

  late final double barInner = ringOuter + 4;

  /// Radius of the outermost swatch edge.
  double outerRadius = 0;

  /// Start, sweep and outer radius of each column of bars.
  final List<(double, double, double)> _columns = [];

  static const _gap = 1.5;
  static const _depth = kMarkerMinSwatchSide;

  /// Space between family groups, in swatch widths.
  static const _groupGap = 0.5;

  double get _ringDepth =>
      lerpDouble(_depth, math.max(_depth, 0.25 * innerRadius), spread)!;

  /// How far the darkest grays reach inside the ring.
  double get _thickExtra => 0.4 * _ringDepth;

  /// Radial distance between neighbors in a column of bars.
  double get _barPitch => lerpDouble(
    _depth + _gap,
    math.max(_depth + _gap, 0.36 * innerRadius),
    spread,
  )!;

  /// The smallest gray ring, in tool wheel radii, that leaves room for the
  /// controls inside it and 28 px wide columns outside it.
  static double minRingRatio(double innerRadius) => math.min(
    kMarkerRingRatio,
    math.max(innerRadius + 200, 330) / innerRadius,
  );

  void _layoutRing(MarkerPalette palette) {
    final groups = [
      for (final family in kMarkerGrayFamilies)
        if (palette.byFamily(family).isNotEmpty)
          _sortedGrays(palette.byFamily(family)),
    ];
    outerRadius = ringOuter;
    if (groups.isEmpty) return;
    final count = groups.fold(0, (sum, group) => sum + group.length);
    final unit = 2 * math.pi / (count + groups.length * _groupGap);
    final sweep = unit - _gap / ringInner;
    var angle = math.pi + unit * _groupGap / 2;
    for (final group in groups) {
      for (final marker in group) {
        final thick = _grayRank(marker) >= 6;
        swatches.add(
          MarkerSwatchGeometry(
            marker,
            thick ? ringInner - _thickExtra : ringInner,
            ringOuter,
            angle,
            sweep,
          ),
        );
        angle += unit;
      }
      angle += unit * _groupGap;
    }
  }

  static int _grayRank(MarkerColor marker) {
    final digits = marker.code.split('-').last;
    if (digits.length > 1 && int.tryParse(digits) == 0) return -1;
    return int.tryParse(digits) ?? 0;
  }

  /// Grays from the lightest (`-00`, `-0`) to the darkest (`-10`).
  static List<MarkerColor> _sortedGrays(List<MarkerColor> colors) {
    final indexed = colors.indexed.toList()
      ..sort((a, b) {
        final byRank = _grayRank(a.$2).compareTo(_grayRank(b.$2));
        return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
      });
    return [for (final (_, marker) in indexed) marker];
  }

  /// Fluorescents clockwise from 3 o'clock, with the remaining colors
  /// (`0`, `100`, `110`) before them.
  void _layoutInnerArc(MarkerPalette palette) {
    bool inner(String family) =>
        !kMarkerHueFamilies.contains(family) &&
        !kMarkerGrayFamilies.contains(family);
    int order(MarkerColor marker) {
      final index = _fluorescentOrder.indexOf(marker.family);
      return index < 0 ? _fluorescentOrder.length : index;
    }

    final fluorescent = <MarkerColor>[];
    final rest = <MarkerColor>[];
    for (final marker in palette.colors) {
      if (!inner(marker.family)) continue;
      (marker.family.startsWith('F') ? fluorescent : rest).add(marker);
    }
    if (fluorescent.isEmpty && rest.isEmpty) return;
    final sorted = fluorescent.indexed.toList()
      ..sort((a, b) {
        final byOrder = order(a.$2).compareTo(order(b.$2));
        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    final outer = ringInner - _thickExtra - 6;
    discInner = outer - _depth;
    final count = fluorescent.length + rest.length;
    final unit = math.min(math.pi / 15, 2 * math.pi / (count + 1));
    final sweep = unit - _gap / discInner;
    var angle = -(rest.length + _groupGap) * unit;
    for (final marker in rest.reversed) {
      swatches.add(
        MarkerSwatchGeometry(marker, discInner, outer, angle, sweep),
      );
      angle += unit;
    }
    angle = 0;
    for (final (_, marker) in sorted) {
      swatches.add(
        MarkerSwatchGeometry(marker, discInner, outer, angle, sweep),
      );
      angle += unit;
    }
  }

  void _layoutBars(MarkerPalette palette) {
    final blocks = <String, List<List<MarkerColor>>>{};
    for (final family in kMarkerHueFamilies) {
      final colors = palette.byFamily(family);
      if (colors.isEmpty) continue;
      final columns = <String, List<MarkerColor>>{};
      for (final marker in colors) {
        final digits = _digits(marker);
        final key = digits.isEmpty ? '' : digits[0];
        columns.putIfAbsent(key, () => []).add(marker);
      }
      final keys = columns.keys.toList()..sort();
      blocks[family] = [
        for (final key in keys)
          columns[key]!..sort((a, b) => _depthRank(a).compareTo(_depthRank(b))),
      ];
    }
    if (blocks.isEmpty) return;
    final columnCount = blocks.values.fold(0, (sum, b) => sum + b.length);
    final unit = 2 * math.pi / (columnCount + blocks.length * _groupGap);
    final sweep = unit - _gap / barInner;
    final pitch = _barPitch;
    var angle = -100 * math.pi / 180 + unit * _groupGap / 2;
    for (final MapEntry(key: family, value: columns) in blocks.entries) {
      families.add(family);
      familySpans[family] = (angle, unit * columns.length);
      for (final column in columns) {
        for (final (index, marker) in column.indexed) {
          final inner = barInner + index * pitch;
          swatches.add(
            MarkerSwatchGeometry(
              marker,
              inner,
              inner + pitch - _gap,
              angle,
              sweep,
            ),
          );
        }
        final outer = barInner + column.length * pitch - _gap;
        _columns.add((angle, sweep, outer));
        outerRadius = math.max(outerRadius, outer);
        angle += unit;
      }
      angle += unit * _groupGap;
    }
  }

  static String _digits(MarkerColor marker) {
    final code = marker.code;
    return code.startsWith(marker.family)
        ? code.substring(marker.family.length)
        : code;
  }

  /// Order within a column, from the center outwards: `…9` down to `…0`,
  /// then `00`, `000` and `0000`.
  static int _depthRank(MarkerColor marker) {
    final digits = _digits(marker);
    if (digits.length > 1 && int.tryParse(digits) == 0) return digits.length;
    final last = digits.length > 1 ? int.tryParse(digits.substring(1)) : 0;
    return -(last ?? 0);
  }

  MarkerSwatchGeometry? byCode(String code) {
    for (final swatch in swatches) {
      if (swatch.marker.code.toLowerCase() == code.toLowerCase()) return swatch;
    }
    return null;
  }

  /// The swatch under [local], a point relative to the wheel's center, with
  /// the wheel turned by [rotation].
  MarkerSwatchGeometry? hitTest(Offset local, {double rotation = 0}) {
    final radius = local.distance;
    if (radius < discInner || radius > outerRadius) return null;
    final angle = local.direction - rotation;
    for (final swatch in swatches) {
      if (swatch.containsPolar(radius, angle)) return swatch;
    }
    return null;
  }

  /// Whether [local] is on the color wheel: on the disc around the tool
  /// wheel, on the gray ring, or on a column of bars up to its tip.
  bool containsWheel(Offset local, {double rotation = 0}) {
    final radius = local.distance;
    if (radius < innerRadius) return false;
    if (radius <= ringOuter + 6) return true;
    final angle = local.direction - rotation;
    final pad = _groupGap * (_depth + _gap) / barInner;
    for (final (start, sweep, outer) in _columns) {
      if (radius <= outer + 6 &&
          (angle - start + pad) % (2 * math.pi) <= sweep + 2 * pad) {
        return true;
      }
    }
    return false;
  }

  /// Center of [swatch] on screen.
  Offset positionOf(
    MarkerSwatchGeometry swatch, {
    required Offset center,
    double rotation = 0,
  }) {
    return center +
        Offset.fromDirection(swatch.midAngle + rotation, swatch.midRadius);
  }

  static bool isOnScreen(
    MarkerSwatchGeometry swatch, {
    required Offset center,
    required Size screen,
    required double rotation,
  }) {
    for (final point in swatch.hull(center, rotation)) {
      if (point.dx < 0 ||
          point.dy < 0 ||
          point.dx > screen.width ||
          point.dy > screen.height) {
        return false;
      }
    }
    return true;
  }

  /// The rotation nearest to [from] at which [swatch] is fully on screen,
  /// or null if spinning alone cannot show it.
  static double? rotationToShow(
    MarkerSwatchGeometry swatch, {
    required Offset center,
    required Size screen,
    double from = 0,
  }) {
    const step = math.pi / 360;
    for (var i = 0; i <= 360; i++) {
      for (final rotation in [from + i * step, from - i * step]) {
        if (isOnScreen(
          swatch,
          center: center,
          screen: screen,
          rotation: rotation,
        )) {
          return rotation;
        }
      }
    }
    return null;
  }

  /// Whether every swatch can be brought fully on screen by spinning.
  bool allReachable({required Offset center, required Size screen}) {
    // Reachability only depends on a swatch's radii and sweep.
    final seen = <(double, double, double)>{};
    for (final swatch in swatches) {
      final shape = (swatch.innerRadius, swatch.outerRadius, swatch.sweep);
      if (!seen.add(shape)) continue;
      if (rotationToShow(swatch, center: center, screen: screen) == null) {
        return false;
      }
    }
    return true;
  }

  /// The layout for a tool wheel of [innerRadius] at [center] on [screen].
  ///
  /// It is the full-size layout if every swatch of it can be spun on
  /// screen. Otherwise the swatches get shallower, down to 28 px, and then
  /// the gray ring moves in, down to [minRingRatio]. If even that layout
  /// does not fit, it is returned anyway.
  static MarkerRingGeometry fit(
    MarkerPalette palette, {
    required double innerRadius,
    required Offset center,
    required Size screen,
  }) {
    final smallest = minRingRatio(innerRadius);
    final candidates = [
      for (final spread in const [1.0, 0.75, 0.5, 0.25, 0.0])
        (kMarkerRingRatio, spread),
      for (var ratio = kMarkerRingRatio - 0.1; ratio > smallest; ratio -= 0.1)
        (ratio, 0.0),
      (smallest, 0.0),
    ];
    late MarkerRingGeometry geometry;
    for (final (ratio, spread) in candidates) {
      geometry = MarkerRingGeometry(
        palette,
        innerRadius: innerRadius,
        ringRatio: ratio,
        spread: spread,
      );
      if (geometry.allReachable(center: center, screen: screen)) break;
    }
    return geometry;
  }

  /// Rotation of a swatch's code on screen when the swatch is at
  /// [screenAngle]: along the ring, flipped on the lower half so that it is
  /// never upside down.
  static double textRotation(double screenAngle) {
    final rotation = wrapAngle(screenAngle + math.pi / 2);
    if (rotation > math.pi / 2) return rotation - math.pi;
    if (rotation < -math.pi / 2) return rotation + math.pi;
    return rotation;
  }

  final Map<String, TextPainter> _labels = {};
  TextStyle? _labelBase;

  /// Font size of [swatch]'s code: as large as fits, from 9 to 11.
  static double labelSize(MarkerSwatchGeometry swatch) {
    final width = swatch.midRadius * swatch.sweep - 3;
    return (width / (0.62 * swatch.marker.code.length)).clamp(
      kMarkerMinLabelSize,
      11.0,
    );
  }

  /// [swatch]'s code laid out in [base], the app's label font. Labels are
  /// kept until [base] changes.
  TextPainter labelOf(MarkerSwatchGeometry swatch, [TextStyle? base]) {
    if (base != _labelBase) {
      dispose();
      _labelBase = base;
    }
    return _labels.putIfAbsent(swatch.marker.code, () {
      final color = swatch.marker.color;
      final dark = color.r * 299 + color.g * 587 + color.b * 114 > 145000;
      return TextPainter(
        text: TextSpan(
          text: swatch.marker.code,
          style: (base ?? const TextStyle()).copyWith(
            color: dark ? const Color(0xCC000000) : const Color(0xE6FFFFFF),
            fontSize: labelSize(swatch),
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
    });
  }

  void dispose() {
    for (final label in _labels.values) {
      label.dispose();
    }
    _labels.clear();
  }
}

/// Paints the whole wheel turned by [rotation] around [center]: a light
/// disc from [holeRadius] to the gray ring, then every swatch with its
/// code. The swatches with a code in [selected] are outlined.
class MarkerWheelPainter extends CustomPainter {
  const MarkerWheelPainter({
    required this.geometry,
    required this.center,
    required this.rotation,
    required this.selected,
    required this.discColor,
    required this.holeRadius,
    this.labelStyle,
  });

  final MarkerRingGeometry geometry;
  final Offset center;
  final double rotation;
  final Set<String> selected;
  final Color discColor;

  /// Radius left clear for the tool wheel, or 0.
  final double holeRadius;

  /// The font the codes are painted in; their size and color are set here.
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = (Offset.zero & size).inflate(
      geometry._barPitch + geometry._ringDepth,
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(
          Rect.fromCircle(center: Offset.zero, radius: geometry.ringOuter),
        )
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: holeRadius)),
      Paint()..color = discColor,
    );
    canvas.rotate(rotation);
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0x26000000);
    final outlined = <MarkerSwatchGeometry>[];
    for (final swatch in geometry.swatches) {
      final position = geometry.positionOf(
        swatch,
        center: center,
        rotation: rotation,
      );
      if (!visible.contains(position)) continue;
      fill.color = Color(swatch.marker.color.value);
      canvas.drawPath(swatch.path, fill);
      canvas.drawPath(swatch.path, edge);
      final label = geometry.labelOf(swatch, labelStyle);
      final local = swatch.center;
      canvas.save();
      canvas.translate(local.dx, local.dy);
      canvas.rotate(
        MarkerRingGeometry.textRotation(swatch.midAngle + rotation) - rotation,
      );
      label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
      canvas.restore();
      if (selected.contains(swatch.marker.code)) outlined.add(swatch);
    }
    for (final swatch in outlined) {
      canvas.drawPath(
        swatch.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = Colors.black,
      );
      canvas.drawPath(
        swatch.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MarkerWheelPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.center != center ||
      oldDelegate.geometry != geometry ||
      oldDelegate.discColor != discColor ||
      oldDelegate.holeRadius != holeRadius ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.selected.length != selected.length ||
      !oldDelegate.selected.containsAll(selected);
}
