import 'dart:convert';
import 'dart:math';

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
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly/views/amaze/shell.dart';
import 'package:butterfly/views/amaze/style.dart';
import 'package:butterfly/views/amaze/tool_slots.dart';
import 'package:butterfly/views/amaze/tool_wheel.dart';
import 'package:butterfly/views/amaze/wheel_presets.dart';
import 'package:butterfly/views/main.dart';
import 'package:butterfly/views/view.dart';
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
const _panel = ValueKey('amaze-adjustment-panel');
const _field = ValueKey('amaze-adjustment-field');

Finder _preset(int index) => find.byKey(ValueKey(('amaze-preset', index)));

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
  group('preset data', () {
    final pen = Tool.pen();
    final fixedWidth = LibraryEntry.fixedWidth.createTool()!;
    const sizeKey = 'amaze.presets.pen.size';

    test('tool kinds: library entries, then the tool type', () {
      expect(presetToolKey(pen), 'pen');
      expect(presetToolKey(Tool.pen(name: 'Other pen')), 'pen');
      expect(presetToolKey(LibraryEntry.pen.createTool()!), 'pen');
      expect(presetToolKey(fixedWidth), 'fixedWidth');
      expect(presetToolKey(Tool.eraser()), 'eraser');
      expect(presetToolKey(LibraryEntry.slice.createTool()!), 'slice');
    });

    test('a missing key gives the defaults', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await loadPresets(pen, ToolAdjustment.size), [2, 5, 10, 25]);
      expect(await loadPresets(pen, ToolAdjustment.opacity), [
        0.25,
        0.5,
        0.75,
        1.0,
      ]);
      expect(await loadPresets(pen, ToolAdjustment.smoothing), [
        0,
        0.25,
        0.5,
        0.75,
      ]);
    });

    test('corrupt data gives the defaults', () async {
      for (final saved in <Object>[
        ['a', 'b', 'c', 'd'],
        ['1', '2', '3'],
        ['1', '2', '3', '4', '5'],
        ['1', '2', 'NaN', '4'],
        'not a list',
        42,
      ]) {
        SharedPreferences.setMockInitialValues({sizeKey: saved});
        expect(await loadPresets(pen, ToolAdjustment.size), [
          2,
          5,
          10,
          25,
        ], reason: '$saved');
      }
    });

    test('saved presets load back', () async {
      SharedPreferences.setMockInitialValues({});
      await savePresets(pen, ToolAdjustment.size, [1, 3, 7.5, 40]);
      expect(await loadPresets(pen, ToolAdjustment.size), [1, 3, 7.5, 40]);
    });

    test('values are clamped to the tool range', () async {
      SharedPreferences.setMockInitialValues({
        sizeKey: ['0.01', '100', '5', '5'],
        'amaze.presets.pen.opacity': ['-1', '0.5', '2', '1'],
      });
      expect(await loadPresets(pen, ToolAdjustment.size), [0.1, 70, 5, 5]);
      expect(await loadPresets(pen, ToolAdjustment.opacity), [0, 0.5, 1, 1]);
    });

    test('pens share presets; pen and fixed width do not', () async {
      SharedPreferences.setMockInitialValues({});
      await savePresets(Tool.pen(name: 'A'), ToolAdjustment.size, [1, 2, 3, 4]);
      expect(await loadPresets(Tool.pen(name: 'B'), ToolAdjustment.size), [
        1,
        2,
        3,
        4,
      ]);
      expect(await loadPresets(fixedWidth, ToolAdjustment.size), [
        2,
        5,
        10,
        25,
      ]);
      await savePresets(fixedWidth, ToolAdjustment.size, [9, 9, 9, 9]);
      expect(await loadPresets(pen, ToolAdjustment.size), [1, 2, 3, 4]);
    });

    test('presets match within 0.5%', () {
      expect(presetMatches(5, 5.02), isTrue);
      expect(presetMatches(5, 5.1), isFalse);
      expect(presetMatches(0, 0), isTrue);
    });
  });

  group('wheel', () {
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
      await _loadFonts();
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      settingsCubit = MockSettingsCubit();
      fileSystem = MockButterflyFileSystem(settingsCubit: settingsCubit);
      windowCubit = WindowCubit(fullScreen: false);
      observer = _Observer();
      previousObserver = Bloc.observer;
      Bloc.observer = observer;
      when(() => settingsCubit.state).thenReturn(
        const ButterflySettings(
          defaultTemplate: 'default',
          autosave: false,
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

    DocumentBloc bloc() => observer.document!;
    List<Tool> tools() => (bloc().state as DocumentLoadSuccess).info.tools;

    int slotOf<T extends Tool>() {
      final all = tools();
      return slotToolIndices(all).indexWhere((index) => all[index] is T);
    }

    Tool slotTool(int slot) => tools()[slotToolIndices(tools())[slot]];

    PenTool pen() => slotTool(slotOf<PenTool>()) as PenTool;

    double opacity() => pen().property.paint.previewColor.a / 255;

    /// Opens the editor with the pen selected.
    Future<EditorController> openEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final document = DocumentDefaults.createDocument(
        name: 'presets',
        page: DocumentPage(
          layers: [
            DocumentLayer(
              content: [
                PadElement.shape(
                  firstPosition: const Point(100.0, 100.0),
                  secondPosition: const Point(300.0, 300.0),
                  property: const ShapeProperty(shape: RectangleShape()),
                ),
              ],
            ),
          ],
        ),
      );
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
                    AssetLocation.local('presets.bfly'),
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
      await pumpUntil(
        tester,
        () => observer.document?.state is DocumentLoadSuccess,
        'document open',
      );
      await tester.pumpAndSettle();
      final editor = bloc().editorController;
      final index = slotToolIndices(tools())[slotOf<PenTool>()];
      await tester.tap(find.byKey(ValueKey(('amaze-slot', slotOf<PenTool>()))));
      await pumpUntil(
        tester,
        () => editor.toolCubit.state.index == index,
        'pen',
      );
      await tester.pumpAndSettle();
      return editor;
    }

    Future<void> openPanel(
      WidgetTester tester,
      ToolAdjustment adjustment,
    ) async {
      await tester.tap(find.byKey(ValueKey(('amaze-adjust', adjustment.name))));
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsOneWidget);
    }

    Future<void> undo(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('amaze-undo')));
      await tester.pump();
    }

    Offset sector(WidgetTester tester, ToolAdjustment adjustment) {
      const geometry = ToolWheelGeometry();
      return tester.getCenter(find.byKey(_wheel)) +
          geometry.adjustmentLabelCenter(adjustment);
    }

    /// Sets an adjustment directly, as one step, before a test gesture.
    Future<void> setValue(
      WidgetTester tester,
      ToolAdjustment adjustment,
      double value,
      bool Function() done,
    ) async {
      applyWheelAdjustment(
        tester.element(find.byKey(_wheel)),
        adjustment,
        value,
      );
      await pumpUntil(tester, done, '$adjustment $value');
      await tester.pumpAndSettle();
    }

    Color chipColor(WidgetTester tester, int index) {
      final material = find.descendant(
        of: _preset(index),
        matching: find.byType(Material),
      );
      return tester.widget<Material>(material.first).color!;
    }

    Color accent(WidgetTester tester) {
      return AmazeStyle.of(tester.element(find.byKey(_panel))).accent;
    }

    String chipLabel(WidgetTester tester, int index) {
      final text = find.descendant(
        of: _preset(index),
        matching: find.byType(Text),
      );
      return tester.widget<Text>(text).data!;
    }

    testWidgets('tapping a preset applies it as one undo step', (tester) async {
      await openEditor(tester);
      await openPanel(tester, ToolAdjustment.size);
      expect(pen().property.strokeWidth, 5);
      expect(chipLabel(tester, 2), '10 pts');
      expect(chipColor(tester, 1), accent(tester));
      final events = observer.toolsChanged;

      await tester.tap(_preset(2));
      await pumpUntil(tester, () => pen().property.strokeWidth == 10, 'preset');
      await tester.pumpAndSettle();
      expect(observer.toolsChanged, events + 1);
      expect(chipColor(tester, 2), accent(tester));
      expect(chipColor(tester, 1), isNot(accent(tester)));

      await undo(tester);
      await pumpUntil(tester, () => pen().property.strokeWidth == 5, 'undo');
      expect(tester.takeException(), isNull);
    });

    testWidgets('holding a preset saves the current value into it', (
      tester,
    ) async {
      await openEditor(tester);
      await setValue(
        tester,
        ToolAdjustment.size,
        7,
        () => pen().property.strokeWidth == 7,
      );
      await openPanel(tester, ToolAdjustment.size);
      final events = observer.toolsChanged;
      await tester.longPress(_preset(0));
      await tester.pumpAndSettle();
      expect(chipLabel(tester, 0), '7 pts');
      expect(chipColor(tester, 0), accent(tester));
      expect(observer.toolsChanged, events);
      final saved = await tester.runAsync(() async {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getStringList('amaze.presets.pen.size');
      });
      expect(saved?.map(double.parse), [7, 5, 10, 25]);

      // Closing and opening the panel loads the presets again.
      await tester.tap(find.byKey(const ValueKey(('amaze-adjust', 'size'))));
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsNothing);
      await openPanel(tester, ToolAdjustment.size);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(chipLabel(tester, 0), '7 pts');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the value field applies valid input only', (tester) async {
      await openEditor(tester);
      await openPanel(tester, ToolAdjustment.size);
      final field = find.byKey(_field);
      expect(tester.widget<TextField>(field).controller!.text, '5');
      final events = observer.toolsChanged;

      await tester.enterText(field, '12');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpUntil(tester, () => pen().property.strokeWidth == 12, 'field');
      expect(observer.toolsChanged, events + 1);

      await tester.enterText(field, '500');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Enter a value from 0.1 to 70'), findsOneWidget);
      await tester.enterText(field, 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Enter a value from 0.1 to 70'), findsOneWidget);
      expect(pen().property.strokeWidth, 12);
      expect(observer.toolsChanged, events + 1);

      await tester.showKeyboard(field);
      await tester.enterText(field, '33');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '12');
      expect(find.text('Enter a value from 0.1 to 70'), findsNothing);
      expect(pen().property.strokeWidth, 12);
      expect(observer.toolsChanged, events + 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the value field takes percent for opacity', (tester) async {
      await openEditor(tester);
      await openPanel(tester, ToolAdjustment.opacity);
      final field = find.byKey(_field);
      expect(tester.widget<TextField>(field).controller!.text, '100');
      await tester.enterText(field, '40');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpUntil(tester, () => (opacity() - 0.4).abs() < 0.01, 'opacity');
      expect(tester.takeException(), isNull);
    });

    /// Presses [start], drags vertically by [dy] right away and releases or
    /// cancels.
    Future<void> scrub(
      WidgetTester tester,
      Offset start,
      double dy, {
      bool cancel = false,
      PointerDeviceKind kind = PointerDeviceKind.touch,
    }) async {
      final gesture = await tester.startGesture(start, kind: kind);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(Offset(0, dy / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump();
    }

    String discLabel(WidgetTester tester, ToolAdjustment adjustment) {
      final text = find.descendant(
        of: find.byKey(ValueKey(('amaze-adjust', adjustment.name))),
        matching: find.byType(Text),
      );
      return tester.widget<Text>(text).data!;
    }

    for (final kind in [
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.mouse,
    ]) {
      testWidgets('scrubbing opacity with ${kind.name}', (tester) async {
        final editor = await openEditor(tester);
        await setValue(
          tester,
          ToolAdjustment.opacity,
          0.25,
          () => (opacity() - 0.25).abs() < 0.01,
        );
        final wheel = tester.getRect(find.byKey(_wheel));
        final transform = editor.transformCubit.state;
        final elements = (bloc().state as DocumentLoadSuccess).page.content;
        final start = sector(tester, ToolAdjustment.opacity);
        final viewport = tester.renderObject(find.byType(MainViewViewport));
        final onCanvas = tester.hitTestOnBinding(start).path.where((entry) {
          for (
            RenderObject? node = entry.target is RenderObject
                ? entry.target as RenderObject
                : null;
            node != null;
            node = node.parent
          ) {
            if (node == viewport) return true;
          }
          return false;
        });
        expect(onCanvas, isEmpty);
        final events = observer.toolsChanged;

        final gesture = await tester.startGesture(start, kind: kind);
        for (var i = 0; i < 10; i++) {
          await gesture.moveBy(const Offset(0, -10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        // The label follows live; the tool changes on release.
        expect(discLabel(tester, ToolAdjustment.opacity), '75%');
        expect(observer.toolsChanged, events);
        await gesture.up();
        await pumpUntil(tester, () => (opacity() - 0.75).abs() < 0.01, 'scrub');
        await tester.pumpAndSettle();
        expect(observer.toolsChanged, events + 1);
        expect(tester.getRect(find.byKey(_wheel)), wheel);
        expect(editor.transformCubit.state.position, transform.position);
        expect(editor.transformCubit.state.size, transform.size);
        expect((bloc().state as DocumentLoadSuccess).page.content, elements);
        expect(find.byKey(_panel), findsNothing);
        expect(pen().property.strokeWidth, 5);

        await undo(tester);
        await pumpUntil(tester, () => (opacity() - 0.25).abs() < 0.01, 'undo');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a cancelled scrub changes nothing', (tester) async {
      await openEditor(tester);
      await setValue(
        tester,
        ToolAdjustment.opacity,
        0.25,
        () => (opacity() - 0.25).abs() < 0.01,
      );
      final events = observer.toolsChanged;
      final canUndo = bloc().canUndo;
      await scrub(
        tester,
        sector(tester, ToolAdjustment.opacity),
        -100,
        cancel: true,
      );
      await tester.pumpAndSettle();
      expect(discLabel(tester, ToolAdjustment.opacity), '25%');
      expect((opacity() - 0.25).abs(), lessThan(0.01));
      expect(observer.toolsChanged, events);
      expect(bloc().canUndo, canUndo);
      expect(tester.takeException(), isNull);
    });

    testWidgets('size scrubs on a log scale', (tester) async {
      await openEditor(tester);
      final range = pen().adjustmentRange(ToolAdjustment.size);
      await setValue(
        tester,
        ToolAdjustment.size,
        range.min,
        () => pen().property.strokeWidth == range.min,
      );
      await scrub(tester, sector(tester, ToolAdjustment.size), -100);
      final mean = sqrt(range.min * range.max);
      await pumpUntil(
        tester,
        () => (pen().property.strokeWidth - mean).abs() < mean * 0.05,
        'log size',
      );
      expect(pen().property.strokeWidth, closeTo(mean, mean * 0.05));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the mouse wheel over a sector steps the value once', (
      tester,
    ) async {
      final editor = await openEditor(tester);
      await setValue(
        tester,
        ToolAdjustment.opacity,
        0.5,
        () => (opacity() - 0.5).abs() < 0.01,
      );
      final transform = editor.transformCubit.state;
      final wheel = tester.getRect(find.byKey(_wheel));
      final events = observer.toolsChanged;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(sector(tester, ToolAdjustment.opacity)),
      );
      for (var i = 0; i < 10; i++) {
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(discLabel(tester, ToolAdjustment.opacity), '60%');
      expect(observer.toolsChanged, events);
      await tester.pump(const Duration(milliseconds: 350));
      await pumpUntil(tester, () => (opacity() - 0.6).abs() < 0.01, 'scroll');
      expect(observer.toolsChanged, events + 1);
      expect(editor.transformCubit.state.position, transform.position);
      expect(tester.getRect(find.byKey(_wheel)), wheel);

      await undo(tester);
      await pumpUntil(tester, () => (opacity() - 0.5).abs() < 0.01, 'undo');
      expect(tester.takeException(), isNull);
    });

    testWidgets('holding a sector, then dragging, still moves the wheel', (
      tester,
    ) async {
      await openEditor(tester);
      final before = tester.getRect(find.byKey(_wheel));
      final events = observer.toolsChanged;
      final gesture = await tester.startGesture(
        sector(tester, ToolAdjustment.opacity),
      );
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(-10, -10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byKey(_wheel));
      expect(after.topLeft, before.topLeft - const Offset(40, 40));
      expect(observer.toolsChanged, events);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Observer extends BlocObserver {
  DocumentBloc? document;
  int toolsChanged = 0;

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    if (bloc is DocumentBloc) document = bloc;
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    if (event is ToolsChanged) toolsChanged++;
  }
}
