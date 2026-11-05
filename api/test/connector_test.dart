import 'dart:math';

import 'package:archive/archive.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:test/test.dart';

ShapeElement _rect(String id, double x, double y, [double w = 100]) =>
    ShapeElement(
      id: id,
      firstPosition: Point(x, y),
      secondPosition: Point(x + w, y + w),
    );

void _expectPoint(Point<double> actual, Point<double> expected) {
  expect(actual.x, closeTo(expected.x, 1e-6));
  expect(actual.y, closeTo(expected.y, 1e-6));
}

void main() {
  final a = _rect('a', 0, 0);
  final b = _rect('b', 300, 0);

  group('geometry', () {
    test('connects facing rectangle edges', () {
      final connector = createConnector(a, b, id: 'c')!;
      _expectPoint(connector.firstPosition, const Point(100, 50));
      _expectPoint(connector.secondPosition, const Point(300, 50));
      expect(connector.property.shape, isA<LineShape>());
      expect(connector.connector, const ConnectorReference('a', 'b'));
    });

    test('anchors on ellipse outline for circles', () {
      final circle = ShapeElement(
        id: 'o',
        secondPosition: const Point(100, 100),
        property: const ShapeProperty(shape: CircleShape()),
      );
      final anchor = connectorAnchor(circle, const Point(150, 150));
      final r = 50 / sqrt2;
      _expectPoint(anchor, Point(50 + r, 50 + r));
    });

    test('respects shape rotation', () {
      final rotated = a.copyWith(
        rotation: 90,
        secondPosition: const Point(200, 100),
      );
      // 200x100 rect rotated 90deg: half-extent towards +x is 50.
      final anchor = connectorAnchor(rotated, const Point(1000, 50));
      _expectPoint(anchor, const Point(150, 50));
    });

    test('rejects invalid connections', () {
      expect(createConnector(a, a), isNull);
      final line = ShapeElement(
        id: 'l',
        property: const ShapeProperty(shape: LineShape()),
      );
      expect(createConnector(a, line), isNull);
      expect(createConnector(a, ShapeElement()), isNull);
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
      final (start, end) = connectorEndpoints(a, moved);
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
      final da = a.copyWith(
        firstPosition: const Point(0, 100),
        secondPosition: const Point(100, 200),
      );
      final db = b.copyWith(
        firstPosition: const Point(300, 100),
        secondPosition: const Point(400, 200),
      );
      final updates = rerouteConnectors(content, {
        'a': [da],
        'b': [db],
      });
      _expectPoint(updates['c']!.firstPosition, const Point(100, 150));
      _expectPoint(updates['c']!.secondPosition, const Point(300, 150));
    });

    test('a moved connector snaps back to its shapes', () {
      final dragged = connector.copyWith(
        firstPosition: const Point(1000, 1000),
        secondPosition: const Point(1200, 1000),
      );
      final updates = rerouteConnectors(content, {
        'c': [dragged],
      });
      _expectPoint(updates['c']!.firstPosition, const Point(100, 50));
    });

    test('unrelated changes do not touch connectors', () {
      final other = _rect('z', 0, 500);
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

    test('missing targets leave the connector untouched', () {
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
    });
  });

  group('deletion and duplication', () {
    final connector = createConnector(a, b, id: 'c')!;
    final content = <PadElement>[a, b, connector];

    test('removing a shape reports its connectors', () {
      expect(danglingConnectors(content, ['a']), {'c'});
      expect(danglingConnectors(content, ['a', 'c']), isEmpty);
      expect(danglingConnectors(content, ['z']), isEmpty);
    });

    test('duplicating shapes with connector remaps references', () {
      var counter = 0;
      final copies = regenerateElementIds(content, () => 'n${counter++}');
      expect(copies.map((e) => e.id), ['n0', 'n1', 'n2']);
      expect(copies[2].connector, const ConnectorReference('n0', 'n1'));
    });

    test('duplicating only the connector detaches it', () {
      final copies = regenerateElementIds([connector], () => 'n');
      expect(copies.single.isConnector, isFalse);
      expect(copies.single.extra.containsKey(kConnectorExtraKey), isFalse);
      expect((copies.single as ShapeElement).property.shape, isA<LineShape>());
    });
  });

  group('persistence', () {
    test('survives json and document round trips', () {
      final connector = createConnector(a, b, id: 'c')!;
      final page = DocumentPage(
        layers: [
          DocumentLayer(id: 'layer', content: [a, b, connector]),
        ],
      );
      final (data, name) = NoteData(Archive()).setPage(page, 'Page');
      final loaded = NoteData.fromData(data.exportAsBytes()).getPage(name)!;
      final element = loaded.content.firstWhere((e) => e.id == 'c');
      expect(element.connector, const ConnectorReference('a', 'b'));
      expect(element, connector);
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
}
