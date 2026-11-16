import 'dart:math';

import '../models/element.dart';
import '../models/page.dart';
import '../models/property.dart';

/// Namespaced key in [PadElement.extra] that marks a line [ShapeElement] as a
/// connector between two other shapes.
///
/// A connector is stored as an ordinary line shape so that documents remain
/// readable by older versions (they simply see a straight line) and so that
/// selection, styling, deletion and rendering reuse the existing pipeline.
///
/// All integrity rules live in this file and are shared by every document
/// operation that creates, copies, changes or removes elements:
///
/// * [ConnectorReference.tryParse] validates stored references.
/// * [isConnectableShape] validates endpoint types and geometry.
/// * [ConnectorIndex] resolves endpoints and detects duplicate/ambiguous ids.
/// * [remapElementIds] / [regenerateElementIds] perform bulk id remapping and
///   detach partially copied connectors.
/// * [invalidatedConnectors] / [pruneInvalidatedConnectors] find connectors
///   whose endpoints were removed or became unsupported by an operation.
/// * [completeConnectorChanges] keeps connectors consistent when elements
///   change and reports which connectors it touched.
/// * [resolveCreatedIdCollisions] renames created elements whose ids are
///   already in use, so creation never makes a reference ambiguous.
///
/// None of these are applied while loading a file, so existing documents are
/// never modified just by opening them.
const kConnectorExtraKey = 'butterfly.connector';

/// Stable references from a connector to the IDs of the shapes it connects.
final class ConnectorReference {
  final String from;
  final String to;

  const ConnectorReference(this.from, this.to);

  Map<String, dynamic> toJson() => {'from': from, 'to': to};

  /// Returns null for anything that is not a well-formed reference.
  static ConnectorReference? tryParse(Object? json) {
    if (json is! Map) return null;
    final from = json['from'];
    final to = json['to'];
    if (from is! String || to is! String) return null;
    if (from.isEmpty || to.isEmpty || from == to) return null;
    return ConnectorReference(from, to);
  }

  bool references(String id) => from == id || to == id;

  @override
  bool operator ==(Object other) =>
      other is ConnectorReference && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'ConnectorReference($from -> $to)';
}

/// Whether [element] is a supported connector endpoint: a non-line shape with
/// an id, a non-degenerate size and a finite transform. Rectangles (including
/// rounded corners), circles/ellipses and triangles are supported with any
/// rotation and shear.
bool isConnectableShape(PadElement element) {
  if (element is! ShapeElement || element.id == null) return false;
  final shape = element.property.shape;
  if (shape is! RectangleShape &&
      shape is! CircleShape &&
      shape is! TriangleShape) {
    return false;
  }
  final width = (element.secondPosition.x - element.firstPosition.x).abs();
  final height = (element.secondPosition.y - element.firstPosition.y).abs();
  return width > 0 &&
      height > 0 &&
      width.isFinite &&
      height.isFinite &&
      element.rotation.isFinite &&
      element.shear.isFinite;
}

extension PadElementConnectorExtension on PadElement {
  /// The connector reference if this element is a well-formed connector.
  /// This does not check whether its endpoints exist; see [ConnectorIndex].
  ConnectorReference? get connector {
    final element = this;
    if (element is! ShapeElement) return null;
    if (element.property.shape is! LineShape) return null;
    return ConnectorReference.tryParse(element.extra[kConnectorExtraKey]);
  }

  bool get isConnector => connector != null;

  /// Whether this element can be an endpoint of a connector.
  bool get isConnectable => isConnectableShape(this);
}

extension ShapeElementConnectorExtension on ShapeElement {
  /// Returns a copy with the connector metadata replaced, preserving all other
  /// metadata in [extra].
  ShapeElement withConnector(ConnectorReference? reference) {
    final next = Map<String, dynamic>.of(extra);
    if (reference == null) {
      next.remove(kConnectorExtraKey);
    } else {
      next[kConnectorExtraKey] = reference.toJson();
    }
    return copyWith(extra: next);
  }
}

/// Removes connector metadata from [element] if it has any.
PadElement detachConnector(PadElement element) =>
    element is ShapeElement && element.extra.containsKey(kConnectorExtraKey)
    ? element.withConnector(null)
    : element;

/// Lookup of the elements of a page (or any element collection) by id.
///
/// Ids that occur more than once are *ambiguous*: a connector can never
/// resolve to them, so it is never silently attached to the wrong object.
class ConnectorIndex {
  final Map<String, PadElement> _unique = {};
  final Set<String> ambiguousIds = {};

  ConnectorIndex(Iterable<PadElement> elements) {
    for (final element in elements) {
      final id = element.id;
      if (id == null || ambiguousIds.contains(id)) continue;
      if (_unique.remove(id) != null) {
        ambiguousIds.add(id);
      } else {
        _unique[id] = element;
      }
    }
  }

  PadElement? operator [](String id) => _unique[id];

  /// The supported endpoint shape for [id], or null if missing, ambiguous or
  /// unsupported.
  ShapeElement? endpoint(String id) {
    final element = _unique[id];
    return element is ShapeElement && element.isConnectable ? element : null;
  }

  /// Whether [connector] is a connector whose endpoints both resolve.
  bool isValid(PadElement connector) {
    final reference = connector.connector;
    return reference != null &&
        endpoint(reference.from) != null &&
        endpoint(reference.to) != null;
  }
}

/// Returns ids that occur more than once in [elements].
Set<String> findDuplicateIds(Iterable<PadElement> elements) =>
    ConnectorIndex(elements).ambiguousIds;

// Element transform used by the renderer (see Renderer.transformPoint):
// world = center + rotate(local.x + local.y * shear, local.y).
Point<double> _toWorld(
  Point<double> local,
  Point<double> center,
  double rad,
  double shear,
) {
  final x = local.x - center.x, y = local.y - center.y;
  final sx = x + y * shear;
  final c = cos(rad), s = sin(rad);
  return Point(center.x + sx * c - y * s, center.y + sx * s + y * c);
}

Point<double> _toLocal(
  Point<double> world,
  Point<double> center,
  double rad,
  double shear,
) {
  final x = world.x - center.x, y = world.y - center.y;
  final c = cos(rad), s = sin(rad);
  final rx = x * c + y * s, ry = -x * s + y * c;
  return Point(center.x + rx - ry * shear, center.y + ry);
}

/// The visual center of a shape (rotation and shear pivot).
Point<double> shapeCenter(ShapeElement shape) => Point(
  (shape.firstPosition.x + shape.secondPosition.x) / 2,
  (shape.firstPosition.y + shape.secondPosition.y) / 2,
);

/// Smallest positive ray parameter t where `t * (dx, dy)` leaves the convex
/// polygon [points] (relative to the ray origin), or null.
double? _rayPolygon(double dx, double dy, List<Point<double>> points) {
  double? best;
  for (var i = 0; i < points.length; i++) {
    final a = points[i], b = points[(i + 1) % points.length];
    final ex = b.x - a.x, ey = b.y - a.y;
    final denom = dx * ey - dy * ex;
    if (denom.abs() < 1e-12) continue;
    final t = (a.x * ey - a.y * ex) / denom;
    final u = (a.x * dy - a.y * dx) / denom;
    if (t > 0 && u >= -1e-9 && u <= 1 + 1e-9) {
      if (best == null || t < best) best = t;
    }
  }
  return best;
}

/// Outward ray parameter where the ray `t * (dx, dy)` leaves the circle at
/// ([kx], [ky]) with radius [r].
double? _rayCircleExit(double dx, double dy, double kx, double ky, double r) {
  final a = dx * dx + dy * dy;
  final b = -2 * (dx * kx + dy * ky);
  final c = kx * kx + ky * ky - r * r;
  final disc = b * b - 4 * a * c;
  if (a == 0 || disc < 0) return null;
  return (-b + sqrt(disc)) / (2 * a);
}

/// Ray parameter (relative to the center) where the axis-aligned outline of
/// [shape] is left, in local (untransformed) coordinates.
double? _localExit(ShapeElement shape, double dx, double dy) {
  final width = (shape.secondPosition.x - shape.firstPosition.x).abs();
  final height = (shape.secondPosition.y - shape.firstPosition.y).abs();
  // The outline is drawn on the rect inset by half the stroke width.
  final inset = max(0.0, shape.property.strokeWidth / 2);
  final hw = max(0.0, width / 2 - inset), hh = max(0.0, height / 2 - inset);
  if (hw == 0 && hh == 0) return null;
  switch (shape.property.shape) {
    case CircleShape():
      if (hw == 0 || hh == 0) break;
      return 1 / sqrt((dx / hw) * (dx / hw) + (dy / hh) * (dy / hh));
    case TriangleShape():
      // Matches ShapeRenderer._trianglePoints.
      final flipped = shape.secondPosition.y < shape.firstPosition.y;
      final tipY = flipped ? hh : -hh, baseY = -tipY;
      return _rayPolygon(dx, dy, [
        Point(0, tipY),
        Point(hw, baseY),
        Point(-hw, baseY),
      ]);
    case RectangleShape(
      :final topLeftCornerRadius,
      :final topRightCornerRadius,
      :final bottomLeftCornerRadius,
      :final bottomRightCornerRadius,
    ):
      final tx = dx == 0 ? double.infinity : hw / dx.abs();
      final ty = dy == 0 ? double.infinity : hh / dy.abs();
      final t = min(tx, ty);
      if (!t.isFinite) return null;
      // Percentage based radii, scaled down like Flutter's RRect when the
      // radii of one side exceed its length.
      final shortest = 2 * min(hw, hh);
      double radius(double percent) => max(0.0, percent / 100 * shortest);
      var tl = radius(topLeftCornerRadius), tr = radius(topRightCornerRadius);
      var bl = radius(bottomLeftCornerRadius);
      var br = radius(bottomRightCornerRadius);
      var scale = 1.0;
      void fit(double sum, double length) {
        if (sum > length && sum > 0) scale = min(scale, length / sum);
      }

      fit(tl + tr, 2 * hw);
      fit(bl + br, 2 * hw);
      fit(tl + bl, 2 * hh);
      fit(tr + br, 2 * hh);
      tl *= scale;
      tr *= scale;
      bl *= scale;
      br *= scale;
      final px = dx * t, py = dy * t;
      final r = px < 0 ? (py < 0 ? tl : bl) : (py < 0 ? tr : br);
      if (r <= 0) return t;
      final kx = (hw - r) * px.sign, ky = (hh - r) * py.sign;
      if (px.abs() <= hw - r || py.abs() <= hh - r) return t;
      return _rayCircleExit(dx, dy, kx, ky, r) ?? t;
    default:
      break;
  }
  return null;
}

/// The point on the visible outline of [shape] where a ray from its center
/// towards [toward] leaves the shape, taking rotation and shear into account.
///
/// Returns null if [shape] is not a supported endpoint.
Point<double>? connectorAnchor(ShapeElement shape, Point<double> toward) {
  if (!shape.isConnectable) return null;
  final center = shapeCenter(shape);
  final rad = shape.rotation * pi / 180;
  // Affine maps preserve ray parameters, so the exit parameter computed in
  // local space is exact in world space.
  final local = _toLocal(toward, center, rad, shape.shear);
  final dx = local.x - center.x, dy = local.y - center.y;
  if (dx == 0 && dy == 0) return center;
  final exit = _localExit(shape, dx, dy);
  if (exit == null || !exit.isFinite) return center;
  // Never extend past the target point when it lies inside the shape.
  final t = min(exit, 1.0);
  final world = _toWorld(
    Point(center.x + dx * t, center.y + dy * t),
    center,
    rad,
    shape.shear,
  );
  return world;
}

/// Computes the endpoints of a straight connector between two shapes, or
/// null if either is not a supported endpoint.
(Point<double>, Point<double>)? connectorEndpoints(
  ShapeElement from,
  ShapeElement to,
) {
  final a = connectorAnchor(from, shapeCenter(to));
  final b = connectorAnchor(to, shapeCenter(from));
  if (a == null || b == null) return null;
  return (a, b);
}

/// Re-routes [connector] between [from] and [to]. Rotation and shear are reset
/// because the endpoints are absolute. Returns null for unsupported shapes.
ShapeElement? routeConnector(
  ShapeElement connector,
  ShapeElement from,
  ShapeElement to,
) {
  final endpoints = connectorEndpoints(from, to);
  if (endpoints == null) return null;
  final (a, b) = endpoints;
  return connector.copyWith(
    firstPosition: a,
    secondPosition: b,
    rotation: 0,
    shear: 0,
  );
}

/// Creates a new connector line between [from] and [to].
///
/// Returns null if either shape is not a supported endpoint, they are the
/// same, or (when [content] is given) either id is missing or ambiguous in
/// [content].
ShapeElement? createConnector(
  ShapeElement from,
  ShapeElement to, {
  String? id,
  String collection = '',
  ShapeProperty? property,
  Iterable<PadElement>? content,
}) {
  final fromId = from.id, toId = to.id;
  if (!from.isConnectable || !to.isConnectable) return null;
  if (fromId == null || toId == null || fromId == toId) return null;
  if (content != null) {
    final index = ConnectorIndex(content);
    if (index.endpoint(fromId) != from || index.endpoint(toId) != to) {
      return null;
    }
  }
  final base = ShapeElement(
    id: id,
    collection: collection,
    property: (property ?? from.property).copyWith(shape: const LineShape()),
  ).withConnector(ConnectorReference(fromId, toId));
  return routeConnector(base, from, to);
}

/// Applies `ElementsChanged`-style [changes] to [content].
List<PadElement> applyElementChanges(
  Iterable<PadElement> content,
  Map<String, List<PadElement>> changes,
) => content.expand((e) => changes[e.id] ?? [e]).toList();

/// Ids of connectors that are valid in [before] but no longer valid in
/// [after] (an endpoint was removed, became ambiguous or became an
/// unsupported shape). Connectors that were already invalid are ignored, so
/// this never cleans up pre-existing data.
Set<String> invalidatedConnectors(
  Iterable<PadElement> before,
  Iterable<PadElement> after,
) {
  final beforeIndex = ConnectorIndex(before);
  final afterIndex = ConnectorIndex(after);
  final result = <String>{};
  for (final element in after) {
    final id = element.id;
    if (id == null || !element.isConnector) continue;
    final previous = beforeIndex[id];
    final previouslyValid =
        previous != null &&
        previous.connector == element.connector &&
        beforeIndex.isValid(previous);
    if (previouslyValid && !afterIndex.isValid(element)) result.add(id);
  }
  return result;
}

/// Returns ids of connectors in [content] that depend on any of [removedIds]
/// and therefore have to be removed with them.
Set<String> danglingConnectors(
  Iterable<PadElement> content,
  Iterable<String> removedIds,
) {
  final removed = removedIds.toSet();
  final list = content.toList();
  return invalidatedConnectors(
    list,
    list.where((e) => !removed.contains(e.id)),
  );
}

/// Removes connectors from [after] that were invalidated by the change from
/// [before]. Returns the pruned page and the removed connector ids.
(DocumentPage, Set<String>) pruneInvalidatedConnectors(
  DocumentPage before,
  DocumentPage after,
) {
  final invalid = invalidatedConnectors(before.content, after.content);
  if (invalid.isEmpty) return (after, invalid);
  return (
    after.mapLayers(
      (layer) => layer.copyWith(
        content: layer.content.where((e) => !invalid.contains(e.id)).toList(),
      ),
    ),
    invalid,
  );
}

/// Given the current page [content] and pending [changes] (keyed by the id of
/// the replaced element, as in `ElementsChanged`), returns the connectors that
/// need to be re-routed, keyed by connector id.
///
/// Connectors that are part of [changes] themselves are re-routed as well so
/// that they stay attached to their shapes. Connectors with missing,
/// ambiguous or unsupported targets are left untouched.
Map<String, ShapeElement> rerouteConnectors(
  Iterable<PadElement> content,
  Map<String, List<PadElement>> changes,
) {
  final after = applyElementChanges(content, changes);
  final index = ConnectorIndex(after);
  final changedShapeIds = changes.values
      .expand((e) => e)
      .where((e) => e.isConnectable)
      .map((e) => e.id)
      .nonNulls
      .toSet();
  final result = <String, ShapeElement>{};
  for (final connector in after) {
    final id = connector.id;
    final reference = connector.connector;
    if (id == null || reference == null || connector is! ShapeElement) {
      continue;
    }
    if (index[id] != connector) continue;
    final selfChanged = changes.containsKey(id);
    if (!selfChanged &&
        !changedShapeIds.contains(reference.from) &&
        !changedShapeIds.contains(reference.to)) {
      continue;
    }
    final from = index.endpoint(reference.from);
    final to = index.endpoint(reference.to);
    if (from == null || to == null) continue;
    final routed = routeConnector(connector, from, to);
    if (routed == null) continue;
    if (routed != connector || selfChanged) result[id] = routed;
  }
  return result;
}

/// Completes `ElementsChanged`-style [changes] so that connectors stay
/// consistent within the same state change (one undo step): connectors whose
/// endpoint was removed, became ambiguous or became unsupported are removed
/// (mapped to an empty list) and connectors attached to changed shapes are
/// re-routed.
///
/// Returns the completed changes and the ids of the connectors this function
/// added or replaced, so callers can find out which layers it touched (see
/// [layersContaining]).
(Map<String, List<PadElement>>, Set<String>) completeConnectorChanges(
  Iterable<PadElement> content,
  Map<String, List<PadElement>> changes,
) {
  final list = content.toList();
  final result = Map<String, List<PadElement>>.of(changes);
  final generated = <String>{};
  for (final id in invalidatedConnectors(
    list,
    applyElementChanges(list, result),
  )) {
    result[id] = const [];
    generated.add(id);
  }
  for (final MapEntry(key: id, value: connector) in rerouteConnectors(
    list,
    result,
  ).entries) {
    if (result[id]?.isEmpty ?? false) continue;
    result[id] = [connector];
    generated.add(id);
  }
  return (result, generated);
}

/// Ids of the layers of [page] that contain an element with one of [ids].
Set<String?> layersContaining(DocumentPage page, Set<String> ids) => {
  for (final layer in page.layers)
    if (layer.content.any((e) => ids.contains(e.id))) layer.id,
};

/// Ids that newly created elements must not reuse on a page with [content]:
/// every element id and every id an existing connector refers to, even if
/// that reference does not resolve right now.
///
/// Reusing one of them would let an existing connector resolve to a
/// different shape later, for example once the original shape is removed and
/// the newcomer is no longer ambiguous.
Set<String> reservedElementIds(Iterable<PadElement> content) {
  final reserved = <String>{};
  for (final element in content) {
    final id = element.id;
    if (id != null) reserved.add(id);
    final reference = element.connector;
    if (reference != null) reserved.addAll([reference.from, reference.to]);
  }
  return reserved;
}

/// Renames [created] elements whose id is reserved on the page (see
/// [reservedElementIds]) or repeated within the batch, so that creating
/// elements can never make an id ambiguous or capture an existing connector.
///
/// New ids are derived deterministically (`<id>~<n>`) so every collaborator
/// applying the same event to the same page gets the same result. Connectors
/// in the batch that refer to a renamed or repeated id are detached, because
/// it is unclear whether they meant the existing element or the new one.
/// Elements already in [content] are never modified.
List<PadElement> resolveCreatedIdCollisions(
  Iterable<PadElement> content,
  List<PadElement> created,
) {
  final reserved = reservedElementIds(content);
  final used = {...reserved, ...created.map((e) => e.id).nonNulls};
  final seen = <String>{};
  final conflicting = <String>{};
  String freshId(String base) {
    var n = 1;
    while (used.contains('$base~$n')) {
      n++;
    }
    final id = '$base~$n';
    used.add(id);
    return id;
  }

  final renamed = created.map((element) {
    final id = element.id;
    if (id == null) return element;
    if (reserved.contains(id) || !seen.add(id)) {
      conflicting.add(id);
      return element.copyWith(id: freshId(id));
    }
    return element;
  }).toList();
  if (conflicting.isEmpty) return created;
  return renamed.map((element) {
    final reference = element.connector;
    if (reference == null || element is! ShapeElement) return element;
    if (conflicting.contains(reference.from) ||
        conflicting.contains(reference.to)) {
      return element.withConnector(null);
    }
    return element;
  }).toList();
}

/// Gives [elements] new ids using [idMap] (old id to new id; elements whose id
/// is not mapped get [createId]) and remaps connector references through the
/// same map.
///
/// A connector is kept attached only if both endpoints are mapped and mapped
/// unambiguously, so a copy is never attached to the original shapes. Other
/// connectors are detached (they become plain lines).
List<PadElement> remapElementIds(
  Iterable<PadElement> elements,
  Map<String, String> idMap,
  String Function() createId, {
  Set<String> ambiguousIds = const {},
}) => elements.map((e) {
  final oldId = e.id;
  final newId = (oldId == null || ambiguousIds.contains(oldId))
      ? createId()
      : (idMap[oldId] ?? createId());
  final element = e.copyWith(id: newId);
  final reference = element.connector;
  if (reference == null || element is! ShapeElement) {
    return detachConnector(element);
  }
  final from = idMap[reference.from], to = idMap[reference.to];
  if (from == null ||
      to == null ||
      ambiguousIds.contains(reference.from) ||
      ambiguousIds.contains(reference.to)) {
    return element.withConnector(null);
  }
  return element.withConnector(ConnectorReference(from, to));
}).toList();

/// Creates an old-to-new id map for every id in [elements]. Duplicate ids are
/// reported via the returned ambiguous set and excluded from the map.
(Map<String, String>, Set<String>) createIdMapping(
  Iterable<PadElement> elements,
  String Function() createId,
) {
  final ambiguous = findDuplicateIds(elements);
  final map = <String, String>{};
  for (final element in elements) {
    final id = element.id;
    if (id == null || ambiguous.contains(id) || map.containsKey(id)) continue;
    map[id] = createId();
  }
  return (map, ambiguous);
}

/// Assigns fresh ids to [elements] (e.g. for duplicate, paste, import or
/// stamping) and remaps connector references within the batch. Connectors
/// copied without both of their endpoints are detached.
List<PadElement> regenerateElementIds(
  Iterable<PadElement> elements,
  String Function() createId,
) {
  final list = elements.toList();
  final (map, ambiguous) = createIdMapping(list, createId);
  return remapElementIds(list, map, createId, ambiguousIds: ambiguous);
}

/// Prepares [created] elements before they are added next to [content]:
/// connectors whose endpoints resolve are routed, all other connectors in the
/// batch are detached so no inactive-but-referencing connector is created.
/// Elements already in [content] are never modified.
List<PadElement> prepareCreatedElements(
  Iterable<PadElement> content,
  List<PadElement> created,
) {
  if (!created.any((e) => e.extra.containsKey(kConnectorExtraKey))) {
    return created;
  }
  final index = ConnectorIndex([...content, ...created]);
  return created.map((element) {
    final reference = element.connector;
    if (reference == null || element is! ShapeElement) {
      return detachConnector(element);
    }
    final from = index.endpoint(reference.from);
    final to = index.endpoint(reference.to);
    if (from == null || to == null) return element.withConnector(null);
    return routeConnector(element, from, to) ?? element.withConnector(null);
  }).toList();
}
