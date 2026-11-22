import 'dart:math';
import 'dart:ui' as ui;

import 'package:butterfly_api/butterfly_api.dart';
import 'package:butterfly_api/butterfly_text.dart' as text;
import 'package:dart_leap/dart_leap.dart';
import 'package:material_ui/material_ui.dart';

import '../objects/object_placement.dart';
import '../objects/object_store.dart';

/// Canvas units per square foot.
const kCanvasUnitsPerSquareFoot =
    kCanvasUnitsPerInch * kCanvasUnitsPerInch * 144;

/// How far from a wall's centerline, past half its thickness, a tap still
/// places a door or window on it.
const kOpeningTapReachIn = 8.0;

/// Depth of the wall stub along the top of every pack door and window.
const kOpeningStubIn = 4.5;

/// Spacing of the points of a room outline, in canvas units.
const kRoomSampleSpacing = 6.0;

/// Alpha of a room fill.
const kRoomAlpha = 0.15;

/// The door or window waiting for a tap on a wall, if any.
final armedOpening = ValueNotifier<ObjectEntry?>(null);

/// Waits for a tap on a wall to place [entry].
void armOpening(ObjectEntry entry) => armedOpening.value = entry;

/// Stops waiting for a tap on a wall.
void disarmOpening() => armedOpening.value = null;

/// The `amaze.opening` facts of a pack object: its kind and width, or null
/// if it isn't a door or window.
({String kind, double widthIn})? openingOf(ButterflyComponent component) {
  for (final element in component.elements) {
    final tag = element.extra[kOpeningExtraKey];
    if (tag is! Map) continue;
    final kind = tag['kind'], width = tag['widthIn'];
    if (kind is String && width is num && width > 0) {
      return (kind: kind, widthIn: width.toDouble());
    }
  }
  return null;
}

/// [units] as feet and inches, for example `12' 6"`.
String formatFeetInches(double units) {
  var inches = (units.abs() / kCanvasUnitsPerInch).round();
  final feet = inches ~/ 12;
  inches %= 12;
  if (feet == 0) return '$inches"';
  return "$feet' $inches\"";
}

/// [units] square canvas units as square feet with one decimal.
String formatSquareFeet(double units) =>
    (units / kCanvasUnitsPerSquareFoot).toStringAsFixed(1);

Offset _offset(Point<double> p) => Offset(p.x, p.y);

/// How far a point may be from the line through its neighbors to be left
/// out of an outline, in canvas units.
const kOutlineTolerance = 0.05;

/// [points] without the points that lie on the line between their
/// neighbors, and without a closing point that repeats the first.
///
/// Walls and converted objects carry a point every few units for the
/// eraser; path operations fail on such long runs of collinear points.
List<Offset> simplifyOutline(List<Offset> points) {
  final input = [...points];
  if (input.length > 1 && (input.first - input.last).distance < 1e-9) {
    input.removeLast();
  }
  if (input.length < 4) return input;
  double distance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final length = ab.distance;
    if (length < 1e-12) return (p - a).distance;
    return ((p.dx - a.dx) * ab.dy - (p.dy - a.dy) * ab.dx).abs() / length;
  }

  final result = <Offset>[input.first];
  for (var i = 1; i < input.length; i++) {
    final next = input[(i + 1) % input.length];
    if (distance(input[i], result.last, next) > kOutlineTolerance) {
      result.add(input[i]);
    }
  }
  return result;
}

/// The closed outline of [element]'s points.
ui.Path elementOutline(PenElement element) => ui.Path()
  ..addPolygon(
    simplifyOutline([for (final p in element.points) Offset(p.x, p.y)]),
    true,
  );

/// The area enclosed by [polygon] (shoelace formula), in square units.
double polygonArea(List<Offset> polygon) {
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i], b = polygon[(i + 1) % polygon.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum.abs() / 2;
}

bool _polygonContains(List<Offset> polygon, Offset point) =>
    (ui.Path()..addPolygon(polygon, true)).contains(point);

/// Each contour of [path] as a polygon sampled every [kRoomSampleSpacing].
List<List<Offset>> pathContours(ui.Path path) {
  final contours = <List<Offset>>[];
  for (final metric in path.computeMetrics()) {
    final steps = max(3, (metric.length / kRoomSampleSpacing).ceil());
    final points = <Offset>[];
    for (var i = 0; i < steps; i++) {
      final tangent = metric.getTangentForOffset(metric.length * i / steps);
      if (tangent != null) points.add(tangent.position);
    }
    if (points.length >= 3) contours.add(points);
  }
  return contours;
}

bool _isWall(PadElement element) =>
    element is PenElement && element.extra[kWallExtraKey] is Map;

bool _isFilledOpening(PadElement element) {
  if (element is! PenElement || element.extra[kOpeningExtraKey] is! Map) {
    return false;
  }
  final points = element.points;
  final closed =
      points.length > 2 &&
      points.first.x == points.last.x &&
      points.first.y == points.last.y;
  return closed && element.property.fillPaint.previewColor.a > 0;
}

/// The union of every wall and every filled door or window part, so an
/// opening's wall stub closes the wall's gap.
ui.Path wallUnion(Iterable<PadElement> content) {
  ui.Path? union;
  for (final element in content) {
    if (!_isWall(element) && !_isFilledOpening(element)) continue;
    final outline = elementOutline(element as PenElement);
    if (union == null) {
      union = outline;
      continue;
    }
    try {
      union = ui.Path.combine(ui.PathOperation.union, union, outline);
    } on StateError catch (e) {
      // A degenerate outline is left out rather than failing the tap.
      debugPrint('Could not add a wall outline to the floor plan: $e');
    }
  }
  return union ?? ui.Path();
}

/// What a tap at [point] finds for a new room.
sealed class RoomSearch {
  const RoomSearch();
}

/// The tap is on a wall.
class OnWall extends RoomSearch {
  const OnWall();
}

/// No walls enclose the tap.
class NotEnclosed extends RoomSearch {
  const NotEnclosed();
}

/// The smallest area enclosed by walls around the tap.
class RoomFound extends RoomSearch {
  const RoomFound(this.polygon);

  final List<Offset> polygon;
}

/// The room around [point]: the smallest contour of the walls' union that
/// contains it.
RoomSearch findRoom(Iterable<PadElement> content, Offset point) {
  final union = wallUnion(content);
  if (union.contains(point)) return const OnWall();
  List<Offset>? best;
  var bestArea = double.infinity;
  for (final contour in pathContours(union)) {
    if (!_polygonContains(contour, point)) continue;
    final area = polygonArea(contour);
    if (area < bestArea) {
      best = contour;
      bestArea = area;
    }
  }
  return best == null ? const NotEnclosed() : RoomFound(best);
}

/// The number of rooms in [content].
int roomCount(Iterable<PadElement> content) =>
    content.where((e) => e.extra[kRoomExtraKey] is Map).length;

/// The room id of a room fill, or null.
String? roomIdOf(PadElement element) {
  final tag = element.extra[kRoomExtraKey];
  return tag is Map ? tag['id'] as String? : null;
}

/// The name of a room fill, or null.
String? roomNameOf(PadElement element) {
  final tag = element.extra[kRoomExtraKey];
  return tag is Map ? tag['name'] as String? : null;
}

/// The outline of a room fill.
List<Offset> roomPolygon(PenElement room) => [
  for (final p in room.points) Offset(p.x, p.y),
];

/// A room on [polygon]: a fill tinted with [color] at [kRoomAlpha] and a
/// centered label with [name] and [areaText] on a second line.
List<PadElement> makeRoom({
  required List<Offset> polygon,
  required SRGBColor color,
  required String name,
  required String areaText,
  String collection = '',
}) {
  final id = createUniqueId();
  final closed = [...polygon, polygon.first];
  final fill = PenElement(
    id: createUniqueId(),
    collection: collection,
    points: [for (final p in closed) PathPoint(p.dx, p.dy, 1)],
    property: PenProperty(
      strokeWidth: 1,
      thinning: 0,
      smoothing: 0,
      streamline: 0,
      paint: const ElementPaint.solid(color: SRGBColor.transparent),
      fillPaint: ElementPaint.solid(
        color: color.withValues(a: (kRoomAlpha * 255).round()),
      ),
    ),
    extra: {
      kRoomExtraKey: {'id': id, 'name': name},
    },
  );
  final bounds = polygon
      .skip(1)
      .fold(
        Rect.fromPoints(polygon.first, polygon.first),
        (rect, p) => rect.expandToInclude(Rect.fromPoints(p, p)),
      );
  // The label is sized to the room; its font is about 14 px before scale.
  final scale = (bounds.shortestSide / 300).clamp(1.0, 400.0);
  const fontSize = 14.0;
  final longest = max(name.length, areaText.length);
  final labelSize = Size(
    longest * fontSize * 0.55 * scale,
    2 * fontSize * 1.2 * scale,
  );
  final center = _centroid(polygon) ?? bounds.center;
  final label = TextElement(
    id: createUniqueId(),
    collection: collection,
    position: Point(
      center.dx - labelSize.width / 2,
      center.dy - labelSize.height / 2,
    ),
    scale: scale,
    foreground: color,
    area: text.TextArea(
      paragraph: text.TextParagraph(
        textSpans: [text.InlineSpan.text(text: '$name\n$areaText')],
      ),
    ),
    extra: {kRoomLabelExtraKey: id},
  );
  return [fill, label];
}

Offset? _centroid(List<Offset> polygon) {
  var area = 0.0, cx = 0.0, cy = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i], b = polygon[(i + 1) % polygon.length];
    final cross = a.dx * b.dy - b.dx * a.dy;
    area += cross;
    cx += (a.dx + b.dx) * cross;
    cy += (a.dy + b.dy) * cross;
  }
  if (area.abs() < 1e-9) return null;
  return Offset(cx / (3 * area), cy / (3 * area));
}

/// A valid wall near a tap, with where the tap falls on it.
class WallHit {
  const WallHit(this.wall, this.geometry, this.along, this.side);

  final PenElement wall;
  final WallGeometry geometry;

  /// The tap's distance along the centerline from its start, clamped to it.
  final double along;

  /// +1 if the tap is on the side of the wall's normal, else -1.
  final double side;
}

/// The nearest valid wall whose centerline is within half its thickness
/// plus [kOpeningTapReachIn] of [point].
WallHit? findWall(Iterable<PadElement> content, Offset point) {
  WallHit? best;
  var bestDistance = double.infinity;
  for (final element in content) {
    if (element is! PenElement) continue;
    final geometry = readWall(element);
    if (geometry == null || geometry.length <= 0) continue;
    final a = _offset(geometry.a);
    final direction = _offset(geometry.direction);
    final normal = _offset(geometry.normal);
    final relative = point - a;
    final along = (relative.dx * direction.dx + relative.dy * direction.dy)
        .clamp(0.0, geometry.length);
    final closest = a + direction * along;
    final distance = (point - closest).distance;
    final reach =
        geometry.thickness / 2 + kOpeningTapReachIn * kCanvasUnitsPerInch;
    if (distance > reach || distance >= bestDistance) continue;
    final offset = relative.dx * normal.dx + relative.dy * normal.dy;
    best = WallHit(element, geometry, along, offset < 0 ? -1 : 1);
    bestDistance = distance;
  }
  return best;
}

/// The wall pieces and the door or window elements for [entry] placed in a
/// gap of [widthIn] on [hit]: the gap is centered on the tap, clamped to the
/// wall; the object turns with the wall and its swing faces the tapped
/// side. Every opening element gets the same `groupId`.
List<PadElement> placeOpening(
  ObjectEntry entry,
  WallHit hit,
  double widthIn,
  String kind,
) {
  final geometry = hit.geometry;
  final width = min(widthIn * kCanvasUnitsPerInch, geometry.length);
  final center = hit.along.clamp(width / 2, geometry.length - width / 2);
  final half = geometry.thickness / 2;
  final pieces = cutWall(
    hit.wall,
    (half + center - width / 2) / kCanvasUnitsPerInch,
    (half + center + width / 2) / kCanvasUnitsPerInch,
  ).map((e) => e.copyWith(id: createUniqueId()));

  // The object is drawn around (0, 0) with its wall stub along the top.
  final placed = placeComponentAt(entry.component, Offset.zero);
  final bounds = _bounds(placed);
  final stub = Offset(
    0,
    (bounds?.top ?? 0) + kOpeningStubIn * kCanvasUnitsPerInch / 2,
  );
  final origin = _offset(geometry.a) + _offset(geometry.direction) * center;
  final angle = geometry.angle;
  final c = cos(angle), s = sin(angle);
  Offset transform(Offset local) {
    var p = local - stub;
    // The swing opens toward local +y; mirror it to the tapped side.
    if (hit.side < 0) p = Offset(p.dx, -p.dy);
    return origin + Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
  }

  final groupId = createUniqueId();
  final opening = [
    for (final element in placed)
      _transformElement(element, transform)?.copyWith(
            id: createUniqueId(),
            extra: {
              ...element.extra,
              kOpeningExtraKey: {
                'kind': kind,
                'widthIn': widthIn,
                'groupId': groupId,
              },
            },
          ) ??
          element,
  ];
  return [...pieces, ...opening];
}

Rect? _bounds(List<PadElement> elements) {
  Rect? result;
  for (final element in elements) {
    if (element is! PenElement) continue;
    for (final p in element.points) {
      final r = Rect.fromLTWH(p.x, p.y, 0, 0);
      result = result?.expandToInclude(r) ?? r;
    }
  }
  return result;
}

PadElement? _transformElement(
  PadElement element,
  Offset Function(Offset) transform,
) {
  if (element is! PenElement) return null;
  return element.copyWith(
    points: [
      for (final p in element.points)
        () {
          final moved = transform(Offset(p.x, p.y));
          return PathPoint(moved.dx, moved.dy, p.pressure);
        }(),
    ],
  );
}

/// The result of combining or subtracting two rooms.
sealed class RoomMerge {
  const RoomMerge();
}

/// The outlines of the rooms left.
class MergedRooms extends RoomMerge {
  const MergedRooms(this.polygons);

  final List<List<Offset>> polygons;
}

/// The result would have a hole.
class MergeWithHole extends RoomMerge {
  const MergeWithHole();
}

/// [first] combined with ([subtract] false) or minus ([subtract] true)
/// [second]. Each outer contour of the result is a room.
RoomMerge mergeRooms(
  PenElement first,
  PenElement second, {
  required bool subtract,
}) {
  final ui.Path result;
  try {
    result = ui.Path.combine(
      subtract ? ui.PathOperation.difference : ui.PathOperation.union,
      elementOutline(first),
      elementOutline(second),
    );
  } on StateError {
    return const MergedRooms([]);
  }
  final contours = pathContours(result)
      .where((c) => polygonArea(c) > kRoomSampleSpacing * kRoomSampleSpacing);
  final list = contours.toList();
  for (final contour in list) {
    for (final other in list) {
      if (identical(contour, other)) continue;
      if (_polygonContains(other, contour.first)) return const MergeWithHole();
    }
  }
  return MergedRooms(list);
}

/// Whether [element] is a room fill.
bool isRoomFill(PadElement element) =>
    element is PenElement && roomIdOf(element) != null;

/// The changes that combine [first] and [second], or subtract [second]
/// from [first], as one `ElementsChanged` map: [first] becomes the new room
/// or rooms with their labels, and [second] and both old labels go.
///
/// New rooms keep [first]'s name; when a subtraction leaves two pieces,
/// the others get the next room numbers from [roomName]. Returns null if
/// the result would have a hole or nothing is left.
Map<String, List<PadElement>>? mergeRoomChanges({
  required Iterable<PadElement> content,
  required PenElement first,
  required PenElement second,
  required bool subtract,
  required String Function(int number) roomName,
  required String Function(String area) areaText,
}) {
  final firstId = first.id, secondId = second.id;
  if (firstId == null || secondId == null) return null;
  final merged = mergeRooms(first, second, subtract: subtract);
  if (merged is! MergedRooms || merged.polygons.isEmpty) return null;
  final color = switch (first.property.fillPaint) {
    SolidElementPaint(:final color) => color.withValues(a: 255),
    _ => kDefaultWallColor,
  };
  final name = roomNameOf(first) ?? roomName(roomCount(content) + 1);
  var next = roomCount(content) + 1;
  final rooms = <PadElement>[];
  for (final (index, polygon) in merged.polygons.indexed) {
    rooms.addAll(
      makeRoom(
        polygon: polygon,
        color: color,
        name: index == 0 ? name : roomName(next++),
        areaText: areaText(formatSquareFeet(polygonArea(polygon))),
        collection: first.collection,
      ),
    );
  }
  final roomIds = {roomIdOf(first), roomIdOf(second)};
  return {
    firstId: rooms,
    secondId: const [],
    for (final element in content)
      if (element.id case final id?
          when roomIds.contains(element.extra[kRoomLabelExtraKey]))
        id: const [],
  };
}
