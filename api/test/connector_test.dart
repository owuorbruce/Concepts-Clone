import 'dart:math';

import 'package:archive/archive.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:test/test.dart';

ShapeElement _shape(
  String id,
  double x,
  double y, {
  double w = 100,
  double h = 100,
  PathShape shape = const RectangleShape(),
  double strokeWidth = 0,
  String collection = '',
}) => ShapeElement(
  id: id,
  collection: collection,
  firstPosition: Point(x, y),
  secondPosition: Point(x + w, y + h),
  property: ShapeProperty(shape: shape, strokeWidth: strokeWidth),
);

void _expectPoint(Point<double>? actual, Point<double> expected) {
  expect(actual, isNotNull);
  expect(actual!.x, closeTo(expected.x, 1e-6), reason: '$actual');
  expect(actual.y, closeTo(expected.y, 1e-6), reason: '$actual');
}

/// Transforms a local point exactly like Renderer.transformPoint.
Point<double> _world(ShapeElement s, Point<double> local) {
  final c = shapeCenter(s);
  final x = local.x - c.x, y = local.y - c.y;
  final sx = x + y * s.shear;
  final rad = s.rotation * pi / 180;
  return Point(
    c.x + sx * cos(rad) - y * sin(rad),
    c.y + sx * sin(rad) + y * cos(rad),
  );
}

/// Distance between [p] and segment [a]-[b].
double _segmentDistance(Point<double> p, Point<double> a, Point<double> b) {
  final ab = b - a, ap = p - a;
  final t = ((ap.x * ab.x + ap.y * ab.y) / (ab.x * ab.x + ab.y * ab.y)).clamp(
    0.0,
    1.0,
  );
  return p.distanceTo(Point(a.x + ab.x * t, a.y + ab.y * t));
}

int _counter = 0;
String _id() => 'n${_counter++}';

void main() {
  setUp(() => _counter = 0);

  final a = _shape('a', 0, 0);
  final b = _shape('b', 300, 0);

  group('geometry', () {
    test('connects facing rectangle edges', () {
      final connector = createConnector(a, b, id: 'c')!;
      _expectPoint(connector.firstPosition, const Point(100, 50));
      _expectPoint(connector.secondPosition, const Point(300, 50));
      expect(connector.property.shape, isA<LineShape>());
      expect(connector.connector, const ConnectorReference('a', 'b'));
    });

    test('anchors on the stroke centerline like the renderer', () {
      final stroked = _shape('s', 0, 0, strokeWidth: 10);
      _expectPoint(
        connectorAnchor(stroked, const Point(500, 50)),
        const Point(95, 50),
      );
    });

    test('anchors on ellipse outline for circles', () {
      final circle = _shape('o', 0, 0, shape: const CircleShape());
      final r = 50 / sqrt2;
      _expectPoint(
        connectorAnchor(circle, const Point(150, 150)),
        Point(50 + r, 50 + r),
      );
    });

    test('anchors on rounded rectangle corners', () {
      final rounded = _shape(
        'r',
        0,
        0,
        shape: const RectangleShape(bottomRightCornerRadius: 50),
      );
      // Radius 50 => the bottom-right corner is a quarter circle centered at
      // (50, 50); the diagonal ray exits at distance 50 from the center.
      final r = 50 / sqrt2;
      _expectPoint(
        connectorAnchor(rounded, const Point(200, 200)),
        Point(50 + r, 50 + r),
      );
    });

    group('triangles', () {
      final triangle = _shape('t', 0, 0, shape: const TriangleShape());

      test('hit the slanted edge, not the bounding box', () {
        // Horizontal ray from (50, 50) to the right exits the edge
        // (50, 0)-(100, 100) at y = 50 => x = 75.
        _expectPoint(
          connectorAnchor(triangle, const Point(500, 50)),
          const Point(75, 50),
        );
        _expectPoint(
          connectorAnchor(triangle, const Point(50, 500)),
          const Point(50, 100),
        );
        _expectPoint(
          connectorAnchor(triangle, const Point(50, -500)),
          const Point(50, 0),
        );
      });

      test('respect vertical flipping', () {
        final flipped = triangle.copyWith(
          firstPosition: const Point(0, 100),
          secondPosition: const Point(100, 0),
        );
        _expectPoint(
          connectorAnchor(flipped, const Point(50, 500)),
          const Point(50, 100),
        );
        _expectPoint(
          connectorAnchor(flipped, const Point(500, 50)),
          const Point(75, 50),
        );
      });

      test('lie on the transformed outline under rotation and shear', () {
        final transformed = triangle.copyWith(rotation: 30, shear: 0.4);
        final outline = [
          const Point(50.0, 0.0),
          const Point(100.0, 100.0),
          const Point(0.0, 100.0),
        ].map((p) => _world(transformed, p)).toList();
        for (final target in [
          const Point(500.0, 50.0),
          const Point(-300.0, 20.0),
          const Point(40.0, 600.0),
          const Point(80.0, -400.0),
        ]) {
          final anchor = connectorAnchor(transformed, target)!;
          final distance = [
            for (var i = 0; i < 3; i++)
              _segmentDistance(anchor, outline[i], outline[(i + 1) % 3]),
          ].reduce(min);
          expect(distance, lessThan(1e-6), reason: '$target -> $anchor');
          // The anchor lies on the segment from the center to the target.
          final center = shapeCenter(transformed);
          expect(_segmentDistance(anchor, center, target), lessThan(1e-6));
        }
      });
    });

    test('respects rectangle rotation', () {
      final rotated = _shape('r', 0, 0, w: 200, h: 100).copyWith(rotation: 90);
      // 200x100 rect rotated 90deg: half-extent towards +x is 50.
      _expectPoint(
        connectorAnchor(rotated, const Point(1000, 50)),
        const Point(150, 50),
      );
    });

    test('respects shear on rectangles', () {
      final sheared = a.copyWith(shear: 1);
      // Local corner (100, 100) maps to (150, 100) after shear around center.
      final anchor = connectorAnchor(sheared, const Point(1000, 1000))!;
      final outline = [
        const Point(0.0, 0.0),
        const Point(100.0, 0.0),
        const Point(100.0, 100.0),
        const Point(0.0, 100.0),
      ].map((p) => _world(sheared, p)).toList();
      final distance = [
        for (var i = 0; i < 4; i++)
          _segmentDistance(anchor, outline[i], outline[(i + 1) % 4]),
      ].reduce(min);
      expect(distance, lessThan(1e-6));
    });

    test('rejects unsupported endpoints', () {
      expect(createConnector(a, a), isNull);
      final line = _shape('l', 0, 0, shape: const LineShape());
      expect(createConnector(a, line), isNull);
      expect(createConnector(a, ShapeElement()), isNull);
      final flat = _shape('f', 0, 0, h: 0);
      expect(flat.isConnectable, isFalse);
      expect(createConnector(a, flat), isNull);
      expect(connectorAnchor(line, const Point(1, 1)), isNull);
    });

    test('rejects ambiguous endpoints', () {
      final duplicate = _shape('a', 600, 0);
      expect(createConnector(a, b, content: [a, b, duplicate]), isNull);
      expect(createConnector(a, b, content: [a, b]), isNotNull);
      expect(createConnector(a, b, content: [a]), isNull);
    });
  });

  group('references', () {
    test('ignores malformed metadata', () {
      for (final value in [
        null,
        'x',
        {'from': 'a'},
        {'from': 'a', 'to': 'a'},
        {'from': 1, 'to': 'b'},
      ]) {
        final line = ShapeElement(
          property: const ShapeProperty(shape: LineShape()),
          extra: {kConnectorExtraKey: value},
        );
        expect(line.connector, isNull, reason: '$value');
      }
    });

    test('non-line shapes are never connectors', () {
      final shape = a.copyWith(
        extra: {
          kConnectorExtraKey: {'from': 'a', 'to': 'b'},
        },
      );
      expect(shape.isConnector, isFalse);
    });

    test('preserves unrelated metadata', () {
      final line = createConnector(a, b)!.copyWith(
        extra: {
          'other.plugin': 42,
          kConnectorExtraKey: {'from': 'a', 'to': 'b'},
        },
      );
      final detached = line.withConnector(null);
      expect(detached.extra, {'other.plugin': 42});
      expect(
        detached
            .withConnector(const ConnectorReference('x', 'y'))
            .extra['other.plugin'],
        42,
      );
    });

    test('index detects duplicate ids across layers', () {
      final connector = createConnector(a, b, id: 'c')!;
      final page = DocumentPage(
        layers: [
          DocumentLayer(id: 'l1', content: [a, connector]),
          DocumentLayer(id: 'l2', content: [b, _shape('a', 0, 500)]),
        ],
      );
      final index = ConnectorIndex(page.content);
      expect(index.ambiguousIds, {'a'});
      expect(index.endpoint('a'), isNull);
      expect(index.isValid(connector), isFalse);
      expect(findDuplicateIds(page.content), {'a'});
    });
  });

  group('movement and resize', () {
    final connector = createConnector(a, b, id: 'c')!;
    final content = <PadElement>[a, b, connector];

    test('moving a shape re-routes the connector', () {
      final moved = b.copyWith(
        firstPosition: const Point(300, 300),
        secondPosition: const Point(400, 400),
      );
      final updates = rerouteConnectors(content, {
        'b': [moved],
      });
      expect(updates.keys, ['c']);
      final (start, end) = connectorEndpoints(a, moved)!;
      _expectPoint(updates['c']!.firstPosition, start);
      _expectPoint(updates['c']!.secondPosition, end);
      _expectPoint(end, const Point(300, 300));
    });

    test('resizing a shape updates its endpoint', () {
      final resized = a.copyWith(secondPosition: const Point(200, 100));
      final updates = rerouteConnectors(content, {
        'a': [resized],
      });
      _expectPoint(updates['c']!.firstPosition, const Point(200, 50));
      _expectPoint(updates['c']!.secondPosition, const Point(300, 50));
    });

    test('moving both shapes together routes against new positions', () {
      final updates = rerouteConnectors(content, {
        'a': [
          a.copyWith(
            firstPosition: const Point(0, 100),
            secondPosition: const Point(100, 200),
          ),
        ],
        'b': [
          b.copyWith(
            firstPosition: const Point(300, 100),
            secondPosition: const Point(400, 200),
          ),
        ],
      });
      _expectPoint(updates['c']!.firstPosition, const Point(100, 150));
      _expectPoint(updates['c']!.secondPosition, const Point(300, 150));
    });

    test('a moved connector snaps back to its shapes', () {
      final updates = rerouteConnectors(content, {
        'c': [
          connector.copyWith(
            firstPosition: const Point(1000, 1000),
            secondPosition: const Point(1200, 1000),
          ),
        ],
      });
      _expectPoint(updates['c']!.firstPosition, const Point(100, 50));
    });

    test('unrelated changes do not touch connectors', () {
      final other = _shape('z', 0, 500);
      expect(
        rerouteConnectors(
          [...content, other],
          {
            'z': [other.copyWith(rotation: 10)],
          },
        ),
        isEmpty,
      );
    });

    test('missing or ambiguous targets leave the connector untouched', () {
      final orphan = connector.withConnector(
        const ConnectorReference('a', 'missing'),
      );
      expect(
        rerouteConnectors(
          [a, orphan],
          {
            'a': [a.copyWith(rotation: 45)],
          },
        ),
        isEmpty,
      );
      expect(
        rerouteConnectors(
          [...content, _shape('b', 900, 0)],
          {
            'a': [a.copyWith(rotation: 45)],
          },
        ),
        isEmpty,
      );
    });
  });

  group('invalidation', () {
    final connector = createConnector(a, b, id: 'c')!;
    final content = <PadElement>[a, b, connector];

    test('removing a shape invalidates its connectors', () {
      expect(danglingConnectors(content, ['a']), {'c'});
      expect(danglingConnectors(content, ['a', 'c']), isEmpty);
      expect(danglingConnectors(content, ['z']), isEmpty);
    });

    test('converting an endpoint into a line invalidates the connector', () {
      final line = a.copyWith(
        property: a.property.copyWith(shape: const LineShape()),
      );
      final after = applyElementChanges(content, {
        'a': [line],
      });
      expect(invalidatedConnectors(content, after), {'c'});
      // Rerouting never produces geometry for an unsupported endpoint.
      expect(
        rerouteConnectors(content, {
          'a': [line],
        }),
        isEmpty,
      );
    });

    test('collapsing an endpoint to zero size invalidates the connector', () {
      final after = applyElementChanges(content, {
        'a': [a.copyWith(secondPosition: const Point(100, 0))],
      });
      expect(invalidatedConnectors(content, after), {'c'});
    });

    test('changing an endpoint id invalidates the connector', () {
      final after = applyElementChanges(content, {
        'a': [a.copyWith(id: 'other')],
      });
      expect(invalidatedConnectors(content, after), {'c'});
    });

    test('pre-existing invalid connectors are not cleaned up', () {
      final orphan = connector.withConnector(
        const ConnectorReference('a', 'missing'),
      );
      expect(invalidatedConnectors([a, orphan], [a, orphan]), isEmpty);
      expect(danglingConnectors([a, orphan], ['a']), isEmpty);
    });

    test('removing an endpoint layer prunes connectors in other layers', () {
      final before = DocumentPage(
        layers: [
          DocumentLayer(id: 'shapes-a', content: [a]),
          DocumentLayer(id: 'shapes-b', content: [b]),
          DocumentLayer(id: 'lines', content: [connector, _shape('z', 0, 0)]),
        ],
      );
      final after = before.copyWith(
        layers: before.layers.where((e) => e.id != 'shapes-a').toList(),
      );
      final (pruned, removed) = pruneInvalidatedConnectors(before, after);
      expect(removed, {'c'});
      expect(pruned.content.map((e) => e.id), ['b', 'z']);
    });

    test('removing an endpoint collection prunes its connectors', () {
      final ca = a.copyWith(collection: 'group');
      final before = DocumentPage(
        layers: [
          DocumentLayer(id: 'l1', content: [ca, b]),
          DocumentLayer(id: 'l2', content: [connector]),
        ],
      );
      final after = before.mapLayers(
        (l) => l.copyWith(
          content: l.content.where((e) => e.collection != 'group').toList(),
        ),
      );
      final (pruned, removed) = pruneInvalidatedConnectors(before, after);
      expect(removed, {'c'});
      expect(pruned.content.map((e) => e.id), ['b']);
    });

    test('an endpoint becoming ambiguous invalidates the connector', () {
      final after = [...content, _shape('a', 0, 900)];
      expect(invalidatedConnectors(content, after), {'c'});
    });
  });

  group('duplication, stamping and import', () {
    final connector = createConnector(a, b, id: 'c')!;
    final content = <PadElement>[a, b, connector];

    test('duplicating shapes with connector remaps references', () {
      final copies = regenerateElementIds(content, _id);
      expect(copies.map((e) => e.id), ['n0', 'n1', 'n2']);
      expect(copies[2].connector, const ConnectorReference('n0', 'n1'));
      expect(ConnectorIndex([...content, ...copies]).isValid(copies[2]), true);
    });

    test('a connector copied without both endpoints is detached', () {
      for (final batch in [
        [connector],
        [a, connector],
      ]) {
        final copies = regenerateElementIds(batch, _id);
        final line = copies.last as ShapeElement;
        expect(line.isConnector, isFalse);
        expect(line.extra.containsKey(kConnectorExtraKey), isFalse);
        expect(line.property.shape, isA<LineShape>());
      }
    });

    test('ambiguous ids inside a copied batch are never attached', () {
      final copies = regenerateElementIds([
        a,
        _shape('a', 0, 500),
        b,
        connector,
      ], _id);
      expect(copies.map((e) => e.id).toSet(), hasLength(4));
      expect(copies.last.isConnector, isFalse);
    });

    test('shared mapping remaps connectors across duplicated layers', () {
      final layers = [
        DocumentLayer(id: 'l1', content: [a]),
        DocumentLayer(id: 'l2', content: [b, connector]),
      ];
      final all = layers.expand((e) => e.content);
      final (map, ambiguous) = createIdMapping(all, _id);
      final copies = layers
          .map(
            (l) =>
                remapElementIds(l.content, map, _id, ambiguousIds: ambiguous),
          )
          .toList();
      final copiedConnector = copies[1][1];
      expect(
        copiedConnector.connector,
        ConnectorReference(map['a']!, map['b']!),
      );
      // Copying a single layer detaches connectors to other layers.
      final single = regenerateElementIds(layers[1].content, _id);
      expect(single[1].isConnector, isFalse);
    });

    test('stamping a component onto the original and another page', () {
      final component = ButterflyComponent(elements: content);
      final original = DocumentPage(
        layers: [DocumentLayer(id: 'l', content: content)],
      );
      const other = DocumentPage(layers: [DocumentLayer(id: 'l')]);
      for (final page in [original, other]) {
        final stamped = regenerateElementIds(component.elements, _id);
        final after = [...page.content, ...stamped];
        final stampedConnector = stamped.last;
        final reference = stampedConnector.connector!;
        expect(reference.from, isNot('a'));
        expect(reference.to, isNot('b'));
        final index = ConnectorIndex(after);
        expect(index.isValid(stampedConnector), isTrue);
        expect(index.ambiguousIds, isEmpty);
        // The original connector still references the originals.
        if (page == original) {
          expect(index['c']!.connector, const ConnectorReference('a', 'b'));
        }
      }
    });
  });

  group('persistence', () {
    test('survives json and document round trips across layers', () {
      final connector = createConnector(a, b, id: 'c')!;
      final page = DocumentPage(
        layers: [
          DocumentLayer(id: 'l1', content: [a]),
          DocumentLayer(id: 'l2', content: [b, connector]),
        ],
      );
      final (data, name) = NoteData(Archive()).setPage(page, 'Page');
      final loaded = NoteData.fromData(data.exportAsBytes()).getPage(name)!;
      final element = loaded.content.firstWhere((e) => e.id == 'c');
      expect(element.connector, const ConnectorReference('a', 'b'));
      expect(element, connector);
      expect(ConnectorIndex(loaded.content).isValid(element), isTrue);
    });

    test('invalid connectors load unchanged', () {
      final orphan = createConnector(
        a,
        b,
        id: 'c',
      )!.withConnector(const ConnectorReference('a', 'missing'));
      final page = DocumentPage(
        layers: [
          DocumentLayer(id: 'l', content: [a, orphan]),
        ],
      );
      final (data, name) = NoteData(Archive()).setPage(page, 'Page');
      final loaded = NoteData.fromData(data.exportAsBytes()).getPage(name)!;
      expect(loaded.content.last, orphan);
    });

    test('legacy line shapes load unchanged', () {
      final json = ShapeElement(
        id: 'l',
        property: const ShapeProperty(shape: LineShape()),
      ).toJson();
      final loaded = PadElement.fromJson(json);
      expect(loaded.isConnector, isFalse);
      expect(loaded.extra, isEmpty);
    });
  });

  group('creation', () {
    test('created connectors are routed when endpoints resolve', () {
      final stale = createConnector(
        a,
        b,
        id: 'c',
      )!.copyWith(firstPosition: const Point(999, 999));
      final [created] = prepareCreatedElements([a, b], [stale]);
      _expectPoint(
        (created as ShapeElement).firstPosition,
        const Point(100, 50),
      );
      expect(created.isConnector, isTrue);
    });

    test('created connectors with missing or ambiguous endpoints detach', () {
      final connector = createConnector(a, b, id: 'c')!;
      expect(
        prepareCreatedElements([a], [connector]).single.isConnector,
        false,
      );
      expect(
        prepareCreatedElements(
          [a, b, _shape('b', 0, 0)],
          [connector],
        ).single.isConnector,
        false,
      );
    });

    test('elements without connector metadata are returned unchanged', () {
      final created = [_shape('z', 0, 0)];
      expect(identical(prepareCreatedElements([a], created), created), isTrue);
    });
  });

  group('cross-layer connector changes', () {
    final connector = createConnector(a, b, id: 'c')!;
    final page = DocumentPage(
      layers: [
        DocumentLayer(id: 'shapes', content: [a, b]),
        DocumentLayer(id: 'connectors', content: [connector]),
      ],
    );

    test('re-routing reports the connector and its layer', () {
      final moved = b.copyWith(
        firstPosition: const Point(300, 300),
        secondPosition: const Point(400, 400),
      );
      final (changes, generated) = completeConnectorChanges(page.content, {
        'b': [moved],
      });
      expect(generated, {'c'});
      expect(changes['b'], [moved]);
      _expectPoint(
        (changes['c']!.single as ShapeElement).secondPosition,
        connectorEndpoints(a, moved)!.$2,
      );
      expect(layersContaining(page, generated), {'connectors'});
    });

    test('removal by endpoint conversion reports the connector', () {
      final line = a.copyWith(
        property: a.property.copyWith(shape: const LineShape()),
      );
      final (changes, generated) = completeConnectorChanges(page.content, {
        'a': [line],
      });
      expect(changes['c'], isEmpty);
      expect(generated, {'c'});
      expect(layersContaining(page, generated), {'connectors'});
    });

    test('changes that do not affect connectors report nothing', () {
      final other = _shape('z', 900, 900);
      final content = [...page.content, other];
      final moved = other.copyWith(firstPosition: const Point(950, 950));
      final (changes, generated) = completeConnectorChanges(content, {
        'z': [moved],
      });
      expect(generated, isEmpty);
      expect(changes.keys, ['z']);
    });
  });

  group('created id collisions', () {
    final connector = createConnector(a, b, id: 'c')!;

    test('a created duplicate never captures an existing connector', () {
      // Codex review scenario: create another `a` in a different layer,
      // remove the original's layer, then move the newcomer.
      final page = DocumentPage(
        layers: [
          DocumentLayer(id: 'layer-a', content: [a]),
          DocumentLayer(id: 'layer-b', content: [b, connector]),
        ],
      );
      final duplicate = _shape('a', 0, 600);
      final [created] = resolveCreatedIdCollisions(page.content, [duplicate]);
      expect(created.id, isNot('a'));
      final withCreated = page.mapLayer(
        'layer-b',
        (l) => l.copyWith(content: [...l.content, created]),
      );
      final index = ConnectorIndex(withCreated.content);
      expect(index.ambiguousIds, isEmpty);
      expect(index.isValid(connector), isTrue);

      final removed = withCreated.copyWith(
        layers: withCreated.layers.where((l) => l.id != 'layer-a').toList(),
      );
      final (after, pruned) = pruneInvalidatedConnectors(withCreated, removed);
      expect(pruned, {'c'});
      expect(after.content.map((e) => e.id), ['b', created.id]);

      final moved = (created as ShapeElement).copyWith(
        firstPosition: const Point(0, 900),
      );
      final rerouted = rerouteConnectors(after.content, {
        created.id!: [moved],
      });
      expect(rerouted, isEmpty);
    });

    test('ids referenced by dangling connectors are reserved', () {
      final dangling = createConnector(a, b, id: 'd')!;
      // Only `b` is on the page, so `d` does not resolve right now.
      final duplicate = _shape('a', 0, 600);
      final [created] = resolveCreatedIdCollisions([b, dangling], [duplicate]);
      expect(created.id, isNot('a'));
      expect(ConnectorIndex([b, dangling, created]).isValid(dangling), isFalse);
    });

    test('renamed ids are deterministic and avoid existing ids', () {
      final content = [a, b, _shape('a~1', 900, 0)];
      final created = [_shape('a', 0, 600), _shape('a', 0, 900)];
      final first = resolveCreatedIdCollisions(content, created);
      final second = resolveCreatedIdCollisions(content, created);
      expect(first.map((e) => e.id), ['a~2', 'a~3']);
      expect(second.map((e) => e.id), first.map((e) => e.id));
    });

    test('repeated ids within a batch are renamed and detach references', () {
      final x1 = _shape('x', 0, 600);
      final x2 = _shape('x', 300, 600);
      final y = _shape('y', 600, 600);
      final toX = createConnector(x1, y, id: 'k')!;
      final result = resolveCreatedIdCollisions([a, b], [x1, x2, y, toX]);
      expect(result.map((e) => e.id), ['x', 'x~1', 'y', 'k']);
      expect(result.last.isConnector, isFalse);
    });

    test('connectors between existing shapes stay attached', () {
      final created = resolveCreatedIdCollisions([a, b], [connector]);
      expect(identical(created.single, connector), isTrue);
      expect(prepareCreatedElements([a, b], created).single.isConnector, true);
    });

    test('batches without collisions are returned unchanged', () {
      final created = [_shape('z', 0, 0), _shape('w', 300, 0)];
      final result = resolveCreatedIdCollisions([a, b, connector], created);
      expect(identical(result, created), isTrue);
    });
  });
}
