import 'package:butterfly/actions/shortcuts.dart';
import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/api/open.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/brushes/brush_preview.dart';
import 'package:butterfly/brushes/brush_registry.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/models/defaults.dart';
import 'package:butterfly/services/font.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/theme.dart';
import 'package:butterfly/views/amaze/icons.dart';
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly/views/amaze/shell.dart';
import 'package:butterfly/views/amaze/tool_slots.dart';
import 'package:butterfly/views/main.dart';
import 'package:butterfly_api/butterfly_api.dart';
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

const _moreTools = ValueKey('amaze-library-more-tools');

Finder _toolTile(int index) =>
    find.byKey(ValueKey(('amaze-library-tool', index)));

class _Observer extends BlocObserver {
  DocumentBloc? bloc;

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    if (bloc is DocumentBloc) this.bloc = bloc;
  }
}

void main() {
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
    SharedPreferences.setMockInitialValues({'amaze.toolWheel.diameter': 320.0});
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
    when(() => settingsCubit.addRecentHistory(any())).thenAnswer((_) async {});
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
    final document = DocumentDefaults.createDocument(name: 'Library');
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

  List<Tool> documentTools() =>
      (observer.bloc!.state as DocumentLoadSuccess).info.tools;

  int slotOf<T extends Tool>() {
    final tools = documentTools();
    return slotToolIndices(tools).indexWhere((index) => tools[index] is T);
  }

  Tool slotTool(int slot) {
    final tools = documentTools();
    return tools[slotToolIndices(tools)[slot]];
  }

  Future<void> openLibrary(WidgetTester tester, int slot) async {
    await tester.longPress(find.byKey(ValueKey(('amaze-slot', slot))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('amaze-brush-library')), findsOneWidget);
  }

  // Tall enough that the whole library, More tools included, is built.
  const tall = Size(1280, 4000);

  testWidgets('22: every Basics brush is available with its own preview', (
    tester,
  ) async {
    await tester.runAsync(loadBrushRegistry);
    setScreen(tester, tall);
    await openEditor(tester);
    await openLibrary(tester, slotOf<PenTool>());

    final basics = LibraryEntry.of(LibrarySection.basics);
    for (final entry in basics) {
      expect(entry.available, isTrue, reason: entry.name);
      final tile = find.byKey(ValueKey(('amaze-library-item', entry.name)));
      expect(tile, findsOneWidget, reason: entry.name);
      if (entry == LibraryEntry.fill) continue;
      expect(entry.brushDefinition, isNotNull, reason: entry.name);
      final preview = find.descendant(
        of: tile,
        matching: find.byType(BrushEnginePreview),
      );
      expect(preview, findsOneWidget, reason: entry.name);
      expect(
        find.descendant(of: preview, matching: find.byType(RawImage)),
        findsOneWidget,
        reason: entry.name,
      );
      final tool = entry.createTool() as PenTool;
      expect(tool.property.brush, entry.brushId, reason: entry.name);
    }
    expect(find.byType(BrushEnginePreview), findsAtLeastNWidgets(11));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tools ends with More tools: one tile per catalog tool', (
    tester,
  ) async {
    setScreen(tester, tall);
    await openEditor(tester);
    await openLibrary(tester, slotOf<PenTool>());

    expect(find.text('MORE TOOLS'), findsOneWidget);
    expect(find.byKey(_moreTools), findsOneWidget);
    final catalog = slotToolCatalog();
    final tiles = find.descendant(
      of: find.byKey(_moreTools),
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<(String, int)> &&
            key.value.$1 == 'amaze-library-tool';
      }),
    );
    expect(tiles, findsNWidgets(catalog.length));
    expect(_toolTile(catalog.length - 1), findsOneWidget);
    // More tools comes after the Tools section's own tiles.
    expect(
      tester.getTopLeft(find.text('MORE TOOLS')).dy,
      greaterThan(tester.getTopLeft(find.text('TOOLS')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rectangle tile puts a rectangle tool into the slot', (
    tester,
  ) async {
    setScreen(tester, tall);
    final editor = await openEditor(tester);
    final slot = slotOf<PenTool>();
    final id = slotTool(slot).id;
    final index = slotToolIndices(documentTools())[slot];
    await openLibrary(tester, slot);

    final rectangle = slotToolCatalog().indexWhere(
      (tool) => tool is ShapeTool && tool.property.shape is RectangleShape,
    );
    expect(rectangle, isNonNegative);
    await tester.tap(_toolTile(rectangle));
    await pumpUntil(tester, () => slotTool(slot) is ShapeTool, 'rectangle');
    await pumpUntil(
      tester,
      () => editor.toolCubit.state.index == index,
      'activated',
    );
    final tool = slotTool(slot) as ShapeTool;
    expect(tool.property.shape, isA<RectangleShape>());
    expect(tool.id, id);
    expect(editor.toolCubit.state.handler.data, isA<ShapeTool>());
    // The library stays open, as after picking any other entry.
    expect(find.byKey(const ValueKey('amaze-brush-library')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('9: no library entry is unavailable or shows a lock', (
    tester,
  ) async {
    await tester.runAsync(loadBrushRegistry);
    setScreen(tester, tall);
    await openEditor(tester);
    await openLibrary(tester, slotOf<PenTool>());
    for (final entry in LibraryEntry.values) {
      expect(entry.available, isTrue, reason: entry.name);
      expect(entry.createTool(), isNotNull, reason: entry.name);
    }
    final market = find.byKey(const ValueKey('amaze-library-market'));
    final scrollable = find
        .descendant(
          of: find.byKey(const ValueKey('amaze-library-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(market, 200, scrollable: scrollable);
    await tester.tap(market);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('amaze-brush-library')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AmazeIcon && widget.icon == AmazeIcons.unavailable,
        ),
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message ?? '').contains('Not available yet'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('10: a market pack shows its 4 brushes; one goes in the slot', (
    tester,
  ) async {
    await tester.runAsync(loadBrushRegistry);
    setScreen(tester, tall);
    await openEditor(tester);
    final slot = slotOf<PenTool>();
    final id = slotTool(slot).id;
    await openLibrary(tester, slot);
    final scrollable = find
        .descendant(
          of: find.byKey(const ValueKey('amaze-library-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    final market = find.byKey(const ValueKey('amaze-library-market'));
    await tester.scrollUntilVisible(market, 200, scrollable: scrollable);
    await tester.tap(market);
    await tester.pumpAndSettle();

    for (final pack in LibraryEntry.of(LibrarySection.market)) {
      final tile = find.byKey(ValueKey(('amaze-library-item', pack.name)));
      await tester.scrollUntilVisible(tile, 200, scrollable: scrollable);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final sheet = find.byKey(ValueKey(('amaze-library-pack', pack.name)));
      expect(sheet, findsOneWidget, reason: pack.name);
      for (final brush in pack.packBrushIds) {
        expect(
          find.descendant(
            of: sheet,
            matching: find.byKey(ValueKey(('amaze-library-pack-brush', brush))),
          ),
          findsOneWidget,
          reason: brush,
        );
      }
      expect(
        find.descendant(of: sheet, matching: find.byType(BrushEnginePreview)),
        findsNWidgets(4),
      );
    }

    // The last pack is open: pick its third brush.
    final pack = LibraryEntry.inkBlot;
    final brush = pack.packBrushIds[2];
    final pick = find.byKey(ValueKey(('amaze-library-pack-brush', brush)));
    await tester.scrollUntilVisible(pick, 200, scrollable: scrollable);
    await tester.tap(pick);
    await pumpUntil(tester, () {
      final tool = slotTool(slot);
      return tool is PenTool && tool.property.brush == brush;
    }, 'pack brush in slot');
    final tool = slotTool(slot) as PenTool;
    expect(tool.id, id);
    expect(tool.displayIcon, 'amaze.${pack.name}');
    expect(libraryEntryOf(tool), pack);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });
}
