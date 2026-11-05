import 'dart:convert';
import 'dart:io';
import 'dart:math' show Point, min;
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
import 'package:butterfly/views/amaze/shell.dart';
import 'package:butterfly/views/app_bar.dart';
import 'package:butterfly/views/edit.dart';
import 'package:butterfly/views/main.dart';
import 'package:butterfly/views/navigator/layers.dart';
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
const _hub = ValueKey('amaze-tool-wheel-hub');
const _puck = ValueKey('amaze-tool-wheel-puck');
const _layers = ValueKey(('amaze-dock', 'layers'));
const _amaze = ButterflySettings(
  defaultTemplate: 'default',
  flags: [kAmazeShellFlag],
);

/// Loads the bundled fonts so screenshots show real text and icons.
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

/// Temporary: prints screenshots to the CI log so they can be reviewed
/// where artifact downloads are blocked.
void _printForReview(String name, List<int> bytes) {
  if (Platform.environment['GITHUB_ACTIONS'] != 'true') return;
  final encoded = base64Encode(bytes);
  stdout.writeln('AMAZE-SHOT-BEGIN $name');
  for (var i = 0; i < encoded.length; i += 4000) {
    stdout.writeln(encoded.substring(i, min(encoded.length, i + 4000)));
  }
  stdout.writeln('AMAZE-SHOT-END $name');
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

  Widget buildApp(NoteData document, {bool dark = false}) {
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
            theme: getThemeData('', dark),
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
  }) async {
    final data = document ?? _sampleDocument();
    await tester.pumpWidget(buildApp(data, dark: dark));
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
      _printForReview(name, bytes);
    });
  }

  testWidgets('landscape tablets get the dock, tool wheel and floating bar', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);

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
    await openEditor(tester);

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

  testWidgets('the wheel switches to the tapped tool', (tester) async {
    setScreen(tester, const Size(1280, 800));
    final editor = await openEditor(tester);
    final state = observer.lastDocumentBloc!.state as DocumentLoadSuccess;
    final pen = state.info.tools.indexWhere((tool) => tool is PenTool);
    final hand = state.info.tools.indexWhere((tool) => tool is HandTool);

    await tester.tap(find.byKey(ValueKey(('amaze-tool-wheel-slot', hand))));
    await pumpUntil(
      tester,
      () => editor.toolCubit.state.index == hand,
      'hand selected',
    );
    await tester.tap(find.byKey(ValueKey(('amaze-tool-wheel-slot', pen))));
    await pumpUntil(
      tester,
      () => editor.toolCubit.state.index == pen,
      'pen selected',
    );
    expect(editor.toolCubit.state.handler.data, isA<PenTool>());
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
    await tester.tap(find.byKey(const ValueKey('amaze-tool-wheel-undo')));
    await pumpUntil(tester, () => description() == original, 'undo');
    await tester.tap(find.byKey(const ValueKey('amaze-tool-wheel-redo')));
    await pumpUntil(tester, () => description() == 'Edited note', 'redo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the hub moves the wheel within the screen', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);
    final before = tester.getTopLeft(find.byKey(_wheel));

    await tester.drag(find.byKey(_hub), const Offset(-300, -200));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.byKey(_wheel));
    expect(after.dx, lessThan(before.dx - 200));
    expect(after.dy, lessThan(before.dy - 100));

    await tester.drag(find.byKey(_hub), const Offset(-5000, -5000));
    await tester.pumpAndSettle();
    final corner = tester.getRect(find.byKey(_wheel));
    expect(corner.left, greaterThanOrEqualTo(0));
    expect(corner.top, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('holding the current tool collapses the wheel', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await openEditor(tester);

    await tester.longPress(
      find.byKey(const ValueKey('amaze-tool-wheel-current')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_wheel), findsNothing);
    expect(find.byKey(_puck), findsOneWidget);

    await tester.tap(find.byKey(_puck));
    await tester.pumpAndSettle();
    expect(find.byKey(_wheel), findsOneWidget);
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
