import 'dart:convert';
import 'dart:math' show Point;
import 'dart:typed_data';

import 'package:butterfly/api/file_system.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:butterfly/models/defaults.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/views/amaze/objects/object_favorites.dart';
import 'package:butterfly/views/amaze/objects/object_library.dart';
import 'package:butterfly/views/amaze/objects/object_store.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mocks.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
const _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
    '<rect width="10" height="10"/></svg>';

ButterflyComponent _component({
  Uint8List? thumbnail,
  List<PadElement>? elements,
}) => ButterflyComponent(
  thumbnail: thumbnail,
  elements:
      elements ??
      [
        PadElement.shape(
          firstPosition: const Point(-50.0, -25.0),
          secondPosition: const Point(50.0, 25.0),
        ),
      ],
);

ObjectEntry _entry(String packId, String packName, String key) =>
    ObjectEntry.fromComponent(
      packId,
      packName,
      NamedItem(name: key, item: _component()),
    );

ObjectPack _pack(
  String id,
  List<String> keys, {
  String? name,
  ObjectPackSource source = .user,
}) {
  final packName = name ?? id;
  return ObjectPack(
    id: id,
    name: packName,
    editable: source == .user,
    source: source,
    objects: [for (final key in keys) _entry(id, packName, key)],
  );
}

NoteData _packData(String name, Map<String, ButterflyComponent> components) {
  var data = DocumentDefaults.createPack();
  data = data.setMetadata(data.getMetadata()!.copyWith(name: name));
  for (final MapEntry(:key, :value) in components.entries) {
    data = data.setComponent(key, value);
  }
  return data;
}

class _FailingFileSystem extends MockButterflyFileSystem {
  @override
  Future<List<(String, NoteData)>> getCoreAndUserPacks([
    ExternalStorage? storage,
  ]) async => throw StateError('broken pack system');
}

Finder _tile(String packId, String key) =>
    find.byKey(ValueKey(('amaze-object', packId, key)));
Finder _favoriteTile(String packId, String key) =>
    find.byKey(ValueKey(('amaze-object-favorite', packId, key)));
Finder _star(String packId, String key) =>
    find.byKey(ValueKey(('amaze-object-star', packId, key)));
Finder _packHeader(String id) =>
    find.byKey(ValueKey(('amaze-object-pack', id)));
const _favorites = ValueKey('amaze-objects-favorites');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(width: kObjectLibraryWidth, child: child),
      ),
    ),
  );

  Future<List<ObjectEntry>> pumpPanel(
    WidgetTester tester,
    List<ObjectPack> packs, {
    bool editable = true,
  }) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final placed = <ObjectEntry>[];
    await tester.pumpWidget(
      host(
        ObjectLibraryPanel(
          editable: editable,
          onClose: () {},
          onPlace: placed.add,
          loadPacks: () async => packs,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return placed;
  }

  group('splitObjectName', () {
    test('splits category and name', () {
      final split = splitObjectName('Living — Sofa');
      expect(split.category, 'Living');
      expect(split.name, 'Sofa');
    });

    test('a key without separator has no category', () {
      final split = splitObjectName('Sofa');
      expect(split.category, isNull);
      expect(split.name, 'Sofa');
    });

    test('only the first separator splits', () {
      final split = splitObjectName('Living — Sofa — Large');
      expect(split.category, 'Living');
      expect(split.name, 'Sofa — Large');
    });
  });

  group('loading', () {
    test('user and core packs are loaded with their objects', () async {
      final fs = MockButterflyFileSystem();
      final system = fs.buildPackSystem();
      await system.initialize();
      await system.createFile(
        kCorePackFileName,
        _packData('Core', {'Lamp': _component()}),
      );
      await system.createFile(
        'Furniture.bfly',
        _packData('Furniture', {
          'Living — Sofa': _component(),
          'Living — Chair': _component(),
          'Kitchen — Sink': _component(),
        }),
      );
      final installed = await fs.getCoreAndUserPacks();
      final coreCount = installed
          .firstWhere((e) => e.$1 == kCorePackFileName)
          .$2
          .getNamedComponents()
          .length;

      final packs = await loadObjectPacks(fs);

      final core = packs.firstWhere((p) => p.id == kCorePackFileName);
      final user = packs.firstWhere((p) => p.id == 'Furniture.bfly');
      expect(core.source, ObjectPackSource.core);
      expect(core.editable, isFalse);
      expect(core.objects, hasLength(coreCount));
      expect(core.objects.map((e) => e.key), contains('Lamp'));
      expect(user.name, 'Furniture');
      expect(user.editable, isTrue);
      expect(user.objects, hasLength(3));
      expect(
        user.objects.map((e) => e.name),
        containsAll(['Sofa', 'Chair', 'Sink']),
      );
    });

    test('a pack that fails to load is skipped', () async {
      final fs = MockButterflyFileSystem();
      final system = fs.buildPackSystem();
      await system.initialize();
      await system.createFile(
        'Furniture.bfly',
        _packData('Furniture', {'Sofa': _component()}),
      );
      final packs = await loadObjectPacks(fs, bundled: ['packs/missing.bfly']);
      expect(packs.map((p) => p.id), contains('Furniture.bfly'));
      expect(packs.map((p) => p.id), isNot(contains(startsWith('bundled:'))));

      expect(await loadObjectPacks(_FailingFileSystem()), isEmpty);
    });

    test('an empty pack is hidden', () async {
      final fs = MockButterflyFileSystem();
      final system = fs.buildPackSystem();
      await system.initialize();
      await system.createFile('Empty.bfly', _packData('Empty', {}));
      final packs = await loadObjectPacks(fs);
      expect(packs.map((p) => p.id), isNot(contains('Empty.bfly')));
    });

    testWidgets('the panel shows each pack with its object count', (
      tester,
    ) async {
      await pumpPanel(tester, [
        _pack('Furniture.bfly', ['Sofa', 'Chair', 'Sink'], name: 'Furniture'),
        _pack(kCorePackFileName, ['Lamp'], name: 'Core', source: .core),
      ]);
      expect(_packHeader('Furniture.bfly'), findsOneWidget);
      expect(_packHeader(kCorePackFileName), findsOneWidget);
      Finder count(String id) =>
          find.byKey(ValueKey(('amaze-object-pack-count', id)));
      expect(tester.widget<Text>(count('Furniture.bfly')).data, '3');
      expect(tester.widget<Text>(count(kCorePackFileName)).data, '1');
    });

    testWidgets('no packs shows the empty state', (tester) async {
      await pumpPanel(tester, []);
      expect(find.text('No objects yet'), findsOneWidget);
    });
  });

  testWidgets('categories follow uncategorized objects in first-seen order', (
    tester,
  ) async {
    const id = 'Furniture.bfly';
    await pumpPanel(tester, [
      _pack(id, ['Living — Sofa', 'Kitchen — Sink', 'Lamp', 'Living — Chair']),
    ]);
    final living = find.byKey(
      const ValueKey(('amaze-object-category', id, 'Living')),
    );
    final kitchen = find.byKey(
      const ValueKey(('amaze-object-category', id, 'Kitchen')),
    );
    expect(living, findsOneWidget);
    expect(kitchen, findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(_tile(id, 'Lamp')), lessThan(top(living)));
    expect(top(living), lessThan(top(_tile(id, 'Living — Sofa'))));
    expect(top(_tile(id, 'Living — Sofa')), top(_tile(id, 'Living — Chair')));
    expect(
      tester.getTopLeft(_tile(id, 'Living — Sofa')).dx,
      lessThan(tester.getTopLeft(_tile(id, 'Living — Chair')).dx),
    );
    expect(top(_tile(id, 'Living — Chair')), lessThan(top(kitchen)));
    expect(top(kitchen), lessThan(top(_tile(id, 'Kitchen — Sink'))));
    expect(find.text('Sofa'), findsOneWidget);
  });

  testWidgets('tiles are at least 80 × 96', (tester) async {
    const id = 'Furniture.bfly';
    await pumpPanel(tester, [
      _pack(id, ['Sofa', 'A very long object name that needs two lines']),
    ]);
    final size = tester.getSize(_tile(id, 'Sofa'));
    expect(size.width, greaterThanOrEqualTo(80));
    expect(size.height, greaterThanOrEqualTo(96));
    expect(tester.getSize(_star(id, 'Sofa')), const Size(32, 32));
  });

  testWidgets('search matches name, category and pack name', (tester) async {
    const id = 'Furniture.bfly';
    await pumpPanel(tester, [
      _pack(id, ['Living — Sofa', 'Kitchen — Sink', 'Kitchen — Oven']),
      _pack('Garden.bfly', ['Tree']),
    ]);
    final search = find.byKey(const ValueKey('amaze-objects-search'));

    await tester.enterText(search, 'sof');
    await tester.pumpAndSettle();
    expect(_tile(id, 'Living — Sofa'), findsOneWidget);
    expect(_tile(id, 'Kitchen — Sink'), findsNothing);
    expect(_packHeader('Garden.bfly'), findsNothing);

    await tester.enterText(search, 'KITCHEN');
    await tester.pumpAndSettle();
    expect(_tile(id, 'Kitchen — Sink'), findsOneWidget);
    expect(_tile(id, 'Kitchen — Oven'), findsOneWidget);
    expect(_tile(id, 'Living — Sofa'), findsNothing);

    await tester.enterText(search, 'garden');
    await tester.pumpAndSettle();
    expect(_tile('Garden.bfly', 'Tree'), findsOneWidget);

    await tester.enterText(search, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No objects found'), findsOneWidget);
  });

  group('favorites', () {
    testWidgets('starring and unstarring an object', (tester) async {
      const id = 'Furniture.bfly';
      await pumpPanel(tester, [
        _pack(id, ['Living — Sofa', 'Lamp']),
      ]);
      expect(find.byKey(_favorites), findsNothing);

      await tester.tap(_star(id, 'Living — Sofa'));
      await tester.pumpAndSettle();
      expect(find.byKey(_favorites), findsOneWidget);
      expect(_favoriteTile(id, 'Living — Sofa'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(kObjectFavoritesKey), ['$id|Living — Sofa']);

      await tester.tap(
        find.byKey(
          const ValueKey(('amaze-object-favorite-star', id, 'Living — Sofa')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_favorites), findsNothing);
      expect(prefs.getStringList(kObjectFavoritesKey), isEmpty);
    });

    testWidgets('a starred pack moves to the top', (tester) async {
      await pumpPanel(tester, [
        _pack(kCorePackFileName, ['Lamp'], source: .core),
        _pack('Furniture.bfly', ['Sofa']),
      ]);
      double top(String id) => tester.getTopLeft(_packHeader(id)).dy;
      expect(top(kCorePackFileName), lessThan(top('Furniture.bfly')));

      await tester.tap(
        find.byKey(
          const ValueKey(('amaze-object-pack-star', 'Furniture.bfly')),
        ),
      );
      await tester.pumpAndSettle();
      expect(top('Furniture.bfly'), lessThan(top(kCorePackFileName)));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(kObjectFavoritePacksKey), ['Furniture.bfly']);
    });

    testWidgets('packs are ordered bundled, core, then users alphabetically', (
      tester,
    ) async {
      await pumpPanel(tester, [
        _pack('b.bfly', ['B'], name: 'beta'),
        _pack(kCorePackFileName, ['Lamp'], source: .core),
        _pack('a.bfly', ['A'], name: 'Alpha'),
        _pack('bundled:x', ['X'], source: .bundled),
      ]);
      final order = [
        'bundled:x',
        kCorePackFileName,
        'a.bfly',
        'b.bfly',
      ].map((id) => tester.getTopLeft(_packHeader(id)).dy).toList();
      expect(order, [...order]..sort());
    });

    testWidgets('a favorite of a deleted object is not shown', (tester) async {
      SharedPreferences.setMockInitialValues({
        kObjectFavoritesKey: ['Furniture.bfly|Gone', 'Furniture.bfly|Sofa'],
      });
      await pumpPanel(tester, [
        _pack('Furniture.bfly', ['Sofa']),
      ]);
      expect(find.byKey(_favorites), findsOneWidget);
      expect(_favoriteTile('Furniture.bfly', 'Sofa'), findsOneWidget);
      expect(_favoriteTile('Furniture.bfly', 'Gone'), findsNothing);
    });
  });

  testWidgets('collapsing a pack is remembered after a rebuild', (
    tester,
  ) async {
    const id = 'Furniture.bfly';
    final packs = [
      _pack(id, ['Sofa']),
    ];
    await pumpPanel(tester, packs);
    expect(_tile(id, 'Sofa'), findsOneWidget);

    await tester.tap(_packHeader(id));
    await tester.pumpAndSettle();
    expect(_tile(id, 'Sofa'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pumpPanel(tester, packs);
    expect(_packHeader(id), findsOneWidget);
    expect(_tile(id, 'Sofa'), findsNothing);

    await tester.tap(_packHeader(id));
    await tester.pumpAndSettle();
    expect(_tile(id, 'Sofa'), findsOneWidget);
  });

  testWidgets('read-only tiles are disabled and explain why', (tester) async {
    const id = 'Furniture.bfly';
    final placed = await pumpPanel(tester, [
      _pack(id, ['Sofa']),
    ], editable: false);
    await tester.tap(_tile(id, 'Sofa'));
    await tester.pumpAndSettle();
    expect(placed, isEmpty);
    expect(
      find.descendant(
        of: _tile(id, 'Sofa'),
        matching: find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == "This drawing can't be edited",
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a tap places the object', (tester) async {
    const id = 'Furniture.bfly';
    final placed = await pumpPanel(tester, [
      _pack(id, ['Sofa']),
    ]);
    await tester.tap(_tile(id, 'Sofa'));
    await tester.pumpAndSettle();
    expect(placed.map((e) => e.key), ['Sofa']);
  });

  group('preview', () {
    Future<void> pumpPreview(
      WidgetTester tester,
      ButterflyComponent component,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox.square(
            dimension: 80,
            child: ObjectPreview(component: component),
          ),
        ),
      );
      await tester.pump();
    }

    const image = ValueKey('amaze-object-preview-image');
    const svg = ValueKey('amaze-object-preview-svg');
    const icon = ValueKey('amaze-object-preview-icon');

    testWidgets('a thumbnail is shown as an image', (tester) async {
      await pumpPreview(
        tester,
        _component(thumbnail: base64Decode(_pngBase64)),
      );
      expect(find.byKey(image), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('an SVG data URI is drawn as SVG', (tester) async {
      final source = UriData.fromString(
        _svg,
        mimeType: 'image/svg+xml',
        base64: true,
      ).toString();
      await pumpPreview(
        tester,
        _component(
          elements: [PadElement.svg(source: source, width: 10, height: 10)],
        ),
      );
      expect(find.byKey(svg), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('anything else shows the shapes icon', (tester) async {
      await pumpPreview(tester, _component());
      expect(find.byKey(icon), findsOneWidget);
      await pumpPreview(
        tester,
        _component(
          elements: [
            PadElement.svg(source: 'assets/x.svg', width: 10, height: 10),
          ],
        ),
      );
      expect(find.byKey(icon), findsOneWidget);
    });
  });
}
