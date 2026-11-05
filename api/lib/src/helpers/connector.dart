import 'dart:math';

import '../models/element.dart';
import '../models/property.dart';

/// Namespaced key in [PadElement.extra] that marks a line [ShapeElement] as a
/// connector between two other shapes.
///
/// A connector is stored as an ordinary line shape so that documents remain
/// readable by older versions (they simply see a straight line) and so that
/// selection, styling, deletion and rendering reuse the existing pipeline.
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

extension PadElementConnectorExtension on PadElement {
  /// The connector reference if this element is a valid connector.
  ConnectorReference? get connector {
    final element = this;
    if (element is! ShapeElement) return null;
    if (element.property.shape is! LineShape) return null;
    return ConnectorReference.tryParse(element.extra[kConnectorExtraKey]);
  }

  bool get isConnector => connector != null;

  /// Whether this element can be an endpoint of a connector.
  bool get isConnectable {
    final element = this;
    return element is ShapeElement &&
        element.id != null &&
        element.property.shape is! LineShape;
  }
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

Point<double> _rotate(Point<double> point, Point<double> pivot, double rad) {
  if (rad == 0) return point;
  final c = cos(rad), s = sin(rad);
  final dx = point.x - pivot.x, dy = point.y - pivot.y;
  return Point(pivot.x + dx * c - dy * s, pivot.y + dx * s + dy * c);
}

/// The visual center of a shape (rotation pivot).
Point<double> shapeCenter(ShapeElement shape) => Point(
  (shape.firstPosition.x + shape.secondPosition.x) / 2,
  (shape.firstPosition.y + shape.secondPosition.y) / 2,
);

/// The point on the outline of [shape] where a ray from its center towards
/// [toward] leaves the shape. Circles use their ellipse, everything else
/// uses its (rotated) bounding rectangle.
Point<double> connectorAnchor(ShapeElement shape, Point<double> toward) {
  final center = shapeCenter(shape);
  final rad = shape.rotation * pi / 180;
  final local = _rotate(toward, center, -rad);
  final dx = local.x - center.x, dy = local.y - center.y;
  final rx = (shape.secondPosition.x - shape.firstPosition.x).abs() / 2;
  final ry = (shape.secondPosition.y - shape.firstPosition.y).abs() / 2;
  if ((dx == 0 && dy == 0) || (rx == 0 && ry == 0)) return center;
  double t;
  if (shape.property.shape is CircleShape && rx > 0 && ry > 0) {
    t = 1 / sqrt((dx / rx) * (dx / rx) + (dy / ry) * (dy / ry));
  } else {
    final tx = dx == 0 ? double.infinity : rx / dx.abs();
    final ty = dy == 0 ? double.infinity : ry / dy.abs();
    t = min(tx, ty);
  }
  if (!t.isFinite) return center;
  // Never extend past the target point when it lies inside the shape.
  t = min(t, 1);
  return _rotate(Point(center.x + dx * t, center.y + dy * t), center, rad);
}

/// Computes the endpoints of a straight connector between two shapes.
(Point<double>, Point<double>) connectorEndpoints(
  ShapeElement from,
  ShapeElement to,
) => (
  connectorAnchor(from, shapeCenter(to)),
  connectorAnchor(to, shapeCenter(from)),
);

/// Re-routes [connector] between [from] and [to]. Rotation and shear are reset
/// because the endpoints are absolute.
ShapeElement routeConnector(
  ShapeElement connector,
  ShapeElement from,
  ShapeElement to,
) {
  final (a, b) = connectorEndpoints(from, to);
  return connector.copyWith(
    firstPosition: a,
    secondPosition: b,
    rotation: 0,
    shear: 0,
  );
}

/// Creates a new connector line between [from] and [to].
///
/// Returns null if either shape is not connectable or they are the same.
ShapeElement? createConnector(
  ShapeElement from,
  ShapeElement to, {
  String? id,
  String collection = '',
  ShapeProperty? property,
}) {
  final fromId = from.id, toId = to.id;
  if (!from.isConnectable || !to.isConnectable) return null;
  if (fromId == null || toId == null || fromId == toId) return null;
  final base = ShapeElement(
    id: id,
    collection: collection,
    property: (property ?? from.property).copyWith(shape: const LineShape()),
  ).withConnector(ConnectorReference(fromId, toId));
  return routeConnector(base, from, to);
}

/// Given the current page [content] and pending [changes] (keyed by the id of
/// the replaced element, as in `ElementsChanged`), returns the connectors that
/// need to be re-routed, keyed by connector id.
///
/// Connectors that are part of [changes] themselves are re-routed as well so
/// that they stay attached to their shapes. Connectors with missing or
/// non-connectable targets are left untouched.
Map<String, ShapeElement> rerouteConnectors(
  Iterable<PadElement> content,
  Map<String, List<PadElement>> changes,
) {
  final shapes = <String, ShapeElement>{};
  final connectors = <String, ShapeElement>{};
  void register(PadElement element) {
    final id = element.id;
    if (id == null || element is! ShapeElement) return;
    if (element.isConnector) {
      connectors[id] = element;
    } else if (element.isConnectable) {
      shapes[id] = element;
    } else {
      shapes.remove(id);
      connectors.remove(id);
    }
  }

  for (final element in content) {
    final id = element.id;
    if (id != null && changes.containsKey(id)) continue;
    register(element);
  }
  for (final updated in changes.values) {
    updated.forEach(register);
  }

  final changedShapeIds = changes.values
      .expand((e) => e)
      .where((e) => e.isConnectable)
      .map((e) => e.id)
      .nonNulls
      .toSet();
  final result = <String, ShapeElement>{};
  for (final MapEntry(key: id, value: connector) in connectors.entries) {
    final reference = connector.connector!;
    final selfChanged = changes.containsKey(id);
    if (!selfChanged &&
        !changedShapeIds.contains(reference.from) &&
        !changedShapeIds.contains(reference.to)) {
      continue;
    }
    final from = shapes[reference.from];
    final to = shapes[reference.to];
    if (from == null || to == null) continue;
    final routed = routeConnector(connector, from, to);
    if (routed != connector || selfChanged) result[id] = routed;
  }
  return result;
}

/// Returns the ids of connectors in [content] that reference any of
/// [removedIds] and are not removed themselves.
Set<String> danglingConnectors(
  Iterable<PadElement> content,
  Iterable<String> removedIds,
) {
  final removed = removedIds.toSet();
  return content
      .where((e) {
        final reference = e.connector;
        final id = e.id;
        return id != null &&
            reference != null &&
            !removed.contains(id) &&
            (removed.contains(reference.from) ||
                removed.contains(reference.to));
      })
      .map((e) => e.id!)
      .toSet();
}

/// Assigns fresh ids to [elements] (e.g. for duplicate, paste or import) and
/// remaps connector references within the batch.
///
/// A connector whose endpoints are not both part of the batch is detached
/// (its connector metadata is removed and it becomes a plain line) so that a
/// copy is never silently attached to the original shapes.
List<PadElement> regenerateElementIds(
  Iterable<PadElement> elements,
  String Function() createId,
) {
  final list = elements.toList();
  final idMap = <String, String>{};
  final withIds = list.map((e) {
    final newId = createId();
    final oldId = e.id;
    if (oldId != null) idMap[oldId] = newId;
    return e.copyWith(id: newId);
  }).toList();
  return withIds.map((e) {
    final reference = e.connector;
    if (reference == null || e is! ShapeElement) return e;
    final from = idMap[reference.from], to = idMap[reference.to];
    if (from == null || to == null) return e.withConnector(null);
    return e.withConnector(ConnectorReference(from, to));
  }).toList();
}
