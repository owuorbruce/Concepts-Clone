import 'dart:convert';

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
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly/views/amaze/shell.dart';
import 'package:butterfly/views/amaze/tool_slots.dart';
import 'package:butterfly/views/amaze/wheel_slots_store.dart';
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

const _library = ValueKey('amaze-brush-library');
const _amaze = ButterflySettings(
  defaultTemplate: 'default',
  flags: [kAmazeShellFlag],
);

/// The default document: lasso, pen, eraser, undo, redo, hand.
NoteData _documentA() => DocumentDefaults.createDocument(name: 'A');

/// A document with other slots, undo and redo between them, and three tools
/// after the eight slots.
NoteData _documentB() {
  final tools = <Tool>[
    UndoTool(id: createUniqueId()),
    LaserTool(id: createUniqueId()),
    RedoTool(id: createUniqueId()),
    LabelTool(id: createUniqueId()),
    PolygonTool(id: createUniqueId()),
    StampTool(id: createUniqueId()),
    AreaTool(id: createUniqueId()),
    PresentationTool(id: createUniqueId()),
    SpacerTool(id: createUniqueId()),
    HandTool(id: createUniqueId()),
    PenTool(id: createUniqueId()),
    // Beyond the eight slots.
    EraserTool(id: createUniqueId()),
    TextureTool(id: createUniqueId()),
  ];
  return DocumentDefaults.createDocument(name: 'B')
      .setInfo(DocumentInfo(tools: tools));
}

String _json(Object? value) => jsonEncode(value);

List<String> _jsonTools(Iterable<Tool> tools) => [
  for (final tool in tools) _json(tool.toJson()),
];

void main() {
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

  group('store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round trip keeps tools, settings, ids and empty slots', () async {
      final slots = <Tool?>[
        PenTool(
          id: 'pen-1',
          property: const PenProperty(strokeWidth: 34, smoothing: 0.3),
        ),
        null,
        EraserTool(id: 'eraser-1', strokeWidth: 12),
        null,
        HandTool(id: 'hand-1'),
        null,
        null,
        LabelTool(id: 'label-1'),
      ];
      await saveWheelSlots(slots);
      final loaded = await loadWheelSlots();
      expect(loaded, hasLength(kToolSlotCount));
      expect(sameSlotTools(loaded!, slots), isTrue);
      expect(loaded[1], isNull);
      expect((loaded[0] as PenTool).property.strokeWidth, 34);
      expect(loaded[7]!.id, 'label-1');
    });

    test('bad or partial data is ignored', () async {
      final seven = encodeWheelSlots(List.filled(kToolSlotCount, null));
      for (final saved in <Object>[
        'not json',
        '{"a": 1}',
        '[null, null]',
        seven.replaceFirst('null,', ''),
        '[${List.filled(kToolSlotCount, '{"type": "unknown"}').join(',')}]',
        '[${List.filled(kToolSlotCount, '{"type": "undo"}').join(',')}]',
        '[${List.filled(kToolSlotCount, '3').join(',')}]',
        42,
      ]) {
        SharedPreferences.setMockInitialValues({kWheelSlotsKey: saved});
        expect(await loadWheelSlots(), isNull, reason: '$saved');
      }
    });

    test('applying slots keeps undo, redo and later tools in place', () {
      final b = _documentB().getInfo()!.tools;
      final store = <Tool?>[
        PenTool(id: 'p'),
        HandTool(id: 'h'),
        null,
        EraserTool(id: 'e'),
        null,
        null,
        null,
        null,
      ];
      final applied = applySlotTools(b, store);
      final tools = applied.tools;
      expect(tools[0], same(b[0]));
      expect(tools[2], same(b[2]));
      expect(tools.map((tool) => tool.id).take(6), [
        b[0].id,
        'p',
        b[2].id,
        'h',
        'e',
        b[10].id,
      ]);
      expect(tools.last, same(b.last));
      expect(applied.slots.whereType<Tool>().map((tool) => tool.id), [
        'p',
        'h',
        'e',
      ]);
    });

    test('a slot id used by a kept tool gets a new id', () {
      final tools = [UndoTool(id: 'u'), RedoTool(id: 'r'), PenTool(id: 'p')];
      final applied = applySlotTools(tools, [
        HandTool(id: 'u'),
        PenTool(id: 'p'),
        PenTool(id: 'p'),
        ...List.filled(kToolSlotCount - 3, null),
      ]);
      final ids = applied.tools.map((tool) => tool.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.take(3), ['u', 'r', isNot('u')]);
      expect(ids[3], 'p');
    });
  });

  group('shared wheel', () {
    late MockSettingsCubit settingsCubit;
    late MockButterflyFileSystem fileSystem;
    late WindowCubit windowCubit;
    late _DocumentObserver observer;
    late BlocObserver previousObserver;
    final routers = <GoRouter>[];

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
      when(() => settingsCubit.addRecentHistory(any()))
          .thenAnswer((_) async {});
      when(() => settingsCubit.changeLocaleTemporarily(any()))
          .thenAnswer((_) async {});
    });

    tearDown(() async {
      Bloc.observer = previousObserver;
      for (final router in routers) {
        router.dispose();
      }
      routers.clear();
      await windowCubit.close();
    });

    void setScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 800);
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

    Widget buildApp(NoteData document, Embedding? embedding) {
      fileSystem.buildTemplateSystem().updateFile('default', document);
      final router = GoRouter(
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
                  embedding: embedding,
                  location: AssetLocation.local(
                    state.pathParameters['path'] ?? '',
                  ),
                ),
              ),
            ],
          ),
        ],
      );
      routers.add(router);
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

    DocumentBloc bloc() => observer.lastDocumentBloc!;

    List<Tool> documentTools() {
      return (bloc().state as DocumentLoadSuccess).info.tools;
    }

    Tool? slotTool(int slot) => slotTools(documentTools())[slot];

    Finder slotButton(int slot) => find.byKey(ValueKey(('amaze-slot', slot)));

    Future<String?> storedSlots() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(kWheelSlotsKey);
    }

    /// Opens [document] in a fresh app, closing the previous one, and waits
    /// for the wheel sync on open.
    Future<EditorController> open(
      WidgetTester tester,
      NoteData document, {
      Embedding? embedding,
    }) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      observer.reset();
      await tester.pumpWidget(buildApp(document, embedding));
      await tester.tap(find.byKey(const ValueKey('open-document')));
      await pumpUntil(
        tester,
        () => observer.lastDocumentBloc?.state is DocumentLoadSuccess,
        'document open',
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      return bloc().editorController;
    }

    /// Lets the throttled store save run.
    Future<void> settleSave(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }

    /// The document saved and opened again, as the next session reads it.
    NoteData reopened(NoteData original) {
      final info = (bloc().state as DocumentLoadSuccess).info;
      final json = jsonDecode(jsonEncode(info.toJson()));
      return original.setInfo(
        DocumentInfo.fromJson(json as Map<String, dynamic>),
      );
    }

    testWidgets('without a store, opening seeds it and changes nothing', (
      tester,
    ) async {
      setScreen(tester);
      final a = _documentA();
      final before = _jsonTools(a.getInfo()!.tools);
      await open(tester, a);

      expect(observer.toolsReplaced, 0);
      expect(_jsonTools(documentTools()), before);
      final stored = parseWheelSlots(await storedSlots());
      expect(sameSlotTools(stored!, slotTools(documentTools())), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('a matching document gets no ToolsReplaced', (tester) async {
      setScreen(tester);
      final a = _documentA();
      await open(tester, a);
      final stored = await storedSlots();
      await open(tester, a);

      expect(observer.toolsReplaced, 0);
      expect(await storedSlots(), stored);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('corrupt or short stores are reseeded from the document', (
      tester,
    ) async {
      setScreen(tester);
      for (final saved in ['{broken', '[null, null, null]']) {
        SharedPreferences.setMockInitialValues({kWheelSlotsKey: saved});
        final a = _documentA();
        final before = _jsonTools(a.getInfo()!.tools);
        await open(tester, a);

        expect(observer.toolsReplaced, 0, reason: saved);
        expect(_jsonTools(documentTools()), before);
        final stored = parseWheelSlots(await storedSlots());
        expect(sameSlotTools(stored!, slotTools(documentTools())), isTrue);
      }
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('a slot change in A appears in B', (tester) async {
      setScreen(tester);
      await open(tester, _documentA());
      await tester.longPress(slotButton(3));
      await tester.pumpAndSettle();
      expect(find.byKey(_library), findsOneWidget);
      final fixedWidth = find.byKey(
        ValueKey(('amaze-library-item', LibraryEntry.fixedWidth.name)),
      );
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('amaze-library-scroll')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        fixedWidth,
        200,
        scrollable: scrollable.first,
      );
      await tester.pumpAndSettle();
      await tester.tap(fixedWidth);
      await pumpUntil(
        tester,
        () => libraryEntryOf(slotTool(3)!) == LibraryEntry.fixedWidth,
        'fixed width',
      );
      final aSlots = slotTools(documentTools());
      await settleSave(tester);
      expect(
        sameSlotTools(parseWheelSlots(await storedSlots())!, aSlots),
        isTrue,
      );

      final b = _documentB();
      final bTools = b.getInfo()!.tools;
      await open(tester, b);

      expect(observer.toolsReplaced, 1);
      expect(libraryEntryOf(slotTool(3)!), LibraryEntry.fixedWidth);
      final tools = documentTools();
      expect(
        _jsonTools(slotTools(tools).whereType<Tool>().take(4)),
        _jsonTools(aSlots.whereType<Tool>()),
      );
      // Undo and redo stay where they were.
      expect(_json(tools[0].toJson()), _json(bTools[0].toJson()));
      expect(_json(tools[2].toJson()), _json(bTools[2].toJson()));
      expect(tools[0], isA<UndoTool>());
      expect(tools[2], isA<RedoTool>());
      // The tools after B's eight slots are kept, in order, after the slots.
      expect(
        _jsonTools(tools.skip(tools.length - 3)),
        _jsonTools(bTools.skip(bTools.length - 3)),
      );
      expect(tools, hasLength(2 + 4 + 3));
      // The sync is not an undo step.
      expect(bloc().canUndo, isFalse);
      expect(
        tester.widget<IconButton>(find.byKey(const ValueKey('amaze-undo'))),
        isA<IconButton>().having((b) => b.onPressed, 'onPressed', isNull),
      );
      // B's extra tools do not leak into the shared wheel.
      await settleSave(tester);
      expect(
        sameSlotTools(parseWheelSlots(await storedSlots())!, aSlots),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('size changes in A carry over to B', (tester) async {
      setScreen(tester);
      await open(tester, _documentA());
      final pen = slotTool(1)! as PenTool;
      bloc().add(ToolsChanged([pen.writeAdjustment(ToolAdjustment.size, 34)]));
      await pumpUntil(
        tester,
        () => (slotTool(1)! as PenTool).property.strokeWidth == 34,
        'pen size',
      );
      // The store is saved shortly after, without reopening.
      await settleSave(tester);
      final stored = parseWheelSlots(await storedSlots())!;
      expect((stored[1]! as PenTool).property.strokeWidth, 34);

      await open(tester, _documentB());
      final inB = slotTool(1)! as PenTool;
      expect(inB.property.strokeWidth, 34);
      expect(inB.id, pen.id);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('undo of a slot change updates the store', (tester) async {
      setScreen(tester);
      await open(tester, _documentA());
      final original = slotTools(documentTools());
      final pen = slotTool(1)! as PenTool;
      bloc().add(ToolsChanged([pen.writeAdjustment(ToolAdjustment.size, 34)]));
      await pumpUntil(
        tester,
        () => (slotTool(1)! as PenTool).property.strokeWidth == 34,
        'pen size',
      );
      await settleSave(tester);
      expect(
        (parseWheelSlots(await storedSlots())![1]! as PenTool)
            .property
            .strokeWidth,
        34,
      );

      bloc().undo();
      await pumpUntil(
        tester,
        () => (slotTool(1)! as PenTool).property.strokeWidth != 34,
        'undo',
      );
      await settleSave(tester);
      expect(
        sameSlotTools(parseWheelSlots(await storedSlots())!, original),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('remove, move earlier and replace update the store', (
      tester,
    ) async {
      setScreen(tester);
      await open(tester, _documentA());
      Future<void> menu(int slot, String item) async {
        await tester.longPress(slotButton(slot));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('amaze-library-slot-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(item)));
        await tester.pumpAndSettle();
      }

      final first = slotTool(0)!.id;
      final second = slotTool(1)!.id;
      await menu(1, 'amaze-slot-earlier');
      await pumpUntil(tester, () => slotTool(0)!.id == second, 'moved');
      expect(slotTool(1)!.id, first);

      final removed = slotTool(2)!.id;
      await menu(2, 'amaze-slot-remove');
      await pumpUntil(
        tester,
        () => documentTools().every((tool) => tool.id != removed),
        'removed',
      );
      expect(slotTool(3), isNull);

      final label = slotToolCatalog().indexWhere((tool) => tool is LabelTool);
      await menu(0, 'amaze-slot-replace');
      await tester.tap(find.byKey(ValueKey(('amaze-catalog', label))));
      await pumpUntil(tester, () => slotTool(0) is LabelTool, 'replaced');
      expect(slotTool(0)!.id, second);

      await settleSave(tester);
      final stored = parseWheelSlots(await storedSlots())!;
      expect(sameSlotTools(stored, slotTools(documentTools())), isTrue);
      expect(stored[3], isNull);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('slots keep their tools after reopening', (tester) async {
      setScreen(tester);
      final a = _documentA();
      await open(tester, a);
      bloc().add(
        ToolReordered(
          slotTool(0)!.id!,
          slotToolIndices(documentTools())[1] + 1,
        ),
      );
      await pumpUntil(tester, () => slotTool(0) is PenTool, 'reordered');
      final ids = [for (final tool in slotTools(documentTools())) tool?.id];
      await settleSave(tester);
      final saved = reopened(a);

      await open(tester, saved);
      expect(observer.toolsReplaced, 0);
      expect([for (final tool in slotTools(documentTools())) tool?.id], ids);
      // And in another drawing.
      await open(tester, _documentB());
      expect(
        [for (final tool in slotTools(documentTools())) tool?.id].take(4),
        ids.take(4),
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('a long press opens the library on release', (tester) async {
      setScreen(tester);
      await open(tester, _documentA());
      final gesture = await tester.startGesture(
        tester.getCenter(slotButton(1)),
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(find.byKey(_library), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(_library), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('the slot menu offers the tool settings', (tester) async {
      setScreen(tester);
      final editor = await open(tester, _documentA());
      await tester.longPress(slotButton(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('amaze-library-slot-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('amaze-slot-configure')));
      await tester.pumpAndSettle();
      expect(editor.toolCubit.state.selection?.selected.single, isA<PenTool>());
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 1));
    });

    for (final editable in [false, true]) {
      testWidgets('embedded documents (editable: $editable) are left alone', (
        tester,
      ) async {
        setScreen(tester);
        final other = encodeWheelSlots(
          slotTools(_documentB().getInfo()!.tools),
        );
        for (final saved in [null, other]) {
          SharedPreferences.setMockInitialValues({kWheelSlotsKey: ?saved});
          final a = _documentA();
          final before = _jsonTools(a.getInfo()!.tools);
          await open(
            tester,
            a,
            embedding: Embedding(editable: editable, internal: true),
          );

          expect(observer.toolsReplaced, 0);
          expect(_jsonTools(documentTools()), before);
          if (editable) {
            final pen = slotTool(1)! as PenTool;
            bloc().add(
              ToolsChanged([pen.writeAdjustment(ToolAdjustment.size, 34)]),
            );
            await pumpUntil(
              tester,
              () => (slotTool(1)! as PenTool).property.strokeWidth == 34,
              'pen size',
            );
            await settleSave(tester);
          }
          expect(await storedSlots(), saved);
        }
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(minutes: 1));
      });
    }
  });
}

class _DocumentObserver extends BlocObserver {
  DocumentBloc? lastDocumentBloc;

  /// How many [ToolsReplaced] events the documents received.
  int toolsReplaced = 0;

  void reset() {
    lastDocumentBloc = null;
    toolsReplaced = 0;
  }

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    if (bloc is DocumentBloc) lastDocumentBloc = bloc;
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    if (event is ToolsReplaced) toolsReplaced++;
  }
}
