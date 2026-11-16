import 'dart:math';

import 'package:dart_leap/dart_leap.dart';

import '../models/area.dart';
import '../models/element.dart';
import '../models/point.dart';
import '../models/property.dart';
import 'svg_strokes.dart';

/// `extra` key of a wall: `{'thicknessIn': t, 'corners': [i0, i1, i2, i3]}`,
/// the indices of the rectangle's corners in the element's points.
const kWallExtraKey = 'amaze.wall';

/// `extra` key of every element of a placed door or window:
/// `{'kind': 'door' | 'window', 'widthIn': w, 'groupId': id}`.
const kOpeningExtraKey = 'amaze.opening';

/// `extra` key of a room fill: `{'id': id, 'name': name}`.
const kRoomExtraKey = 'amaze.room';

/// `extra` key of a room label; its value is the room's id.
const kRoomLabelExtraKey = 'amaze.roomLabel';

/// The default wall color.
const kDefaultWallColor = SRGBColor(0xff374151);

/// How far the corners of a valid wall may be from a rectangle, in canvas
/// units.
const kWallTolerance = 0.5;

/// A wall's centerline from [a] to [b] and its thickness.
///
/// A wall's rectangle reaches half its thickness past each end of the
/// centerline, so walls meeting at a corner overlap cleanly.
class WallGeometry {
  const WallGeometry(this.a, this.b, this.thicknessIn);

  final Point<double> a, b;
  final double thicknessIn;

  /// The thickness in canvas units.
  double get thickness => thicknessIn * kCanvasUnitsPerInch;

  /// The centerline length in canvas units.
  double get length => a.distanceTo(b);

  /// The angle of the centerline in radians.
  double get angle => atan2(b.y - a.y, b.x - a.x);

  /// The unit vector from [a] to [b].
  Point<double> get direction {
    final length = this.length;
    if (length == 0) return const Point(1, 0);
    return (b - a) * (1 / length);
  }

  /// The unit normal, a quarter turn from [direction].
  Point<double> get normal {
    final d = direction;
    return Point(-d.y, d.x);
  }

  /// The start of the wall's rectangle, half a thickness before [a].
  Point<double> get outerStart => a - direction * (thickness / 2);

  /// The end of the wall's rectangle, half a thickness past [b].
  Point<double> get outerEnd => b + direction * (thickness / 2);

  /// The full length of the wall's rectangle in canvas units.
  double get outerLength => length + thickness;
}

/// A wall around the centerline [a] → [b], [thicknessIn] inches thick: a
/// fill-only closed rectangle that reaches half the thickness past each
/// end, so L and T joints need no mitres.
PenElement makeWall(
  Point<double> a,
  Point<double> b,
  double thicknessIn,
  SRGBColor color,
) {
  final half = thicknessIn * kCanvasUnitsPerInch / 2;
  final length = a.distanceTo(b);
  final direction = length == 0
      ? const Point(1.0, 0.0)
      : (b - a) * (1 / length);
  return _wallRectangle(
    a - direction * half,
    b + direction * half,
    thicknessIn,
    color,
  );
}

/// A wall rectangle from [start] to [end], with flat ends there.
PenElement _wallRectangle(
  Point<double> start,
  Point<double> end,
  double thicknessIn,
  SRGBColor color,
) {
  final half = thicknessIn * kCanvasUnitsPerInch / 2;
  final length = start.distanceTo(end);
  final direction = length == 0
      ? const Point(1.0, 0.0)
      : (end - start) * (1 / length);
  final normal = Point(-direction.y, direction.x);
  final corners = [
    start - normal * half,
    end - normal * half,
    end + normal * half,
    start + normal * half,
  ];
  final points = <Point<double>>[];
  final indices = <int>[];
  for (var i = 0; i < 4; i++) {
    final side = resamplePoints([corners[i], corners[(i + 1) % 4]]);
    indices.add(points.length);
    // Each side starts at its corner; the last side ends on the first.
    points.addAll(side.take(side.length - 1));
  }
  points.add(corners.first);
  return PenElement(
    points: [for (final p in points) PathPoint(p.x, p.y, 1)],
    property: PenProperty(
      strokeWidth: 1,
      thinning: 0,
      smoothing: 0,
      streamline: 0,
      paint: const ElementPaint.solid(color: SRGBColor.transparent),
      fillPaint: ElementPaint.solid(color: color),
    ),
    extra: {
      kWallExtraKey: {'thicknessIn': thicknessIn, 'corners': indices},
    },
  );
}

/// The color a wall is filled with.
SRGBColor wallColor(PenElement wall) => switch (wall.property.fillPaint) {
  SolidElementPaint(:final color) => color,
  _ => kDefaultWallColor,
};

/// The corners of [element] if it is tagged as a wall and they form a
/// rectangle, else null.
List<Point<double>>? _wallCorners(PenElement element) {
  final tag = element.extra[kWallExtraKey];
  if (tag is! Map) return null;
  final indices = tag['corners'];
  if (indices is! List || indices.length != 4) return null;
  final corners = <Point<double>>[];
  for (final index in indices) {
    if (index is! int || index < 0 || index >= element.points.length) {
      return null;
    }
    final point = element.points[index];
    corners.add(Point(point.x, point.y));
  }
  bool same(double a, double b) => (a - b).abs() <= kWallTolerance;
  final side0 = corners[0].distanceTo(corners[1]);
  final side1 = corners[1].distanceTo(corners[2]);
  final side2 = corners[2].distanceTo(corners[3]);
  final side3 = corners[3].distanceTo(corners[0]);
  final diagonal0 = corners[0].distanceTo(corners[2]);
  final diagonal1 = corners[1].distanceTo(corners[3]);
  // Opposite sides equal and equal diagonals: a rectangle.
  if (!same(side0, side2) || !same(side1, side3)) return null;
  if (!same(diagonal0, diagonal1)) return null;
  if (side0 <= kWallTolerance || side1 <= kWallTolerance) return null;
  return corners;
}

/// The centerline and thickness of [element], or null if it isn't a valid
/// wall: a wall whose four corner points still form a rectangle.
///
/// The thickness is measured, so a scaled wall reports its new thickness.
/// The centerline is the rectangle's middle line, half a thickness in from
/// each end.
WallGeometry? readWall(PenElement element) {
  final corners = _wallCorners(element);
  if (corners == null) return null;
  final start = Point(
    (corners[0].x + corners[3].x) / 2,
    (corners[0].y + corners[3].y) / 2,
  );
  final end = Point(
    (corners[1].x + corners[2].x) / 2,
    (corners[1].y + corners[2].y) / 2,
  );
  final thickness = corners[1].distanceTo(corners[2]);
  final length = start.distanceTo(end);
  final direction = (end - start) * (1 / length);
  final inset = min(thickness / 2, length / 2);
  return WallGeometry(
    start + direction * inset,
    end - direction * inset,
    thickness / kCanvasUnitsPerInch,
  );
}

/// The pieces of [wall] left after removing the stretch from [fromIn] to
/// [toIn] inches, measured along its full outline from the start.
///
/// The pieces keep the wall's color and thickness, are valid walls, and
/// are flat on the cut side. A cut at an end leaves one piece; a wall that
/// isn't valid is returned unchanged.
List<PenElement> cutWall(PenElement wall, double fromIn, double toIn) {
  final geometry = readWall(wall);
  if (geometry == null) return [wall];
  final total = geometry.outerLength;
  final from = (min(fromIn, toIn) * kCanvasUnitsPerInch).clamp(0.0, total);
  final to = (max(fromIn, toIn) * kCanvasUnitsPerInch).clamp(0.0, total);
  final start = geometry.outerStart;
  final direction = geometry.direction;
  final color = wallColor(wall);
  PenElement piece(double begin, double end) => _wallRectangle(
    start + direction * begin,
    start + direction * end,
    geometry.thicknessIn,
    color,
  ).copyWith(collection: wall.collection, zoom: wall.zoom);
  return [
    if (from > kWallTolerance) piece(0, from),
    if (total - to > kWallTolerance) piece(to, total),
  ];
}
