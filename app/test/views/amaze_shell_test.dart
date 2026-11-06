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
import 'package:butterfly/views/amaze/shell.dart';
import 'package:butterfly/views/amaze/tool_slots.dart';
import 'package:butterfly/views/amaze/tool_wheel.dart';
import 'package:butterfly/views/app_bar.dart';
import 'package:butterfly/views/edit.dart';
import 'package:butterfly/views/main.dart';
import 'package:butterfly/views/navigator/layers.dart';
import 'package:butterfly/views/toolbar/view.dart';
import 'package:butterfly/views/zoom.dart';
import 'package:butterfly/visualizer/tool.dart';
import 'package:butterfly_api/butterfly_api.dart';
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

  /// A point on the outer ring between undo and the first slot.
  Offset ringPoint(WidgetTester tester) {
    const geometry = ToolWheelGeometry();
    const angle = 126 * pi / 180;
    final direction = Offset(cos(angle), sin(angle));
    final center = tester.getCenter(find.byKey(_wheel));
    return center + direction * geometry.slotDistance;
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
    final market = find.byKey(const ValueKey('amaze-library-market'));
    await tester.ensureVisible(market);
    await tester.pumpAndSettle();
    await tester.tap(market);
    await tester.pumpAndSettle();
    final last = libraryItem(LibraryEntry.inkBlot);
    await tester.ensureVisible(last);
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

  testWidgets('the wheel and the tool bar share the instrument theme', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    Brightness brightnessOf(Finder finder) {
      return Theme.of(tester.element(finder)).colorScheme.brightness;
    }

    expect(brightnessOf(find.byKey(_wheel)), Brightness.dark);
    await dockWheel(tester);
    expect(brightnessOf(find.byKey(_bar)), Brightness.dark);
    expect(tester.takeException(), isNull);
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

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    if (bloc is DocumentBloc) lastDocumentBloc = bloc;
  }
}
