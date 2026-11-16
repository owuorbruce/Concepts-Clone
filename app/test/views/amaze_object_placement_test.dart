import 'dart:convert';
import 'dart:math' show Point;

import 'package:butterfly/actions/shortcuts.dart';
import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/api/open.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/embed/embedding.dart';
import 'package:butterfly/models/defaults.dart';
import 'package:butterfly/services/font.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/theme.dart';
import 'package:butterfly/views/main.dart';
import 'package:butterfly/views/amaze/objects/object_placement.dart';
import 'package:butterfly/views/amaze/shell.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:lw_sysapi/lw_sysapi.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mocks.dart';

const _dockButton = ValueKey('amaze-dock-objects');
const _panel = ValueKey('amaze-object-library');
const _packId = 'Furniture.bfly';
const _key = 'Living — Sofa';
const _tile = ValueKey(('amaze-object', _packId, _key));

/// A 100 × 50 rectangle centered at (0, 0), like a stored component.
ButterflyComponent _sofa() => ButterflyComponent(
  elements: [
    PadElement.shape(
      id: 'stored',
      firstPosition: const Point(-50.0, -25.0),
      secondPosition: const Point(50.0, 25.0),
      property: const ShapeProperty(shape: RectangleShape(), strokeWidth: 4),
    ),
  ],
);

const _boxKey = 'Living — Box';
const _boxTile = ValueKey(('amaze-object', _packId, _boxKey));
const _credits = {
  'source': {'pack': 'test', 'license': 'CC0-1.0'},
  'furnishing': {'id': 'box', 'heightIn': 30},
};

/// A component like the furniture pack's: one SVG, 200 × 100 around (0, 0).
ButterflyComponent _svgComponent(String body) => ButterflyComponent(
  elements: [
    PadElement.svg(
      source: Uri.dataFromString(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 10">'
        '$body</svg>',
        mimeType: 'image/svg+xml',
        encoding: utf8,
      ).toString(),
      position: const Point(-100.0, -50.0),
      width: 200,
      height: 100,
      extra: _credits,
    ),
  ],
);

ButterflyComponent _box() => _svgComponent(
  '<rect x="0.5" y="0.5" width="19" height="9" fill="#cbd5e1" '
  'stroke="#374151"/><line x1="10" y1="0.5" x2="10" y2="9.5" '
  'stroke="#374151"/>',
);

/// The bounds of the points of [elements].
Rect _penBounds(Iterable<PadElement> elements) {
  final points = [
    for (final element in elements)
      for (final p in (element as PenElement).points) Offset(p.x, p.y),
  ];
  return points
      .skip(1)
      .fold(
        Rect.fromPoints(points.first, points.first),
        (rect, p) => rect.expandToInclude(Rect.fromPoints(p, p)),
      );
}

Rect _shapeRect(PadElement element) {
  final shape = element as ShapeElement;
  return Rect.fromPoints(
    Offset(shape.firstPosition.x, shape.firstPosition.y),
    Offset(shape.secondPosition.x, shape.secondPosition.y),
  );
}

class _Observer extends BlocObserver {
  DocumentBloc? bloc;
  final created = <ElementsCreated>[];

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    if (bloc is DocumentBloc) this.bloc = bloc;
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    if (event is ElementsCreated) created.add(event);
  }
}

void main() {
  group('placeComponentAt', () {
    test('an SVG object becomes pen strokes in its box', () {
      final placed = placeComponentAt(_box(), const Offset(500, 300));
      expect(placed, hasLength(2));
      expect(placed, everyElement(isA<PenElement>()));
      final bounds = _penBounds(placed);
      expect(
        bounds.center,
        offsetMoreOrLessEquals(const Offset(500, 300), epsilon: 0.5),
      );
      // The rect is inset half a unit: 190 × 90 of the 200 × 100 box.
      expect(bounds.width, moreOrLessEquals(190, epsilon: 0.01));
      expect(bounds.height, moreOrLessEquals(90, epsilon: 0.01));
      for (final element in placed) {
        expect(element.extra, _credits);
        expect(element.id, isNotNull);
      }
      expect(placed.map((e) => e.id).toSet(), hasLength(placed.length));
    });

    test('an unsupported SVG stays an SVG element', () {
      final placed = placeComponentAt(
        _svgComponent('<rect width="20" height="10" transform="rotate(10)"/>'),
        const Offset(500, 300),
      );
      final element = placed.single as SvgElement;
      expect(element.position.x, moreOrLessEquals(400));
      expect(element.position.y, moreOrLessEquals(250));
      expect(element.extra, _credits);
    });

    test('places the component at real size around the point', () {
      final placed = placeComponentAt(_sofa(), const Offset(500, 300));
      expect(placed, hasLength(1));
      final rect = _shapeRect(placed.single);
      expect(rect.center, offsetMoreOrLessEquals(const Offset(500, 300)));
      expect(rect.width, moreOrLessEquals(100));
      expect(rect.height, moreOrLessEquals(50));
    });

    test('every placement gets new ids', () {
      final first = placeComponentAt(_sofa(), Offset.zero).single.id;
      final second = placeComponentAt(_sofa(), Offset.zero).single.id;
      expect(first, isNotNull);
      expect(first, isNot('stored'));
      expect(second, isNot('stored'));
      expect(first, isNot(second));
    });

    test('a zero-size target keeps the stamp math at 1:1', () {
      expect(
        calculateComponentScale(const Rect.fromLTWH(0, 0, 10, 10), Rect.zero),
        (1.0, 1.0),
      );
      expect(
        calculateComponentScale(
          const Rect.fromLTWH(0, 0, 10, 20),
          const Rect.fromLTWH(5, 5, 20, 10),
        ),
        (2.0, 0.5),
      );
    });
  });

  group('in the editor', () {
    late MockSettingsCubit settingsCubit;
    late MockButterflyFileSystem fileSystem;
    late WindowCubit windowCubit;
    late GoRouter router;
    late _Observer observer;
    late BlocObserver previousObserver;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      registerFallbackValue(AssetLocation.empty);
      SharedPreferences.setMockInitialValues({});
      await keybinder.ready;
      FlutterSecureStorage.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), (
            call,
          ) async {
            return switch (call.method) {
              'isMaximized' ||
              'isMinimized' ||
              'isFullScreen' ||
              'isPreventClose' ||
              'isAlwaysOnTop' ||
              'isSkipTaskbar' => false,
              _ => null,
            };
          });
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'amaze.toolWheel.diameter': 320.0,
      });
      settingsCubit = MockSettingsCubit();
      fileSystem = MockButterflyFileSystem(settingsCubit: settingsCubit);
      windowCubit = WindowCubit(fullScreen: false);
      observer = _Observer();
      previousObserver = Bloc.observer;
      Bloc.observer = observer;
      const settings = ButterflySettings(
        defaultTemplate: 'default',
        autosave: false,
        flags: [kAmazeShellFlag],
      );
      when(() => settingsCubit.state).thenReturn(settings);
      when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
      when(() => settingsCubit.getRemote(any())).thenReturn(null);
      when(() => settingsCubit.addRecentHistory(any()))
          .thenAnswer((_) async {});
    });

    tearDown(() async {
      Bloc.observer = previousObserver;
      router.dispose();
      await windowCubit.close();
    });

    void setScreen(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<void> pumpUntil(
      WidgetTester tester,
      bool Function() condition,
      String description,
    ) async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        if (condition()) return;
      }
      fail('Timed out waiting for $description');
    }

    Widget buildApp(NoteData document) {
      fileSystem.buildTemplateSystem().updateFile('default', document);
      router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const ValueKey('open-document'),
                  onPressed: () => openFile(
                    context,
                    true,
                    AssetLocation.local('amaze.bfly'),
                    document,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
            routes: [
              GoRoute(
                name: 'local',
                path: 'local/:path(.*)',
                builder: (context, state) => ProjectPage(
                  data: state.extra ?? document,
                  location: AssetLocation.local(
                    state.pathParameters['path'] ?? '',
                  ),
                ),
              ),
            ],
          ),
        ],
      );
      return MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ButterflyFileSystem>.value(value: fileSystem),
          RepositoryProvider<FontService>(
            create: (context) => FontService(fileSystem),
          ),
          RepositoryProvider<ClipboardManager>.value(
            value: UnsupportedClipboardManager(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsCubit>.value(value: settingsCubit),
            BlocProvider<WindowCubit>.value(value: windowCubit),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            debugShowCheckedModeBanner: false,
            theme: getThemeData('', false),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              LeapLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
    }

    Future<EditorController> openEditor(WidgetTester tester) async {
      await tester.runAsync(() async {
        final system = fileSystem.buildPackSystem();
        await system.initialize();
        var pack = DocumentDefaults.createPack();
        pack = pack.setMetadata(
          pack.getMetadata()!.copyWith(name: 'Furniture'),
        );
        await system.createFile(
          _packId,
          pack.setComponent(_key, _sofa()).setComponent(_boxKey, _box()),
        );
      });
      final document = DocumentDefaults.createDocument(name: 'Objects');
      await tester.pumpWidget(buildApp(document));
      await tester.tap(find.byKey(const ValueKey('open-document')));
      await pumpUntil(
        tester,
        () => observer.bloc?.state is DocumentLoadSuccess,
        'document open',
      );
      await tester.pumpAndSettle();
      return observer.bloc!.editorController;
    }

    DocumentLoadSuccess state() => observer.bloc!.state as DocumentLoadSuccess;
    List<ShapeElement> shapes() =>
        state().page.content.whereType<ShapeElement>().toList();

    Future<void> openPanel(WidgetTester tester) async {
      await tester.tap(find.byKey(_dockButton));
      await pumpUntil(
        tester,
        () => find.byKey(_tile).evaluate().isNotEmpty,
        'object tiles',
      );
      await tester.pumpAndSettle();
    }

    Offset screenToWorld(EditorController editor, Offset screen) =>
        editor.transformCubit.state.localToGlobal(screen);

    testWidgets('the dock button, close button and Escape toggle the panel', (
      tester,
    ) async {
      setScreen(tester, const Size(1280, 800));
      await openEditor(tester);
      expect(find.byKey(_panel), findsNothing);

      await openPanel(tester);
      expect(find.byKey(_panel), findsOneWidget);
      expect(tester.getSize(find.byKey(_panel)).width, 360);
      expect(tester.getTopRight(find.byKey(_panel)).dx, 1280);
      await tester.tap(find.byKey(_dockButton));
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsNothing);

      await openPanel(tester);
      await tester.tap(find.byKey(const ValueKey('amaze-objects-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsNothing);

      await openPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the panel fills narrow screens', (tester) async {
      setScreen(tester, const Size(400, 800));
      await openEditor(tester);
      await openPanel(tester);
      expect(tester.getSize(find.byKey(_panel)).width, 400);
    });

    for (final (name, zoom, pan) in [
      ('at zoom 1', 1.0, Offset.zero),
      ('at zoom 4', 4.0, Offset.zero),
      ('at zoom 0.25', 0.25, Offset.zero),
      ('after a pan', 1.0, const Offset(-640, 275)),
    ]) {
      testWidgets('a tap places one object mid-canvas $name', (tester) async {
        setScreen(tester, const Size(1280, 800));
        final editor = await openEditor(tester);
        editor.transformCubit.teleport(pan, zoom);
        await tester.pumpAndSettle();
        await openPanel(tester);
        final before = shapes().length;
        final context = tester.element(find.byKey(_panel));
        final expected = visibleCanvasCenter(context);
        expect(
          expected,
          offsetMoreOrLessEquals(
            screenToWorld(editor, const Offset(640, 400)),
            epsilon: 0.5,
          ),
        );

        await tester.tap(find.byKey(_tile));
        await pumpUntil(tester, () => shapes().length > before, 'placement');
        await tester.pumpAndSettle();

        expect(observer.created, hasLength(1));
        final event = observer.created.single;
        expect(event.pageName, state().pageName);
        expect(event.layer, state().currentLayer);
        expect(shapes(), hasLength(before + 1));
        final rect = _shapeRect(shapes().last);
        expect(rect.center, offsetMoreOrLessEquals(expected, epsilon: 0.5));
        expect(rect.size, const Size(100, 50));
        expect(find.byKey(_panel), findsOneWidget);

        // The wheel's undo button is under the panel here.
        observer.bloc!.sendUndo();
        await pumpUntil(tester, () => shapes().length == before, 'undo');
        expect(tester.takeException(), isNull);
      });
    }

    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      testWidgets('dragging with a ${kind.name} drops the object there', (
        tester,
      ) async {
        setScreen(tester, const Size(1280, 800));
        final editor = await openEditor(tester);
        editor.transformCubit.teleport(const Offset(100, -50), 2);
        await tester.pumpAndSettle();
        await openPanel(tester);
        final before = shapes().length;
        const drop = Offset(420, 360);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_tile)),
          kind: kind,
        );
        if (kind == PointerDeviceKind.touch) {
          await tester.pump(const Duration(milliseconds: 700));
        }
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
        await gesture.moveTo(drop);
        await tester.pump();
        await gesture.up();
        await pumpUntil(tester, () => shapes().length > before, 'drop');
        await tester.pumpAndSettle();

        expect(observer.created, hasLength(1));
        final rect = _shapeRect(shapes().last);
        expect(
          rect.center,
          offsetMoreOrLessEquals(screenToWorld(editor, drop), epsilon: 0.5),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('dropping on the panel adds nothing', (tester) async {
      setScreen(tester, const Size(1280, 800));
      await openEditor(tester);
      await openPanel(tester);
      final before = shapes().length;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_tile)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byKey(_panel)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(observer.created, isEmpty);
      expect(shapes(), hasLength(before));
    });

    testWidgets('a placed SVG object is one undo step of pen strokes', (
      tester,
    ) async {
      setScreen(tester, const Size(1280, 800));
      await openEditor(tester);
      await openPanel(tester);
      final before = state().page.content.length;
      final center = visibleCanvasCenter(tester.element(find.byKey(_panel)));

      await tester.tap(find.byKey(_boxTile));
      await pumpUntil(
        tester,
        () => state().page.content.length > before,
        'placement',
      );
      await tester.pumpAndSettle();
      expect(observer.created, hasLength(1));
      final created = observer.created.single.elements;
      expect(created, hasLength(2));
      expect(created, everyElement(isA<PenElement>()));
      final added = state().page.content.skip(before).toList();
      expect(added, hasLength(2));
      expect(added, everyElement(isA<PenElement>()));
      expect(
        _penBounds(added).center,
        offsetMoreOrLessEquals(center, epsilon: 0.5),
      );
      for (final element in added) {
        expect(element.extra, _credits);
      }

      observer.bloc!.sendUndo();
      await pumpUntil(
        tester,
        () => state().page.content.length == before,
        'undo',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap adds nothing to a read-only drawing', (tester) async {
      setScreen(tester, const Size(1280, 800));
      final editor = await openEditor(tester);
      editor.saveCubit.replace(
        editor.saveCubit.state.copyWith(
          embedding: Embedding(editable: false, internal: true),
        ),
      );
      await tester.pumpAndSettle();
      await openPanel(tester);
      final before = shapes().length;
      await tester.tap(find.byKey(_tile));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(observer.created, isEmpty);
      expect(shapes(), hasLength(before));
    });

    testWidgets('Tab reaches a tile and Enter places it', (tester) async {
      setScreen(tester, const Size(1280, 800));
      await openEditor(tester);
      await openPanel(tester);
      final before = shapes().length;

      bool tileFocused() {
        final context = FocusManager.instance.primaryFocus?.context;
        if (context == null) return false;
        var found = false;
        context.visitAncestorElements((element) {
          if (element.widget.key == _tile) found = true;
          return !found;
        });
        return found;
      }

      for (var i = 0; i < 20 && !tileFocused(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(tileFocused(), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await pumpUntil(tester, () => shapes().length > before, 'placement');
      expect(observer.created, hasLength(1));
    });
  });
}
