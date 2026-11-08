import 'dart:convert';
import 'dart:io';
import 'dart:math' show Point, cos, pi, sin;
import 'dart:ui' as ui;

import 'package:butterfly/actions/shortcuts.dart';
import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/api/open.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/models/defaults.dart';
import 'package:butterfly/services/font.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/theme.dart';
import 'package:butterfly/views/amaze/dock.dart';
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/views/amaze/shell.dart';
import 'package:butterfly/views/amaze/style.dart';
import 'package:butterfly/views/amaze/tool_slots.dart';
import 'package:butterfly/views/amaze/tool_wheel.dart';
import 'package:butterfly/views/app_bar.dart';
import 'package:butterfly/views/edit.dart';
import 'package:butterfly/views/main.dart';
import 'package:butterfly/views/view.dart';
import 'package:butterfly/views/navigator/layers.dart';
import 'package:butterfly/views/toolbar/view.dart';
import 'package:butterfly/views/zoom.dart';
import 'package:butterfly/visualizer/tool.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
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

const _wheel = ValueKey('amaze-tool-wheel');
const _bar = ValueKey('amaze-tool-bar');
const _color = ValueKey('amaze-color');
const _puck = ValueKey('amaze-tool-wheel-puck');
const _layers = ValueKey(('amaze-dock', 'layers'));
const _library = ValueKey('amaze-brush-library');
const _amaze = ButterflySettings(
  defaultTemplate: 'default',
  flags: [kAmazeShellFlag],
);

/// Loads the bundled fonts so screenshots show real text and icons.
ThemeData _theme(bool dark, String? fontFamily) {
  final theme = getThemeData('', dark);
  if (fontFamily == null) return theme;
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: fontFamily),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: fontFamily),
  );
}

Future<void> _loadFonts() async {
  final manifest = await rootBundle.loadString('FontManifest.json');
  final families = jsonDecode(manifest) as List<dynamic>;
  for (final family in families.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    final fonts = family['fonts'] as List<dynamic>;
    for (final font in fonts.cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

NoteData _sampleDocument() {
  const rectangle = ShapeProperty(
    shape: RectangleShape(),
    strokeWidth: 6,
    paint: ElementPaint.solid(color: SRGBColor(0xFF1B2440)),
  );
  const circle = ShapeProperty(
    shape: CircleShape(),
    strokeWidth: 6,
    paint: ElementPaint.solid(color: SRGBColor(0xFF0B8F84)),
  );
  final elements = [
    PadElement.shape(
      firstPosition: const Point(160.0, 140.0),
      secondPosition: const Point(560.0, 420.0),
      property: rectangle,
    ),
    PadElement.shape(
      firstPosition: const Point(640.0, 200.0),
      secondPosition: const Point(900.0, 460.0),
      property: circle,
    ),
  ];
  return DocumentDefaults.createDocument(
    name: 'aMaze shell',
    page: DocumentPage(
      backgrounds: const [],
      layers: [DocumentLayer(content: elements)],
    ),
  );
}

void main() {
  final screenshotKey = GlobalKey();

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
    await _loadFonts();
  });

  late MockSettingsCubit settingsCubit;
  late MockButterflyFileSystem fileSystem;
  late WindowCubit windowCubit;
  late GoRouter router;
  late _DocumentObserver observer;
  late BlocObserver previousObserver;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settingsCubit = MockSettingsCubit();
    fileSystem = MockButterflyFileSystem(settingsCubit: settingsCubit);
    windowCubit = WindowCubit(fullScreen: false);
    observer = _DocumentObserver();
    previousObserver = Bloc.observer;
    Bloc.observer = observer;

    when(() => settingsCubit.state).thenReturn(_amaze);
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
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

  Widget buildApp(NoteData document, {bool dark = false, String? fontFamily}) {
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
              builder: (context, state) {
                final path = state.pathParameters['path'] ?? '';
                return ProjectPage(
                  data: state.extra ?? document,
                  location: AssetLocation.local(path),
                );
              },
            ),
          ],
        ),
      ],
    );

    return RepaintBoundary(
      key: screenshotKey,
      child: MultiRepositoryProvider(
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
            theme: _theme(dark, fontFamily),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              LeapLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      ),
    );
  }

  Future<EditorController> openEditor(
    WidgetTester tester, {
    NoteData? document,
    bool dark = false,
    String? fontFamily,
  }) async {
    final data = document ?? _sampleDocument();
    await tester.pumpWidget(buildApp(data, dark: dark, fontFamily: fontFamily));
    await tester.tap(find.byKey(const ValueKey('open-document')));
    await pumpUntil(
      tester,
      () => observer.lastDocumentBloc?.state is DocumentLoadSuccess,
      'document open',
    );
    await tester.pumpAndSettle();
    return observer.lastDocumentBloc!.editorController;
  }

  /// Writes a PNG of the app to build/amaze_screenshots for review.
  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    final context = screenshotKey.currentContext!;
    final boundary = context.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = data!.buffer.asUint8List();
      final file = File('build/amaze_screenshots/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
    });
  }

  List<Tool> documentTools() {
    final state = observer.lastDocumentBloc!.state as DocumentLoadSuccess;
    return state.info.tools;
  }

  int slotOf<T extends Tool>() {
    final tools = documentTools();
    return slotToolIndices(tools).indexWhere((index) => tools[index] is T);
  }

  Tool slotTool(int slot) {
    final tools = documentTools();
    return tools[slotToolIndices(tools)[slot]];
  }

  Finder slotButton(int slot) => find.byKey(ValueKey(('amaze-slot', slot)));

  /// The fill of the wheel wedge of [slot].
  Color wedgeColor(WidgetTester tester, int slot) {
    final box = tester.widget<DecoratedBox>(
      find.byKey(ValueKey(('amaze-wedge', slot))),
    );
    return (box.decoration as ShapeDecoration).color!;
  }

  /// The opacity the wheel is shown at, or animating to.
  double fadeOpacity(WidgetTester tester) {
    final fade = find.byKey(const ValueKey('amaze-wheel-fade'));
    return tester.widget<AnimatedOpacity>(fade).opacity;
  }

  Finder libraryItem(LibraryEntry entry) {
    return find.byKey(ValueKey(('amaze-library-item', entry.name)));
  }

  Future<void> selectSlot(
    WidgetTester tester,
    EditorController editor,
    int slot,
  ) async {
    final index = slotToolIndices(documentTools())[slot];
    await tester.tap(slotButton(slot));
    await pumpUntil(
      tester,
      () => editor.toolCubit.state.index == index,
      'slot $slot',
    );
    await tester.pumpAndSettle();
  }

  /// A point in the wheel's left gap, between undo and redo.
  Offset ringPoint(WidgetTester tester) {
    const geometry = ToolWheelGeometry();
    const angle = pi; // The gap between undo and redo.
    final direction = Offset(cos(angle), sin(angle));
    final center = tester.getCenter(find.byKey(_wheel));
    return center + direction * geometry.historyDistance;
  }

  Future<void> dockWheel(WidgetTester tester) async {
    final gesture = await tester.startGesture(ringPoint(tester));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    final target = find.byKey(const ValueKey('amaze-dock-target'));
    expect(target, findsOneWidget);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('landscape tablets get the dock, tool wheel and floating bar', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    await selectSlot(tester, editor, slotOf<PenTool>());

    expect(find.byKey(_wheel), findsOneWidget);
    expect(find.byType(AmazeDock), findsOneWidget);
    expect(find.byType(EditToolbar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.widget<PadAppBar>(find.byType(PadAppBar)).floating, isTrue);
    final wheel = tester.getRect(find.byKey(_wheel));
    expect(wheel.right, lessThanOrEqualTo(1280));
    expect(wheel.bottom, lessThanOrEqualTo(800));
    expect(wheel.center.dx, greaterThan(640));
    expect(tester.takeException(), isNull);
    await capture(tester, 'landscape');
  });

  testWidgets('portrait tablets keep the wheel on screen', (tester) async {
    setScreen(tester, const Size(800, 1280));
    final editor = await openEditor(tester);
    await selectSlot(tester, editor, slotOf<PenTool>());

    expect(find.byKey(_wheel), findsOneWidget);
    expect(find.byType(AmazeDock), findsOneWidget);
    expect(find.byType(EditToolbar), findsNothing);
    expect(find.byType(PadAppBar), findsOneWidget);
    final wheel = tester.getRect(find.byKey(_wheel));
    expect(wheel.left, greaterThanOrEqualTo(0));
    expect(wheel.right, lessThanOrEqualTo(800));
    expect(wheel.bottom, lessThanOrEqualTo(1280));
    expect(wheel.center.dx, closeTo(400, 2));
    expect(tester.takeException(), isNull);
    await capture(tester, 'portrait');
  });

  testWidgets('the wheel follows rotation without leaving the screen', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pumpAndSettle();
    final wheel = tester.getRect(find.byKey(_wheel));
    expect(wheel.right, lessThanOrEqualTo(800));
    expect(wheel.bottom, lessThanOrEqualTo(1280));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wheel has eight slots and separate undo and redo', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);

    for (var slot = 0; slot < kToolSlotCount; slot++) {
      expect(slotButton(slot), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('amaze-undo')), findsOneWidget);
    expect(find.byKey(const ValueKey('amaze-redo')), findsOneWidget);
    final tools = documentTools();
    final slotted = slotToolIndices(tools).map((index) => tools[index]);
    expect(slotted.whereType<UndoTool>(), isEmpty);
    expect(slotted.whereType<RedoTool>(), isEmpty);
    expect(slotted, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a slot activates its tool, again opens it', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);

    await selectSlot(tester, editor, slotOf<HandTool>());
    await selectSlot(tester, editor, slotOf<PenTool>());
    expect(editor.toolCubit.state.handler.data, isA<PenTool>());

    await tester.tap(slotButton(slotOf<PenTool>()));
    await tester.pumpAndSettle();
    final selection = editor.toolCubit.state.selection;
    expect(selection?.selected.single, isA<PenTool>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty slot opens the brush library', (tester) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final empty = slotToolIndices(documentTools()).length;

    await tester.tap(slotButton(empty));
    await tester.pumpAndSettle();
    expect(find.byKey(_library), findsOneWidget);
    expect(find.byKey(const ValueKey('amaze-library-slot-menu')), findsNothing);
    await tester.tap(libraryItem(LibraryEntry.wire));
    await pumpUntil(
      tester,
      () => slotToolIndices(documentTools()).length == empty + 1,
      'slot assigned',
    );
    final wire = slotTool(empty) as PenTool;
    expect(wire.zoomDependent, isTrue);
    expect(wire.property.thinning, 0);
    expect(libraryEntryOf(wire), LibraryEntry.wire);
    await tester.pumpAndSettle();
    expect(editor.toolCubit.state.handler.data, isA<PenTool>());
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('long press opens the library, tap still activates', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final hand = slotOf<HandTool>();

    await selectSlot(tester, editor, hand);
    expect(find.byKey(_library), findsNothing);
    final pen = slotOf<PenTool>();
    await tester.longPress(slotButton(pen));
    await tester.pumpAndSettle();
    expect(find.byKey(_library), findsOneWidget);
    expect(editor.toolCubit.state.handler.data, isA<HandTool>());
    final name = tester.widget<Text>(
      find.byKey(const ValueKey('amaze-library-name')),
    );
    expect(
      name.data,
      slotTool(pen).getDisplay(tester.element(find.byKey(_library))),
    );
    await capture(tester, 'library-brushes');

    await tester.tap(find.byKey(const ValueKey('amaze-library-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(_library), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a brush replaces the slot and activates it', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final eraser = slotOf<EraserTool>();
    final eraserId = slotTool(eraser).id;
    final index = slotToolIndices(documentTools())[eraser];

    await tester.longPress(slotButton(eraser));
    await tester.pumpAndSettle();
    await tester.tap(libraryItem(LibraryEntry.dynamicPen));
    await pumpUntil(tester, () => slotTool(eraser) is PenTool, 'replaced');
    await pumpUntil(
      tester,
      () => editor.toolCubit.state.index == index,
      'activated',
    );
    final tool = slotTool(eraser) as PenTool;
    expect(tool.id, eraserId);
    expect(tool.property.thinning, 0.8);
    expect(libraryEntryOf(tool), LibraryEntry.dynamicPen);
    expect(editor.toolCubit.state.handler.data, isA<PenTool>());

    await tester.tap(libraryItem(LibraryEntry.fill));
    await pumpUntil(
      tester,
      () => libraryEntryOf(slotTool(eraser)) == LibraryEntry.fill,
      'fill',
    );
    final fill = slotTool(eraser) as PenTool;
    expect(fill.property.fillPaint.previewColor.a, greaterThan(0));
    expect(
      fill.property.fillPaint.previewColor,
      fill.property.paint.previewColor,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('unavailable library items cannot be picked', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    final pen = slotOf<PenTool>();
    final before = slotTool(pen);

    await tester.longPress(slotButton(pen));
    await tester.pumpAndSettle();
    for (final entry in LibraryEntry.values) {
      if (entry.section == LibrarySection.market) continue;
      await tester.ensureVisible(libraryItem(entry));
      expect(libraryItem(entry), findsOneWidget);
    }
    await tester.ensureVisible(libraryItem(LibraryEntry.watercolor));
    await tester.pumpAndSettle();
    await tester.tap(libraryItem(LibraryEntry.watercolor), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(slotTool(pen), same(before));
    await tester.ensureVisible(libraryItem(LibraryEntry.lasso));
    await tester.pumpAndSettle();
    await capture(tester, 'library-tools');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the brush market expands', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);

    await tester.longPress(slotButton(0));
    await tester.pumpAndSettle();
    expect(libraryItem(LibraryEntry.inkBlot), findsNothing);
    // The library list is the outermost scrollable; its grids scroll too.
    final scrollables = find.descendant(
      of: find.byKey(const ValueKey('amaze-library-scroll')),
      matching: find.byType(Scrollable),
    );
    final scrollable = scrollables.first;
    final market = find.byKey(const ValueKey('amaze-library-market'));
    await tester.scrollUntilVisible(market, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(market);
    await tester.pumpAndSettle();
    final last = libraryItem(LibraryEntry.inkBlot);
    await tester.scrollUntilVisible(last, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    for (final entry in LibraryEntry.of(LibrarySection.market)) {
      expect(libraryItem(entry), findsOneWidget);
      expect(entry.available, isFalse);
    }
    await capture(tester, 'library-market');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the library offers the slot menu to replace and move tools', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    final eraser = slotOf<EraserTool>();
    final eraserId = slotTool(eraser).id;
    final label = slotToolCatalog().indexWhere((tool) => tool is LabelTool);
    final slotMenu = find.byKey(const ValueKey('amaze-library-slot-menu'));

    await tester.longPress(slotButton(eraser));
    await tester.pumpAndSettle();
    await tester.tap(slotMenu);
    await tester.pumpAndSettle();
    await capture(tester, 'slot-menu');
    await tester.tap(find.byKey(const ValueKey('amaze-slot-replace')));
    await tester.pumpAndSettle();
    await capture(tester, 'slot-catalog');
    await tester.tap(find.byKey(ValueKey(('amaze-catalog', label))));
    await pumpUntil(tester, () => slotTool(eraser) is LabelTool, 'replaced');
    expect(slotTool(eraser).id, eraserId);
    await tester.pumpAndSettle();

    final first = slotTool(0).id;
    await tester.longPress(slotButton(0));
    await tester.pumpAndSettle();
    await tester.tap(slotMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('amaze-slot-later')));
    await pumpUntil(tester, () => slotTool(1).id == first, 'moved');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('the tool bar opens the library too', (tester) async {
    setScreen(tester, const Size(800, 1280));
    await openEditor(tester);
    await dockWheel(tester);
    expect(find.byKey(_bar), findsOneWidget);
    await capture(tester, 'toolbar-icons');

    await tester.longPress(slotButton(0));
    await tester.pumpAndSettle();
    expect(find.byKey(_library), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library assignments are stored with the document', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    final pen = slotOf<PenTool>();

    await tester.longPress(slotButton(pen));
    await tester.pumpAndSettle();
    await tester.tap(libraryItem(LibraryEntry.fixedWidth));
    await pumpUntil(
      tester,
      () => libraryEntryOf(slotTool(pen)) == LibraryEntry.fixedWidth,
      'fixed width',
    );
    // Tools are stored in the document, so a JSON round trip is what the
    // next session reads back.
    final reopened = documentTools().map((tool) {
      final json = jsonDecode(jsonEncode(tool.toJson()));
      return Tool.fromJson(json as Map<String, dynamic>);
    }).toList();
    final slot = reopened[slotToolIndices(reopened)[pen]];
    expect(libraryEntryOf(slot), LibraryEntry.fixedWidth);
    expect((slot as PenTool).property.thinning, 0);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('dark library', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester, dark: true);
    await tester.longPress(slotButton(0));
    await tester.pumpAndSettle();
    await capture(tester, 'library-dark');
    expect(tester.takeException(), isNull);
  });

  testWidgets('middle ring adjustments change the active pen', (tester) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final penSlot = slotOf<PenTool>();
    await selectSlot(tester, editor, penSlot);
    PenTool pen() => editor.toolCubit.state.handler.data as PenTool;

    Future<void> adjust(ToolAdjustment adjustment, double value) async {
      final key = ValueKey(('amaze-adjust', adjustment.name));
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('amaze-adjustment-slider'));
      tester.widget<Slider>(slider).onChangeEnd!(value);
      await tester.pumpAndSettle();
    }

    await adjust(ToolAdjustment.size, 12);
    await pumpUntil(tester, () => pen().property.strokeWidth == 12, 'size');
    await capture(tester, 'landscape-adjust-size');
    await adjust(ToolAdjustment.opacity, 0.5);
    await pumpUntil(
      tester,
      () => pen().property.paint.previewColor.a == 128,
      'opacity',
    );
    await adjust(ToolAdjustment.smoothing, 0.8);
    await pumpUntil(tester, () => pen().property.smoothing == 0.8, 'smoothing');

    final stored = slotTool(penSlot) as PenTool;
    expect(stored.property.strokeWidth, 12);
    expect(stored.property.paint.previewColor.a, 128);
    expect(stored.property.smoothing, 0.8);
    expect(find.text('12'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('the eraser shows its size and both erasing behaviours', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final eraser = slotOf<EraserTool>();
    await selectSlot(tester, editor, eraser);

    const size = ValueKey(('amaze-adjust', 'size'));
    const opacity = ValueKey(('amaze-adjust', 'opacity'));
    const smoothing = ValueKey(('amaze-adjust', 'smoothing'));
    expect(find.byKey(size), findsOneWidget);
    expect(find.byKey(opacity), findsNothing);
    expect(find.byKey(smoothing), findsNothing);
    final center = find.descendant(
      of: find.byKey(_color),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(center).onTap, isNull);

    await tester.tap(slotButton(eraser));
    await tester.pumpAndSettle();
    expect(find.text('Cut strokes'), findsOneWidget);
    expect(find.text('Whole elements'), findsOneWidget);
    await capture(tester, 'eraser-options');
    await tester.tap(find.byKey(const ValueKey(('eraser-mode', 'path'))));
    await pumpUntil(
      tester,
      () => (slotTool(eraser) as EraserTool).mode == EraserMode.path,
      'eraser mode',
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('the center opens the color picker', (tester) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    await selectSlot(tester, editor, slotOf<PenTool>());

    await tester.tap(find.byKey(_color));
    await tester.pumpAndSettle();
    expect(find.byType(ColorPicker), findsOneWidget);
    Navigator.of(tester.element(find.byType(ColorPicker))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wheel undoes and redoes document changes', (tester) async {
    when(() => settingsCubit.state).thenReturn(
      const ButterflySettings(
        defaultTemplate: 'default',
        autosave: false,
        flags: [kAmazeShellFlag],
      ),
    );
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    final bloc = observer.lastDocumentBloc!;
    String description() =>
        (bloc.state as DocumentLoadSuccess).metadata.description;
    final original = description();

    bloc.add(const DocumentDescriptionChanged(description: 'Edited note'));
    await pumpUntil(tester, () => description() == 'Edited note', 'edit');
    await tester.tap(find.byKey(const ValueKey('amaze-undo')));
    await pumpUntil(tester, () => description() == original, 'undo');
    await tester.tap(find.byKey(const ValueKey('amaze-redo')));
    await pumpUntil(tester, () => description() == 'Edited note', 'redo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press dragging the ring moves the wheel', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    final before = tester.getTopLeft(find.byKey(_wheel));

    final gesture = await tester.startGesture(ringPoint(tester));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(-300, -200));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final after = tester.getRect(find.byKey(_wheel));
    expect(after.left, lessThan(before.dx - 200));
    expect(after.top, lessThan(before.dy - 100));
    expect(after.left, greaterThanOrEqualTo(0));
    expect(after.top, greaterThanOrEqualTo(0));
    expect(find.byKey(_bar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dropping the wheel on the dock target makes a tool bar', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    await selectSlot(tester, editor, slotOf<PenTool>());
    final index = editor.toolCubit.state.index;

    await dockWheel(tester);
    expect(find.byKey(_wheel), findsNothing);
    expect(find.byKey(_bar), findsOneWidget);
    for (var slot = 0; slot < kToolSlotCount; slot++) {
      expect(slotButton(slot), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('amaze-undo')), findsOneWidget);
    expect(find.byKey(const ValueKey('amaze-redo')), findsOneWidget);
    expect(find.byKey(const ValueKey(('amaze-adjust', 'size'))), findsOne);
    expect(find.byKey(_color), findsOneWidget);
    expect(editor.toolCubit.state.index, index);
    final mode = await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('amaze.toolWheel.mode');
    });
    expect(mode, 'bar');
    await capture(tester, 'landscape-bar');

    tester.view.physicalSize = const Size(800, 1280);
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byKey(_bar));
    expect(bar.left, greaterThanOrEqualTo(0));
    expect(bar.right, lessThanOrEqualTo(800));
    expect(bar.bottom, lessThanOrEqualTo(1280));
    await capture(tester, 'portrait-bar');

    await tester.tap(find.byKey(const ValueKey('amaze-bar-show-wheel')));
    await tester.pumpAndSettle();
    expect(find.byKey(_wheel), findsOneWidget);
    expect(editor.toolCubit.state.index, index);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tool bar is restored in the next session', (tester) async {
    SharedPreferences.setMockInitialValues({'amaze.toolWheel.mode': 'bar'});
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);

    expect(find.byKey(_bar), findsOneWidget);
    expect(find.byKey(_wheel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('holding the center collapses the wheel', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);

    await tester.longPress(find.byKey(_color));
    await tester.pumpAndSettle();
    expect(find.byKey(_wheel), findsNothing);
    expect(find.byKey(_puck), findsOneWidget);
    final collapsed = await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('amaze.toolWheel.collapsed');
    });
    expect(collapsed, isTrue);

    await tester.tap(find.byKey(_puck));
    await tester.pumpAndSettle();
    expect(find.byKey(_wheel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typography proposal: Roboto', (tester) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester, fontFamily: 'Roboto');
    await selectSlot(tester, editor, slotOf<PenTool>());
    await capture(tester, 'typography-roboto-wheel');
    await dockWheel(tester);
    await capture(tester, 'typography-roboto-bar');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dock opens layers beside the canvas on wide screens', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);

    await tester.tap(find.byKey(_layers));
    await tester.pumpAndSettle();
    expect(find.byType(AmazeNavigatorPanel), findsOneWidget);
    expect(find.byType(LayersView), findsOneWidget);
    await capture(tester, 'landscape-layers');

    await tester.tap(find.byKey(_layers));
    await tester.pumpAndSettle();
    expect(find.byType(AmazeNavigatorPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dock opens layers as a dialog in portrait', (tester) async {
    setScreen(tester, const Size(800, 1280));
    await openEditor(tester);

    await tester.tap(find.byKey(_layers));
    await tester.pumpAndSettle();
    expect(find.byType(AmazeNavigatorPanel), findsNothing);
    expect(find.byType(LayersView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'portrait-layers');
  });

  testWidgets('the dock shows tool options and zoom and remembers them', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    expect(find.byType(ToolbarView), findsNothing);
    expect(find.byType(ZoomView), findsNothing);

    await tester.tap(find.byKey(const ValueKey('amaze-dock-tool-options')));
    await tester.pumpAndSettle();
    expect(find.byType(ToolbarView), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('amaze-dock-zoom')));
    await tester.pumpAndSettle();
    expect(find.byType(ZoomView), findsOneWidget);
    final saved = await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      return (
        prefs.getBool('amaze.shell.toolOptions'),
        prefs.getBool('amaze.shell.zoom'),
      );
    });
    expect(saved, (true, true));
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved panels come back in the next session', (tester) async {
    SharedPreferences.setMockInitialValues({'amaze.shell.zoom': true});
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);

    expect(find.byType(ZoomView), findsOneWidget);
    expect(find.byType(ToolbarView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  final themes = ValueVariant<bool>({false, true});

  testWidgets('the wheel and the tool bar follow the app theme', (
    tester,
  ) async {
    final dark = themes.currentValue!;
    final expected = dark ? Brightness.dark : Brightness.light;
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester, dark: dark);
    await selectSlot(tester, editor, slotOf<PenTool>());
    Brightness brightnessOf(Finder finder) {
      return Theme.of(tester.element(finder)).colorScheme.brightness;
    }

    expect(brightnessOf(find.byKey(_wheel)), expected);

    // An unselected wedge, and the size number on it.
    final eraser = slotOf<EraserTool>();
    final scheme = getThemeData('', dark).colorScheme;
    final surface = wedgeColor(tester, eraser);
    expect(
      surface,
      scheme.surfaceContainerHigh.withValues(alpha: kWheelSurfaceOpacity),
    );
    final other = getThemeData('', !dark).colorScheme.surfaceContainerHigh;
    expect(surface.withValues(alpha: 1), isNot(other.withValues(alpha: 1)));
    final label = tester.widget<Text>(
      find.byKey(ValueKey(('amaze-slot-size', eraser))),
    );
    final text = label.style!.color!;
    // The canvas behind the translucent surface can be light or dark.
    for (final canvas in [Colors.white, Colors.black]) {
      final background = Color.alphaBlend(surface, canvas);
      expect(
        contrastRatio(text, background),
        greaterThanOrEqualTo(4.5),
        reason: 'over $canvas',
      );
    }

    await dockWheel(tester);
    expect(brightnessOf(find.byKey(_bar)), expected);
    expect(tester.takeException(), isNull);
  }, variant: themes);

  testWidgets('the selected wedge takes the tool color and follows the tool', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final pen = slotOf<PenTool>();
    final eraser = slotOf<EraserTool>();
    await selectSlot(tester, editor, pen);
    final handler = editor.toolCubit.state.handler as ColoredHandler;
    final penColor = handler.getColor().toColor();
    expect(wedgeColor(tester, pen), penColor);
    final surface = wedgeColor(tester, eraser);
    expect(surface, isNot(penColor));

    await selectSlot(tester, editor, eraser);
    expect(wedgeColor(tester, pen), surface);
    expect(wedgeColor(tester, eraser), isNot(surface));
    await capture(tester, 'wheel-selected-eraser');
    expect(tester.takeException(), isNull);
  });

  testWidgets('wedges show their tool size, tools without one show none', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final pen = slotOf<PenTool>();
    await selectSlot(tester, editor, pen);
    await tester.tap(find.byKey(const ValueKey(('amaze-adjust', 'size'))));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('amaze-adjustment-slider'));
    tester.widget<Slider>(slider).onChangeEnd!(34);
    await pumpUntil(
      tester,
      () => (slotTool(pen) as PenTool).property.strokeWidth == 34,
      'pen size',
    );
    await tester.pumpAndSettle();
    Finder sizeOf(int slot) => find.byKey(ValueKey(('amaze-slot-size', slot)));
    expect(tester.widget<Text>(sizeOf(pen)).data, '34');
    for (final slot in [slotOf<SelectTool>(), slotOf<HandTool>()]) {
      expect(slot, isNonNegative);
      expect(sizeOf(slot), findsNothing, reason: '${slotTool(slot)}');
    }
    // Empty slots keep their plus and show no number.
    final empty = slotToolIndices(documentTools()).length;
    expect(sizeOf(empty), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a stroke passing under the wheel fades it and keeps drawing', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    await selectSlot(tester, editor, slotOf<PenTool>());
    final bloc = observer.lastDocumentBloc!;
    int elements() => (bloc.state as DocumentLoadSuccess).page.content.length;
    final before = elements();
    final wheel = tester.getRect(find.byKey(_wheel));
    final start = wheel.centerLeft - const Offset(400, 0);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(start + Offset(40.0 * i - 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(fadeOpacity(tester), greaterThan(0));
    }
    // The pointer is now within 12 px of the wheel.
    expect(fadeOpacity(tester), kWheelFadedOpacity);
    await gesture.moveTo(wheel.center);
    await tester.pump(const Duration(milliseconds: 200));
    expect(fadeOpacity(tester), kWheelFadedOpacity);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fadeOpacity(tester), kWheelFadedOpacity);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(fadeOpacity(tester), 1);
    await pumpUntil(tester, () => elements() > before, 'stroke');
    expect(tester.takeException(), isNull);
    // Lets the autosave after the stroke run.
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('pointers that start on the wheel never fade it', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    final wheel = tester.getRect(find.byKey(_wheel));
    final gesture = await tester.startGesture(ringPoint(tester));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(30, -10));
      await tester.pump(const Duration(milliseconds: 16));
      expect(fadeOpacity(tester), 1);
    }
    await gesture.moveTo(wheel.topCenter - const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(wheel.center);
    await tester.pump(const Duration(milliseconds: 16));
    expect(fadeOpacity(tester), 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fadeOpacity(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stroke near a corner of the wheel box does not fade it', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    await selectSlot(tester, editor, slotOf<PenTool>());
    final wheel = tester.getRect(find.byKey(_wheel));
    // Inside the bounding square, but outside the circle plus 12 px.
    final corner = wheel.topLeft + const Offset(4, 4);
    expect((corner - wheel.center).distance, greaterThan(wheel.width / 2 + 12));
    final start = corner - const Offset(300, 0);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(start + Offset(30.0 * i, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(fadeOpacity(tester), 1);
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fadeOpacity(tester), 1);
    await tester.pump(const Duration(minutes: 1));
  });

  /// Presses [position] long enough for a long press, moves by [by] in
  /// steps and releases, or cancels if [cancel].
  Future<void> hold(
    WidgetTester tester,
    Offset position, {
    Offset by = Offset.zero,
    PointerDeviceKind kind = PointerDeviceKind.touch,
    bool cancel = false,
  }) async {
    final gesture = await tester.startGesture(position, kind: kind);
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 0; i < 4 && by != Offset.zero; i++) {
      await gesture.moveBy(by / 4);
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (cancel) {
      await gesture.cancel();
    } else {
      await gesture.up();
    }
    await tester.pumpAndSettle();
  }

  const geometry = ToolWheelGeometry();
  Offset wheelPoint(WidgetTester tester, Offset fromCenter) {
    return tester.getCenter(find.byKey(_wheel)) + fromCenter;
  }

  testWidgets('a long press on a slot drags, or opens the library in place', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    final pen = slotOf<PenTool>();
    final before = tester.getRect(find.byKey(_wheel));

    await hold(
      tester,
      tester.getCenter(slotButton(pen)),
      by: const Offset(-40, 0),
    );
    final moved = tester.getRect(find.byKey(_wheel));
    expect(moved.left, closeTo(before.left - 40, 0.5));
    expect(moved.top, closeTo(before.top, 0.5));
    expect(find.byKey(_library), findsNothing);

    await hold(tester, tester.getCenter(slotButton(pen)));
    expect(find.byKey(_library), findsOneWidget);
    final name = tester.widget<Text>(
      find.byKey(const ValueKey('amaze-library-name')),
    );
    expect(
      name.data,
      slotTool(pen).getDisplay(tester.element(find.byKey(_library))),
    );
    expect(tester.getRect(find.byKey(_wheel)), moved);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long press on the center drags, or collapses in place', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    final before = tester.getRect(find.byKey(_wheel));

    await hold(
      tester,
      wheelPoint(tester, Offset.zero),
      by: const Offset(-40, -40),
    );
    final moved = tester.getRect(find.byKey(_wheel));
    expect(moved.topLeft, before.topLeft - const Offset(40, 40));
    expect(find.byKey(_puck), findsNothing);

    await hold(tester, wheelPoint(tester, Offset.zero));
    expect(find.byKey(_wheel), findsNothing);
    expect(find.byKey(_puck), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long press on an adjustment drags, or does nothing', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    await selectSlot(tester, editor, slotOf<PenTool>());
    final size = geometry.adjustmentLabelCenter(ToolAdjustment.size);
    final before = tester.getRect(find.byKey(_wheel));

    await hold(tester, wheelPoint(tester, size), by: const Offset(-40, 0));
    final moved = tester.getRect(find.byKey(_wheel));
    expect(moved.left, closeTo(before.left - 40, 0.5));

    for (final spot in [
      size,
      geometry.undoCenter,
      Offset.fromDirection(pi, geometry.historyDistance),
    ]) {
      await hold(tester, wheelPoint(tester, spot));
      expect(tester.getRect(find.byKey(_wheel)), moved, reason: '$spot');
      expect(
        find.byKey(const ValueKey('amaze-adjustment-panel')),
        findsNothing,
      );
      expect(find.byKey(_library), findsNothing);
      expect(find.byKey(_puck), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cancelled drag keeps and saves the position', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    final pen = slotOf<PenTool>();
    final before = tester.getRect(find.byKey(_wheel));

    await hold(
      tester,
      tester.getCenter(slotButton(pen)),
      by: const Offset(-80, 0),
      cancel: true,
    );
    final after = tester.getRect(find.byKey(_wheel));
    expect(after.left, closeTo(before.left - 80, 0.5));
    expect(find.byKey(_library), findsNothing);
    expect(find.byKey(const ValueKey('amaze-dock-target')), findsNothing);
    expect(find.byKey(_bar), findsNothing);
    final saved = await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble('amaze.toolWheel.x');
    });
    final freeX = 1280 - 16 - before.width;
    expect(saved, isNotNull);
    expect(saved! * freeX, closeTo(after.left - 8, 1));

    // A cancel before moving opens nothing either.
    await hold(tester, tester.getCenter(slotButton(pen)), cancel: true);
    expect(find.byKey(_library), findsNothing);
    expect(tester.getRect(find.byKey(_wheel)), after);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stylus long press on a slot opens the library', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    await hold(
      tester,
      tester.getCenter(slotButton(slotOf<PenTool>())),
      kind: PointerDeviceKind.stylus,
    );
    expect(find.byKey(_library), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a canvas stroke over the wheel starts no wheel gesture', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final pen = slotOf<PenTool>();
    await selectSlot(tester, editor, pen);
    final index = editor.toolCubit.state.index;
    final wheel = tester.getRect(find.byKey(_wheel));
    final start = wheel.centerLeft - const Offset(300, 0);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(tester.getCenter(slotButton(pen)));
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.moveTo(wheel.center);
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.moveBy(const Offset(-40, -40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_wheel)), wheel);
    expect(find.byKey(_library), findsNothing);
    expect(find.byKey(_puck), findsNothing);
    expect(find.byKey(const ValueKey('amaze-dock-target')), findsNothing);
    expect(editor.toolCubit.state.index, index);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a right click on the wheel does nothing and skips the canvas', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final pen = slotOf<PenTool>();
    await selectSlot(tester, editor, pen);
    final viewport = tester.renderObject(find.byType(MainViewViewport));
    bool onCanvas(HitTestEntry entry) {
      final target = entry.target;
      if (target is! RenderObject) return false;
      for (RenderObject? node = target; node != null; node = node.parent) {
        if (node == viewport) return true;
      }
      return false;
    }

    final bloc = observer.lastDocumentBloc!;
    final document = (bloc.state as DocumentLoadSuccess).page;
    final wheel = tester.getRect(find.byKey(_wheel));
    for (final spot in [
      tester.getCenter(slotButton(slotOf<EraserTool>())),
      wheelPoint(tester, Offset.zero),
      wheelPoint(tester, Offset.fromDirection(pi, geometry.historyDistance)),
    ]) {
      final path = tester.hitTestOnBinding(spot).path;
      expect(path.where(onCanvas), isEmpty, reason: '$spot');
      await tester.tapAt(
        spot,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
    }
    expect(editor.toolCubit.state.handler.data, isA<PenTool>());
    expect((bloc.state as DocumentLoadSuccess).page, document);
    expect(tester.getRect(find.byKey(_wheel)), wheel);
    expect(find.byKey(_library), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a plain scroll over the wheel reaches the canvas', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final wheel = tester.getRect(find.byKey(_wheel));
    final position = editor.transformCubit.state.position;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(wheel.center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pumpAndSettle();
    expect(editor.transformCubit.state.position, isNot(position));
    expect(tester.getRect(find.byKey(_wheel)), wheel);
    expect(tester.takeException(), isNull);
  });

  group('adjustments', () {
    const slider = ValueKey('amaze-adjustment-slider');

    /// Selects the pen and opens its size panel.
    Future<(EditorController, int)> openPenSize(WidgetTester tester) async {
      setScreen(tester, const Size(1280, 800));
      final editor = await openEditor(tester);
      final pen = slotOf<PenTool>();
      await selectSlot(tester, editor, pen);
      await tester.tap(find.byKey(const ValueKey(('amaze-adjust', 'size'))));
      await tester.pumpAndSettle();
      return (editor, pen);
    }

    /// Drags the size slider across ten values, then ends or cancels.
    Future<void> dragSlider(WidgetTester tester, {bool cancel = false}) async {
      final rect = tester.getRect(find.byKey(slider));
      final gesture = await tester.startGesture(
        rect.centerLeft + const Offset(40, 0),
      );
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(18, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pumpAndSettle();
    }

    double penSize(int slot) =>
        (slotTool(slot) as PenTool).property.strokeWidth;

    testWidgets('one slider drag is one undo step', (tester) async {
      final (_, pen) = await openPenSize(tester);
      final start = slotTool(pen);
      final events = observer.toolsChanged;

      final rect = tester.getRect(find.byKey(slider));
      final gesture = await tester.startGesture(
        rect.centerLeft + const Offset(40, 0),
      );
      await tester.pump();
      final shown = <String>{};
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(18, 0));
        await tester.pump(const Duration(milliseconds: 16));
        shown.add(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('amaze-adjustment-value')),
              )
              .data!,
        );
        // The value is previewed, but nothing is dispatched yet.
        expect(observer.toolsChanged, events);
      }
      expect(shown.length, greaterThan(5));
      await gesture.up();
      await pumpUntil(
        tester,
        () => penSize(pen) != (start as PenTool).property.strokeWidth,
        'drag',
      );
      await tester.pumpAndSettle();
      final dragged = penSize(pen);
      expect(observer.toolsChanged, events + 1);

      await tester.tap(find.byKey(const ValueKey('amaze-undo')));
      await pumpUntil(tester, () => slotTool(pen) == start, 'undo');
      await tester.tap(find.byKey(const ValueKey('amaze-redo')));
      await pumpUntil(tester, () => penSize(pen) == dragged, 'redo');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('a cancelled slider drag changes nothing', (tester) async {
      final (_, pen) = await openPenSize(tester);
      final start = slotTool(pen);
      final events = observer.toolsChanged;
      final bloc = observer.lastDocumentBloc!;
      final canUndo = bloc.canUndo;
      String shown() => tester
          .widget<Text>(find.byKey(const ValueKey('amaze-adjustment-value')))
          .data!;
      final before = shown();

      await dragSlider(tester, cancel: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(observer.toolsChanged, events);
      expect(slotTool(pen), start);
      expect(bloc.canUndo, canUndo);
      expect(shown(), before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('size changes the tool, never the selected elements', (
      tester,
    ) async {
      final (editor, pen) = await openPenSize(tester);
      final bloc = observer.lastDocumentBloc!;
      List<String> elements() => [
        for (final element in (bloc.state as DocumentLoadSuccess).page.content)
          jsonEncode(element.toJson()),
      ];
      final renderers = editor.rendererCubit.renderers;
      expect(renderers, isNotEmpty);
      editor.toolCubit.changeSelection(renderers.first);
      await tester.pumpAndSettle();
      expect(editor.toolCubit.state.selection, isNotNull);
      final before = elements();

      await dragSlider(tester);
      await pumpUntil(tester, () => penSize(pen) != 5, 'size');
      await tester.pump(const Duration(milliseconds: 100));
      expect(elements(), before);
      expect(editor.toolCubit.state.handler.data, isA<PenTool>());
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('an unsupported adjustment dispatches nothing', (tester) async {
      setScreen(tester, const Size(1280, 800));
      final editor = await openEditor(tester);
      final eraser = slotOf<EraserTool>();
      await selectSlot(tester, editor, eraser);
      final bloc = observer.lastDocumentBloc!;
      final tools = (bloc.state as DocumentLoadSuccess).info.tools;
      final events = observer.toolsChanged;
      final context = tester.element(find.byKey(_wheel));
      for (final adjustment in [
        ToolAdjustment.opacity,
        ToolAdjustment.smoothing,
      ]) {
        applyWheelAdjustment(context, adjustment, 0.5);
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(observer.toolsChanged, events);
      expect((bloc.state as DocumentLoadSuccess).info.tools, tools);

      applyWheelAdjustment(context, ToolAdjustment.size, 12);
      await pumpUntil(
        tester,
        () => (slotTool(eraser) as EraserTool).strokeWidth == 12,
        'eraser size',
      );
      expect(observer.toolsChanged, events + 1);
      await tester.pump(const Duration(minutes: 1));
    });
  });

  testWidgets('sizes read as points in the disc and as numbers on slots', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final pen = slotOf<PenTool>();
    await selectSlot(tester, editor, pen);
    Finder slotSize() => find.byKey(ValueKey(('amaze-slot-size', pen)));
    String disc() {
      final label = find.descendant(
        of: find.byKey(const ValueKey(('amaze-adjust', 'size'))),
        matching: find.byType(Text),
      );
      return tester.widget<Text>(label).data!;
    }

    Future<void> setSize(double size) async {
      final current = editor.toolCubit.state.handler.data as PenTool;
      if (current.property.strokeWidth != size) {
        await tester.tap(find.byKey(const ValueKey(('amaze-adjust', 'size'))));
        await tester.pumpAndSettle();
        final slider = find.byKey(const ValueKey('amaze-adjustment-slider'));
        tester.widget<Slider>(slider).onChangeEnd!(size);
        await pumpUntil(
          tester,
          () => (slotTool(pen) as PenTool).property.strokeWidth == size,
          'size $size',
        );
        await tester.tap(find.byKey(const ValueKey(('amaze-adjust', 'size'))));
        await tester.pumpAndSettle();
      }
    }

    await setSize(5);
    expect(disc(), '5 pts');
    expect(tester.widget<Text>(slotSize()).data, '5');
    await setSize(2.5);
    expect(disc(), '2.5 pts');
    expect(tester.widget<Text>(slotSize()).data, '2.5');
    await setSize(34);
    expect(disc(), '34 pts');
    expect(tester.widget<Text>(slotSize()).data, '34');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('All tools shows the full tool bar', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);

    await tester.tap(find.byKey(const ValueKey('amaze-dock-all-tools')));
    await tester.pumpAndSettle();
    expect(find.byType(EditToolbar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester, dark: true);
    expect(find.byKey(_wheel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'landscape-dark');
  });

  testWidgets('the classic layout stays available', (tester) async {
    when(() => settingsCubit.state).thenReturn(
      const ButterflySettings(
        defaultTemplate: 'default',
        flags: [kAmazeShellFlag, kClassicEditorFlag],
      ),
    );
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);

    expect(find.byKey(_wheel), findsNothing);
    expect(find.byType(AmazeDock), findsNothing);
    expect(find.byType(EditToolbar), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changes still save in the aMaze shell', (tester) async {
    when(() => settingsCubit.state).thenReturn(
      const ButterflySettings(
        defaultTemplate: 'default',
        autosaveDelaySeconds: 1800,
        flags: [kAmazeShellFlag],
      ),
    );
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    final bloc = observer.lastDocumentBloc!;
    final saveCubit = bloc.editorController.saveCubit;

    bloc.add(const DocumentDescriptionChanged(name: 'Saved in aMaze'));
    await pumpUntil(
      tester,
      () => saveCubit.state.isSaveDelayed,
      'delayed autosave',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await pumpUntil(
      tester,
      () => saveCubit.state.saved == SaveState.saved,
      'save',
    );

    final system = fileSystem.buildDocumentSystem();
    final saved = await system.getAsset('amaze.bfly');
    expect(saved, isA<FileSystemFile<NoteFile>>());
    final file = saved as FileSystemFile<NoteFile>;
    expect(file.data?.display()?.getMetadata()?.name, 'Saved in aMaze');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(minutes: 30));
  });
}

class _DocumentObserver extends BlocObserver {
  DocumentBloc? lastDocumentBloc;

  /// How many [ToolsChanged] events the document received.
  int toolsChanged = 0;

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    if (bloc is DocumentBloc) lastDocumentBloc = bloc;
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    if (event is ToolsChanged) toolsChanged++;
  }
}
