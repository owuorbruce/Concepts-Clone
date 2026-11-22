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
import 'package:butterfly/views/amaze/tool_preview.dart';
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

Finder _toolTile(ToolFamily family) =>
    find.byKey(ValueKey(('amaze-library-tool', family.name)));

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
  GoRouter? router;
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
    router?.dispose();
    router = null;
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
          routerConfig: router!,
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

  testWidgets('the header shows the slot in action on a wide strip', (
    tester,
  ) async {
    await tester.runAsync(loadBrushRegistry);
    setScreen(tester, tall);
    await openEditor(tester);
    final strip = find.byKey(const ValueKey('amaze-library-preview'));

    await openLibrary(tester, slotOf<PenTool>());
    final library = tester.getSize(
      find.byKey(const ValueKey('amaze-brush-library')),
    );
    final size = tester.getSize(strip);
    expect(size.height, 72);
    expect(size.width, greaterThan(library.width - 40));
    expect(
      find.descendant(
        of: strip,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is CheckerboardPainter,
        ),
      ),
      findsOneWidget,
    );
    final pen = slotTool(slotOf<PenTool>()) as PenTool;
    final brush = tester.widget<BrushStripPreview>(
      find.descendant(of: strip, matching: find.byType(BrushStripPreview)),
    );
    expect(brush.definition.id, 'amaze.pen');
    expect(brush.strokeWidth, pen.property.strokeWidth);
    expect(
      find.descendant(of: strip, matching: find.byType(RawImage)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('amaze-library-close')));
    await tester.pumpAndSettle();

    for (final (slot, kind) in [
      (slotOf<EraserTool>(), ToolPreviewKind.eraser),
      (slotOf<SelectTool>(), ToolPreviewKind.lasso),
    ]) {
      await openLibrary(tester, slot);
      final preview = tester.widget<ToolStripPreview>(
        find.descendant(of: strip, matching: find.byType(ToolStripPreview)),
      );
      expect(preview.kind, kind);
      await tester.tap(find.byKey(const ValueKey('amaze-library-close')));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  test('previews are cached per item and size', () {
    var paints = 0;
    void paint(Canvas canvas) => paints++;
    const size = Size(200, 72);
    final a = cachedPreviewImage(('test', 1), size, 1, paint);
    final again = cachedPreviewImage(('test', 1), size, 1, paint);
    final wider = cachedPreviewImage(
      ('test', 1),
      const Size(300, 72),
      1,
      paint,
    );
    final other = cachedPreviewImage(('test', 2), size, 1, paint);
    expect(identical(a, again), isTrue);
    expect(identical(a, wider), isFalse);
    expect(identical(a, other), isFalse);
    expect(paints, 3);
  });

  testWidgets('13: More tools shows one tile per family, in its groups', (
    tester,
  ) async {
    setScreen(tester, tall);
    await openEditor(tester);
    await openLibrary(tester, slotOf<PenTool>());

    expect(find.byKey(_moreTools), findsOneWidget);
    final tiles = find.descendant(
      of: find.byKey(_moreTools),
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<(String, String)> &&
            key.value.$1 == 'amaze-library-tool';
      }),
    );
    expect(tiles, findsNWidgets(ToolFamily.values.length));
    // Groups in order, each holding its own families.
    double? lastTop;
    for (final group in ToolGroup.values) {
      final grid = find.byKey(ValueKey(('amaze-library-group', group.name)));
      expect(grid, findsOneWidget, reason: group.name);
      final top = tester.getTopLeft(grid).dy;
      if (lastTop != null) expect(top, greaterThan(lastTop));
      lastTop = top;
      for (final family in ToolFamily.of(group)) {
        expect(
          find.descendant(of: grid, matching: _toolTile(family)),
          findsOneWidget,
          reason: family.name,
        );
      }
    }
    expect(find.text('Draw & edit'.toUpperCase()), findsOneWidget);
    expect(find.text('Present & view'.toUpperCase()), findsOneWidget);
    // Clear names.
    for (final name in [
      'Text',
      'Straightedge',
      'Insert space',
      'Artboard',
      'Pattern fill',
      'Laser pointer',
      'Collections',
    ]) {
      expect(
        find.descendant(of: find.byKey(_moreTools), matching: find.text(name)),
        findsOneWidget,
        reason: name,
      );
    }
    // Actions carry a badge.
    for (final family in ToolFamily.values) {
      expect(
        find.byKey(ValueKey(('amaze-library-action', family.name))),
        family.isAction ? findsOneWidget : findsNothing,
        reason: family.name,
      );
    }
    expect(tester.takeException(), isNull);
  });

  test('13: every catalog preset stays reachable through a family', () {
    for (final preset in slotToolCatalog()) {
      final family = ToolFamily.ofTool(preset);
      expect(family, isNotNull, reason: preset.runtimeType.toString());
      expect(
        family!.variants.any((variant) => sameToolVariant(variant, preset)),
        isTrue,
        reason: preset.runtimeType.toString(),
      );
    }
    expect(ToolFamily.shapes.variants.length, 4);
    expect(ToolFamily.barcode.variants.length, BarcodeType.values.length);
    expect(ToolFamily.insertSpace.variants.length, 2);
    expect(ToolFamily.eraser.variants.length, 2);
    expect(ToolFamily.select.variants.length, 2);
  });

  testWidgets('13: the Shapes tile puts a shape in; its menu picks a type', (
    tester,
  ) async {
    setScreen(tester, tall);
    final editor = await openEditor(tester);
    final slot = slotOf<PenTool>();
    final id = slotTool(slot).id;
    final index = slotToolIndices(documentTools())[slot];
    await openLibrary(tester, slot);

    await tester.tap(_toolTile(ToolFamily.shapes));
    await pumpUntil(tester, () => slotTool(slot) is ShapeTool, 'shape');
    await pumpUntil(
      tester,
      () => editor.toolCubit.state.index == index,
      'activated',
    );
    expect(slotTool(slot).id, id);
    expect(find.byKey(const ValueKey('amaze-library-info')), findsOneWidget);
    expect(find.textContaining('Shapes: drag'), findsOneWidget);

    await tester.longPress(_toolTile(ToolFamily.shapes));
    await tester.pumpAndSettle();
    final rectangle = ToolFamily.shapes.variants.indexWhere(
      (tool) => tool is ShapeTool && tool.property.shape is RectangleShape,
    );
    await tester.tap(
      find.byKey(ValueKey(('amaze-library-variant', rectangle))),
    );
    await pumpUntil(
      tester,
      () => (slotTool(slot) as ShapeTool).property.shape is RectangleShape,
      'rectangle',
    );
    expect(slotTool(slot).id, id);
    expect(editor.toolCubit.state.handler.data, isA<ShapeTool>());
    // The library stays open, as after picking any other entry.
    expect(find.byKey(const ValueKey('amaze-brush-library')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('13: every barcode type is reachable from its tile', (
    tester,
  ) async {
    setScreen(tester, tall);
    await openEditor(tester);
    final slot = slotOf<PenTool>();
    await openLibrary(tester, slot);
    for (final (index, type) in BarcodeType.values.indexed) {
      await tester.longPress(_toolTile(ToolFamily.barcode));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(('amaze-library-variant', index))));
      await pumpUntil(
        tester,
        () => switch (slotTool(slot)) {
          BarcodeTool(:final barcodeType) => barcodeType == type,
          _ => false,
        },
        type.name,
      );
      await tester.pumpAndSettle();
      // Close a content dialog if picking the tool opened one.
      if (find.byType(Dialog).evaluate().isNotEmpty) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('13: search for "pattern" finds Pattern fill', (tester) async {
    setScreen(tester, tall);
    await openEditor(tester);
    await openLibrary(tester, slotOf<PenTool>());
    await tester.enterText(
      find.byKey(const ValueKey('amaze-library-search')),
      'pattern',
    );
    await tester.pumpAndSettle();
    expect(_toolTile(ToolFamily.patternFill), findsOneWidget);
    expect(_toolTile(ToolFamily.shapes), findsNothing);
    // The brush named after patterns shows too.
    expect(
      find.byKey(const ValueKey(('amaze-library-item', 'tilingPatterns'))),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('amaze-library-search')),
      'zzzz',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('amaze-library-no-results')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('13: Full screen runs without changing the slot', (tester) async {
    setScreen(tester, tall);
    await openEditor(tester);
    final slot = slotOf<PenTool>();
    final before = slotTool(slot);
    await openLibrary(tester, slot);
    expect(windowCubit.state.fullScreen, isFalse);
    await tester.tap(_toolTile(ToolFamily.fullScreen));
    await pumpUntil(tester, () => windowCubit.state.fullScreen, 'full screen');
    expect(slotTool(slot).id, before.id);
    expect(slotTool(slot), isA<PenTool>());
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  test('14: the Pattern fill tile starts with a visible grid', () {
    final tool = ToolFamily.patternFill.defaultTool as TextureTool;
    final texture = tool.texture as PatternTexture;
    expect(texture.boxWidth, 40);
    expect(texture.boxHeight, 40);
    expect(texture.boxColor.a, 0);
    expect(texture.boxXStroke, greaterThan(0));
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
