import 'dart:convert';
import 'dart:math';

import 'package:butterfly/actions/shortcuts.dart';
import 'package:butterfly/api/open.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/models/defaults.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/services/font.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/theme.dart';
import 'package:butterfly/views/amaze/shell.dart';
import 'package:butterfly/views/amaze/tool_wheel.dart';
import 'package:butterfly/views/amaze/wheel_prefs.dart';
import 'package:butterfly/views/main.dart';
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

const _wheel = ValueKey('amaze-tool-wheel');
const _diameterKey = 'amaze.toolWheel.diameter';

/// Saved prefs that put the wheel in the middle of the layer.
const _centered = <String, Object>{
  'amaze.toolWheel.x': 0.5,
  'amaze.toolWheel.y': 0.5,
};

/// Loads the bundled fonts, so text has its real size.
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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(const AssetLocation(path: 'fallback.bfly'));
    await _loadFonts();
  });

  group('saved size', () {
    Future<double?> loadDiameter(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return (await loadToolWheelLayout()).diameter;
    }

    test('a saved diameter loads back', () async {
      expect(await loadDiameter({_diameterKey: 400.0}), 400);
    });

    test('layouts without a size load the default', () async {
      expect(await loadDiameter({'amaze.toolWheel.mode': 'wheel'}), isNull);
      expect(await loadDiameter({}), isNull);
    });

    test('saved sizes are clamped to the supported range', () async {
      expect(await loadDiameter({_diameterKey: 900.0}), kToolWheelMaxDiameter);
      expect(await loadDiameter({_diameterKey: 100.0}), kToolWheelMinDiameter);
    });

    test('saving and loading keeps the size', () async {
      SharedPreferences.setMockInitialValues({});
      await saveToolWheelLayout(const ToolWheelLayout(diameter: 352));
      expect((await loadToolWheelLayout()).diameter, 352);
    });
  });

  group('resizing the wheel layer', () {
    late ValueNotifier<bool> shown;

    /// Pumps the wheel layer with the default pen active, in a layer of
    /// [layer] (the whole 1280x800 screen by default).
    Future<void> pumpLayer(
      WidgetTester tester, {
      Map<String, Object> prefs = _centered,
      Size? layer,
    }) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues(prefs);
      final fileSystem = MockButterflyFileSystem();
      final settings = fileSystem.settingsCubit as MockSettingsCubit;
      when(() => settings.state)
          .thenReturn(const ButterflySettings(autosave: false));
      when(() => settings.stream).thenAnswer((_) => const Stream.empty());
      when(() => settings.addRecentHistory(any())).thenAnswer((_) async {});
      final editor = EditorController(
        settings,
        TransformCubit(1),
        CameraViewport.unbaked(),
      );
      final window = WindowCubit(fullScreen: false);
      final data = DocumentDefaults.createDocument(name: 'wheel');
      final bloc = (await tester.runAsync(() async {
        final bloc = DocumentBloc(
          fileSystem,
          editor,
          window,
          data,
          const AssetLocation(path: 'wheel.bfly'),
        );
        await pumpEventQueue();
        return bloc;
      }))!;
      final state = bloc.state as DocumentLoadSuccess;
      final index = state.info.tools.indexWhere((tool) => tool is PenTool);
      final tools = ToolCubit(
        ToolRuntimeState(
          index: index,
          handler: Handler.fromTool(state.info.tools[index]),
        ),
      );
      shown = ValueNotifier(true);
      addTearDown(() async {
        shown.dispose();
        await tester.runAsync(() async {
          await tools.close();
          await bloc.close();
          await editor.close();
          await window.close();
        });
      });
      Widget layerWidget = const AmazeToolWheelLayer();
      if (layer != null) {
        layerWidget = Center(
          child: SizedBox.fromSize(
            key: const ValueKey('test-layer'),
            size: layer,
            child: layerWidget,
          ),
        );
      }
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<DocumentBloc>.value(value: bloc),
            BlocProvider<ToolCubit>.value(value: tools),
          ],
          child: MaterialApp(
            theme: getThemeData('', false),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              LeapLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: shown,
                builder: (context, visible, _) =>
                    visible ? layerWidget : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Rect wheel(WidgetTester tester) => tester.getRect(find.byKey(_wheel));

    Future<double?> savedDiameter(WidgetTester tester) {
      return tester.runAsync<double?>(() async {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getDouble(_diameterKey);
      });
    }

    testWidgets('Ctrl + scroll changes the size by 16 per notch', (
      tester,
    ) async {
      await pumpLayer(tester);
      final center = wheel(tester).center;
      expect(wheel(tester).width, 320);

      await _scroll(tester, center, -100, notches: 3, control: true);
      expect(wheel(tester).width, 368);
      expect(wheel(tester).center, _near(center));
      expect(await savedDiameter(tester), 368);

      await _scroll(tester, center, 100, notches: 6, control: true);
      expect(wheel(tester).width, 272);
      expect(wheel(tester).center, _near(center));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ctrl + scroll stops at the limits', (tester) async {
      await pumpLayer(tester);
      final center = wheel(tester).center;
      await _scroll(tester, center, -100, notches: 20, control: true);
      expect(wheel(tester).width, kToolWheelMaxDiameter);
      await _scroll(tester, center, 100, notches: 30, control: true);
      expect(wheel(tester).width, kToolWheelMinDiameter);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a plain scroll leaves the size alone', (tester) async {
      await pumpLayer(tester);
      final center = wheel(tester).center;
      await _scroll(tester, center, -100, notches: 3, control: false);
      await _scroll(tester, center, 100, notches: 3, control: false);
      expect(wheel(tester).width, 320);
      expect(await savedDiameter(tester), isNull);
    });

    testWidgets('a two-finger pinch on the wheel resizes it', (tester) async {
      await pumpLayer(tester);
      final center = wheel(tester).center;
      final first = await tester.startGesture(
        center - const Offset(60, 0),
        pointer: 1,
        kind: PointerDeviceKind.touch,
      );
      final second = await tester.startGesture(
        center + const Offset(60, 0),
        pointer: 2,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        await first.moveBy(const Offset(-10, 0));
        await second.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      // The fingers are 160 apart instead of 120.
      expect(wheel(tester).width, closeTo(320 * 160 / 120, 0.01));
      expect(wheel(tester).center, _near(center));
      expect(await savedDiameter(tester), isNull);

      for (var i = 0; i < 10; i++) {
        await first.moveBy(const Offset(-20, 0));
        await second.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      expect(wheel(tester).width, kToolWheelMaxDiameter);
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(await savedDiameter(tester), kToolWheelMaxDiameter);
      // Neither finger counted as a tap on an adjustment.
      expect(
        find.byKey(const ValueKey('amaze-adjustment-panel')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cancelled pinch keeps and saves the last size', (
      tester,
    ) async {
      await pumpLayer(tester);
      final center = wheel(tester).center;
      final first = await tester.startGesture(
        center - const Offset(60, 0),
        pointer: 1,
        kind: PointerDeviceKind.touch,
      );
      final second = await tester.startGesture(
        center + const Offset(60, 0),
        pointer: 2,
        kind: PointerDeviceKind.touch,
      );
      await first.moveBy(const Offset(15, 0));
      await second.moveBy(const Offset(-15, 0));
      await tester.pump();
      final size = wheel(tester).width;
      expect(size, closeTo(320 * 90 / 120, 0.01));
      await first.cancel();
      await second.cancel();
      await tester.pumpAndSettle();
      expect(wheel(tester).width, size);
      expect(await savedDiameter(tester), size);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a stylus never resizes the wheel', (tester) async {
      await pumpLayer(tester);
      final center = wheel(tester).center;
      final first = await tester.startGesture(
        center - const Offset(60, 0),
        pointer: 1,
        kind: PointerDeviceKind.stylus,
      );
      final second = await tester.startGesture(
        center + const Offset(60, 0),
        pointer: 2,
        kind: PointerDeviceKind.stylus,
      );
      await first.moveBy(const Offset(-40, 0));
      await second.moveBy(const Offset(40, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(wheel(tester).width, 320);
    });

    testWidgets('a resize at the screen edge keeps the wheel inside', (
      tester,
    ) async {
      await pumpLayer(
        tester,
        prefs: {'amaze.toolWheel.x': 1.0, 'amaze.toolWheel.y': 1.0},
      );
      final before = wheel(tester);
      await _scroll(tester, before.center, -100, notches: 5, control: true);
      final after = wheel(tester);
      expect(after.width, 400);
      expect(after.right, closeTo(1280, 0.01));
      expect(after.bottom, closeTo(800, 0.01));
      expect(after.left, greaterThanOrEqualTo(0));
      expect(after.top, greaterThanOrEqualTo(0));
    });

    testWidgets('the ring still drags the wheel after a resize', (
      tester,
    ) async {
      await pumpLayer(tester);
      await _scroll(
        tester,
        wheel(tester).center,
        -100,
        notches: 5,
        control: true,
      );
      final before = wheel(tester);
      expect(before.width, 400);
      const geometry = ToolWheelGeometry(diameter: 400);
      const angle = pi; // The gap between undo and redo.
      final ring =
          before.center +
          Offset(cos(angle), sin(angle)) * geometry.historyDistance;
      final gesture = await tester.startGesture(ring);
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveBy(const Offset(-150, -100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final after = wheel(tester);
      expect(after.width, 400);
      expect(after.left, closeTo(before.left - 150, 0.5));
      expect(after.top, closeTo(before.top - 100, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the size survives a rebuild', (tester) async {
      await pumpLayer(tester);
      await _scroll(
        tester,
        wheel(tester).center,
        -100,
        notches: 3,
        control: true,
      );
      expect(wheel(tester).width, 368);

      shown.value = false;
      await tester.pumpAndSettle();
      expect(find.byKey(_wheel), findsNothing);
      shown.value = true;
      await tester.pumpAndSettle();
      expect(wheel(tester).width, 368);
    });

    testWidgets('a small layer limits the size, but not below 240', (
      tester,
    ) async {
      await pumpLayer(
        tester,
        prefs: {..._centered, _diameterKey: 400.0},
        layer: const Size(300, 300),
      );
      expect(wheel(tester).width, 300 - 16);
      await _scroll(
        tester,
        wheel(tester).center,
        -100,
        notches: 3,
        control: true,
      );
      expect(wheel(tester).width, 300 - 16);
      await _scroll(
        tester,
        wheel(tester).center,
        100,
        notches: 10,
        control: true,
      );
      expect(wheel(tester).width, kToolWheelMinDiameter);
      final layer = tester.getRect(find.byKey(const ValueKey('test-layer')));
      final rect = wheel(tester);
      expect(rect.left, greaterThanOrEqualTo(layer.left));
      expect(rect.right, lessThanOrEqualTo(layer.right));
      expect(rect.top, greaterThanOrEqualTo(layer.top));
      expect(rect.bottom, lessThanOrEqualTo(layer.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a layer smaller than the minimum keeps 240', (tester) async {
      await pumpLayer(tester, layer: const Size(200, 200));
      expect(wheel(tester).width, kToolWheelMinDiameter);
      expect(tester.takeException(), isNull);
    });
  });

  _canvasTests();
}

/// Matches an offset within half a pixel.
Matcher _near(Offset expected) {
  return predicate<Offset>(
    (offset) => (offset - expected).distance < 0.5,
    'within 0.5 px of $expected',
  );
}

/// Sends [notches] mouse wheel notches of [dy] at [position], with Ctrl
/// held if [control], then waits for the debounced save.
Future<void> _scroll(
  WidgetTester tester,
  Offset position,
  double dy, {
  required int notches,
  required bool control,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(position));
  for (var i = 0; i < notches; i++) {
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Opens the real editor so the canvas sits under the wheel.
void _canvasTests() {
  group('canvas under the wheel', () {
    late MockSettingsCubit settingsCubit;
    late MockButterflyFileSystem fileSystem;
    late WindowCubit windowCubit;
    late GoRouter router;
    late _DocumentObserver observer;
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
      SharedPreferences.setMockInitialValues({});
      settingsCubit = MockSettingsCubit();
      fileSystem = MockButterflyFileSystem(settingsCubit: settingsCubit);
      windowCubit = WindowCubit(fullScreen: false);
      observer = _DocumentObserver();
      previousObserver = Bloc.observer;
      Bloc.observer = observer;
      when(() => settingsCubit.state).thenReturn(
        const ButterflySettings(
          defaultTemplate: 'default',
          flags: [kAmazeShellFlag],
        ),
      );
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

    Future<EditorController> openEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final document = DocumentDefaults.createDocument(name: 'resize');
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
                    AssetLocation.local('resize.bfly'),
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
      await tester.pumpWidget(
        MultiRepositoryProvider(
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
              theme: getThemeData('', false),
              localizationsDelegates: const [
                ...AppLocalizations.localizationsDelegates,
                LeapLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-document')));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        if (observer.lastDocumentBloc?.state is DocumentLoadSuccess) break;
      }
      expect(observer.lastDocumentBloc?.state, isA<DocumentLoadSuccess>());
      await tester.pumpAndSettle();
      return observer.lastDocumentBloc!.editorController;
    }

    testWidgets('resizing over the wheel leaves the canvas alone', (
      tester,
    ) async {
      final editor = await openEditor(tester);
      final transform = editor.transformCubit.state;
      final elements = (observer.lastDocumentBloc!.state as DocumentLoadSuccess)
          .page
          .content
          .length;
      Rect wheel() => tester.getRect(find.byKey(_wheel));
      final start = wheel().width;

      final center = wheel().center;
      final first = await tester.startGesture(
        center - const Offset(60, 0),
        pointer: 1,
        kind: PointerDeviceKind.touch,
      );
      final second = await tester.startGesture(
        center + const Offset(60, 0),
        pointer: 2,
        kind: PointerDeviceKind.touch,
      );
      for (var i = 0; i < 3; i++) {
        await first.moveBy(const Offset(10, 0));
        await second.moveBy(const Offset(-10, 0));
        await tester.pump();
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(wheel().width, lessThan(start));
      expect(editor.transformCubit.state.position, transform.position);
      expect(editor.transformCubit.state.size, transform.size);

      final pinched = wheel().width;
      await _scroll(tester, wheel().center, -100, notches: 3, control: true);
      expect(wheel().width, pinched + 48);
      expect(editor.transformCubit.state.position, transform.position);
      expect(editor.transformCubit.state.size, transform.size);
      final after = observer.lastDocumentBloc!.state as DocumentLoadSuccess;
      expect(after.page.content.length, elements);
      expect(tester.takeException(), isNull);
    });
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
