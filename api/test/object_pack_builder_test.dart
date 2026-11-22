import 'dart:convert';
import 'dart:io';

import 'package:butterfly_api/butterfly_api.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../tool/object_pack_builder.dart';

final _furnitureSpec = File('tool/object_packs/furniture/pack.json');

const _categories = [
  'Living',
  'Dining',
  'Kitchen',
  'Bedroom',
  'Bathroom',
  'Laundry',
  'Garage',
  'Shop',
  'Sunroom',
  'Office / Storage',
  'HVAC',
  'Framing',
];

const _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100">'
    '<rect width="200" height="100"/></svg>';

List<SvgElement> _elements(NoteData pack) => [
  for (final item in pack.getNamedComponents())
    ...item.item.elements.cast<SvgElement>(),
];

/// The stored component JSON. Reading a component back gives elements
/// without an id a random one, so the raw archive entries are compared.
Map<String, String> _componentJson(NoteData pack) => {
  for (final name in pack.getComponents())
    name: utf8.decode(
      pack.getAsset('$kComponentsArchiveDirectory/$name.json')!,
    ),
};

void main() {
  group('furniture pack', () {
    late BuildResult result;
    late NoteData pack;

    setUpAll(() async {
      result = await buildObjectPack(_furnitureSpec);
      pack = result.pack;
    });

    test('has 96 components and the pack metadata', () {
      expect(result.objectCount, 96);
      expect(pack.getNamedComponents(), hasLength(96));
      final metadata = pack.getMetadata()!;
      expect(metadata.type, NoteFileType.pack);
      expect(metadata.name, 'Furniture (to scale)');
      expect(metadata.version, '1.0.0');
      expect(metadata.author, 'FloorPlanner contributors · CC0-1.0');
      expect(result.warnings, isEmpty);
    });

    test('the sofa is 84 × 36 inches, centered on the origin', () {
      final sofa = pack.getComponent('Living — Sofa')!;
      expect(sofa.thumbnail, isNull);
      expect(sofa.elements, hasLength(1));
      final element = sofa.elements.single as SvgElement;
      expect(element.width, closeTo(8064, 0.01));
      expect(element.height, closeTo(3456, 0.01));
      expect(element.position.x + element.width / 2, closeTo(0, 0.01));
      expect(element.position.y + element.height / 2, closeTo(0, 0.01));
    });

    test('every source is an SVG data URI with well-formed XML', () {
      for (final element in _elements(pack)) {
        expect(element.source, startsWith('data:image/svg+xml'));
        final data = UriData.parse(element.source);
        expect(data.mimeType, 'image/svg+xml');
        final document = XmlDocument.parse(utf8.decode(data.contentAsBytes()));
        expect(document.rootElement.name.local, 'svg');
      }
    });

    test('every element names its license and furnishing height', () {
      for (final element in _elements(pack)) {
        final source = element.extra['source'] as Map;
        expect(source['license'], 'CC0-1.0');
        expect(source['pack'], 'furniture');
        final furnishing = element.extra['furnishing'] as Map;
        expect(furnishing['heightIn'], isA<num>());
      }
    });

    test('the sofa keeps its furnishing facts', () {
      final element =
          pack.getComponent('Living — Sofa')!.elements.single as SvgElement;
      final furnishing = element.extra['furnishing'] as Map;
      expect(furnishing['id'], 'sofa');
      expect(furnishing['heightIn'], 32);
      expect(furnishing['elevationIn'], 0);
      expect(furnishing['form'], 'seat');
      expect(furnishing['material'], 'soft');
      expect(furnishing['priceUsd'], 650.0);
      expect(furnishing['widthIn'], 84);
      expect(furnishing['depthIn'], 36);
    });

    test('names are unique and all 12 categories appear', () {
      final names = pack.getComponents().toList();
      expect(names.toSet(), hasLength(names.length));
      final categories = names.map((e) => e.split(' — ').first).toSet();
      expect(categories, containsAll(_categories));
      expect(categories, hasLength(12));
    });

    test('two builds give identical components', () async {
      final again = await buildObjectPack(_furnitureSpec);
      expect(_componentJson(again.pack), _componentJson(pack));
    });
  });

  group('small specs', () {
    late Directory directory;

    setUp(() => directory = Directory.systemTemp.createTempSync('pack_test'));
    tearDown(() => directory.deleteSync(recursive: true));

    File writeSpec({
      String sizing = 'longestSide',
      List<Map<String, Object?>>? objects,
      Map<String, String> files = const {'a.svg': _svg},
    }) {
      for (final MapEntry(:key, :value) in files.entries) {
        File('${directory.path}/$key').writeAsStringSync(value);
      }
      return File('${directory.path}/spec.json')..writeAsStringSync(
        jsonEncode({
          'id': 'test',
          'name': 'Test',
          'description': 'A test pack.',
          'author': 'Tester',
          'license': 'CC0-1.0',
          'licenseUrl': 'https://creativecommons.org/publicdomain/zero/1.0/',
          'sourceUrl': 'https://example.com',
          'version': '0.1.0',
          'sizing': sizing,
          'longestSideIn': 10,
          'objects':
              objects ??
              [
                {'name': 'Box', 'file': 'a.svg'},
              ],
        }),
      );
    }

    Matcher failsNaming(String text) => throwsA(
      isA<ObjectPackBuildException>().having(
        (e) => e.message,
        'message',
        contains(text),
      ),
    );

    test('longestSide keeps the aspect ratio', () async {
      final result = await buildObjectPack(writeSpec());
      final component = result.pack.getComponent('Box')!;
      final element = component.elements.single as SvgElement;
      expect(element.width, closeTo(960, 0.01));
      expect(element.height, closeTo(480, 0.01));
      expect(element.position.x, closeTo(-480, 0.01));
      expect(element.position.y, closeTo(-240, 0.01));
      expect(element.extra.containsKey('furnishing'), isFalse);
      expect((element.extra['source'] as Map)['pack'], 'test');
    });

    test('a viewBox far from the spec size warns and uses the spec', () async {
      final result = await buildObjectPack(
        writeSpec(
          sizing: 'inches',
          objects: [
            {'name': 'Box', 'file': 'a.svg', 'widthIn': 20, 'depthIn': 10},
          ],
        ),
      );
      expect(result.warnings.single, contains('a.svg'));
      final element =
          result.pack.getComponent('Box')!.elements.single as SvgElement;
      expect(element.width, closeTo(1920, 0.01));
      expect(element.height, closeTo(960, 0.01));
    });

    test('a missing file fails', () {
      expect(
        buildObjectPack(
          writeSpec(
            objects: [
              {'name': 'Box', 'file': 'missing.svg'},
            ],
          ),
        ),
        failsNaming('missing.svg'),
      );
    });

    test('a script fails', () {
      expect(
        buildObjectPack(
          writeSpec(
            files: {
              'a.svg':
                  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">'
                  '<script>alert(1)</script></svg>',
            },
          ),
        ),
        failsNaming('a.svg'),
      );
    });

    test('an external link fails, internal and data links pass', () async {
      const internal =
          '<svg xmlns="http://www.w3.org/2000/svg" '
          'xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 2 1">'
          '<defs><rect id="r" width="1" height="1"/></defs>'
          '<use href="#r"/><image xlink:href="data:image/png;base64,AA=="/>'
          '</svg>';
      await buildObjectPack(writeSpec(files: {'a.svg': internal}));
      expect(
        buildObjectPack(
          writeSpec(
            files: {
              'a.svg':
                  '<svg xmlns="http://www.w3.org/2000/svg" '
                  'xmlns:xlink="http://www.w3.org/1999/xlink" '
                  'viewBox="0 0 1 1">'
                  '<image xlink:href="https://example.com/a.png"/></svg>',
            },
          ),
        ),
        failsNaming('a.svg'),
      );
    });

    test('malformed XML fails', () {
      expect(
        buildObjectPack(
          writeSpec(
            files: {
              'a.svg': '<svg xmlns="http://www.w3.org/2000/svg"><rect></svg>',
            },
          ),
        ),
        failsNaming('a.svg'),
      );
    });

    test('a duplicate name fails', () {
      expect(
        buildObjectPack(
          writeSpec(
            objects: [
              {'name': 'Box', 'category': 'Toys', 'file': 'a.svg'},
              {'name': 'Box', 'category': 'Toys', 'file': 'a.svg'},
            ],
          ),
        ),
        failsNaming('Toys — Box'),
      );
    });
  });
}
