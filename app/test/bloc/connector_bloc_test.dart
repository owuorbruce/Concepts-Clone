import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:material_leap/material_leap.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

class _Context extends Mock implements EventContext {}

ShapeElement _shape(String id, double x, double y, {String collection = ''}) =>
    ShapeElement(
      id: id,
      collection: collection,
      firstPosition: Point(x, y),
      secondPosition: Point(x + 100, y + 100),
      property: const ShapeProperty(shape: RectangleShape(), strokeWidth: 0),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorController editorController;
  late WindowCubit windowCubit;
  late DocumentBloc bloc;
  late String otherPageName;

  final a = _shape('a', 0, 0, collection: 'group');
  final b = _shape('b', 300, 0);
  final connector = createConnector(a, b, id: 'c')!;
  final initialPage = DocumentPage(
    layers: [
      DocumentLayer(id: 'layer-a', content: [a]),
      DocumentLayer(id: 'layer-b', content: [b]),
      DocumentLayer(id: 'layer-c', content: [connector]),
    ],
  );

  setUpAll(() {
    registerFallbackValue(const AssetLocation(path: 'fallback.bfly'));
  });

  setUp(() async {
    final fileSystem = MockButterflyFileSystem();
    final settingsCubit = fileSystem.settingsCubit as MockSettingsCubit;
    when(() => settingsCubit.state)
        .thenReturn(const ButterflySettings(autosave: false));
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => settingsCubit.addRecentHistory(any())).thenAnswer((_) async {});
    editorController = EditorController(
      settingsCubit,
      TransformCubit(1),
      CameraViewport.unbaked(),
    );
    windowCubit = WindowCubit(fullScreen: false);
    var (data, pageName) = NoteData(Archive()).setPage(initialPage, 'Page');
    (data, otherPageName) = data.setPage(
      const DocumentPage(layers: [DocumentLayer(id: 'other-layer')]),
      'Other',
    );
    bloc = DocumentBloc(
      fileSystem,
      editorController,
      windowCubit,
      data,
      const AssetLocation(path: 'connector.bfly'),
      null,
      initialPage,
      pageName,
    );
    await pumpEventQueue();
  });

  tearDown(() async {
    if (!bloc.isClosed) await bloc.close();
    if (!editorController.isClosed) await editorController.close();
    if (!windowCubit.isClosed) await windowCubit.close();
  });

  DocumentLoadSuccess current() => bloc.state as DocumentLoadSuccess;
  List<PadElement> content() => current().page.content;
  PadElement? element(String id) =>
      content().where((e) => e.id == id).singleOrNull;

  /// Waits until the bloc state satisfies [predicate] instead of sleeping.
  Future<void> until(bool Function() predicate) async {
    if (bloc.state is DocumentLoadSuccess && predicate()) return;
    await bloc.stream
        .where((s) => s is DocumentLoadSuccess && predicate())
        .first
        .timeout(const Duration(seconds: 5));
  }

  Future<void> dispatch(DocumentEvent event, bool Function() done) async {
    final result = until(done);
    bloc.add(event);
    await result;
  }

  Future<void> undo(bool Function() done) async {
    final result = until(done);
    bloc.undo();
    await result;
  }

  Future<void> redo(bool Function() done) async {
    final result = until(done);
    bloc.redo();
    await result;
  }

  bool isInitial() => current().page == initialPage;

  test('moving a shape re-routes the connector in one undo step', () async {
    final moved = b.copyWith(
      firstPosition: const Point(300, 300),
      secondPosition: const Point(400, 400),
    );
    final (_, end) = connectorEndpoints(a, moved)!;
    bool isMoved() =>
        element('b') == moved &&
        (element('c') as ShapeElement?)?.secondPosition == end;
    await dispatch(
      ElementsChanged({
        'b': [moved],
      }),
      isMoved,
    );
    await undo(isInitial);
    await redo(isMoved);
  });

  test('converting an endpoint into a line removes the connector', () async {
    final line = a.copyWith(
      property: a.property.copyWith(shape: const LineShape()),
    );
    bool isConverted() => element('a') == line && element('c') == null;
    await dispatch(
      ElementsChanged({
        'a': [line],
      }),
      isConverted,
    );
    expect(element('b'), b);
    await undo(isInitial);
    await redo(isConverted);
  });

  test('deleting a shape removes its connector in another layer', () async {
    bool isRemoved() =>
        element('a') == null && element('c') == null && element('b') == b;
    await dispatch(const ElementsRemoved(['a']), isRemoved);
    await undo(isInitial);
    await redo(isRemoved);
  });

  test('deleting only the connector keeps the shapes', () async {
    await dispatch(
      const ElementsRemoved(['c']),
      () => element('c') == null && element('a') == a && element('b') == b,
    );
    await undo(isInitial);
  });

  test('removing an endpoint layer removes dependent connectors', () async {
    bool isRemoved() =>
        !current().page.layers.any((l) => l.id == 'layer-a') &&
        element('c') == null &&
        element('b') == b;
    await dispatch(const LayerRemoved('layer-a'), isRemoved);
    await undo(isInitial);
    await redo(isRemoved);
  });

  test(
    'removing an endpoint collection removes dependent connectors',
    () async {
      bool isRemoved() =>
          element('a') == null && element('c') == null && element('b') == b;
      await dispatch(const CollectionElementsRemoved('group'), isRemoved);
      await undo(isInitial);
      await redo(isRemoved);
    },
  );

  test('duplicating all connected layers remaps the clones', () async {
    bool isDuplicated() => current().page.layers.length == 6;
    await dispatch(
      const LayersMerged(['layer-a', 'layer-b', 'layer-c'], true),
      isDuplicated,
    );
    final index = ConnectorIndex(content());
    expect(index.ambiguousIds, isEmpty);
    final connectors = content().where((e) => e.isConnector).toList();
    expect(connectors, hasLength(2));
    final clone = connectors.singleWhere((e) => e.id != 'c');
    expect(index.isValid(clone), isTrue);
    expect(clone.connector!.from, isNot('a'));
    expect(clone.connector!.to, isNot('b'));
    expect(element('c'), connector);
    await undo(isInitial);
    await redo(isDuplicated);
  });

  test('duplicating only the connector layer detaches the clone', () async {
    await dispatch(
      const LayersMerged(['layer-c'], true),
      () => current().page.layers.length == 4,
    );
    final lines = content()
        .whereType<ShapeElement>()
        .where((e) => e.property.shape is LineShape)
        .toList();
    expect(lines, hasLength(2));
    expect(lines.where((e) => e.isConnector).single.id, 'c');
    final clone = lines.singleWhere((e) => e.id != 'c');
    expect(clone.extra.containsKey(kConnectorExtraKey), isFalse);
  });

  test(
    'a connector copied without both endpoints is created detached',
    () async {
      final copy = regenerateElementIds([a, connector], createUniqueId);
      await dispatch(
        ElementsCreated(copy, layer: 'layer-c'),
        () => content().length == 5,
      );
      final created = element(copy[1].id!)!;
      expect(created.isConnector, isFalse);
      expect(element('c'), connector);
    },
  );

  test('connectors to ambiguous ids are created detached', () async {
    final duplicate = _shape('a', 0, 600);
    final extra = connector.copyWith(id: 'c2');
    await dispatch(
      ElementsCreated([duplicate, extra], layer: 'layer-c'),
      () => content().length == 5,
    );
    expect(element('c2')!.isConnector, isFalse);
  });

  group('stamping a connected component', () {
    Future<List<PadElement>> stamp(Rect target) async {
      final handler = StampHandler(
        StampTool(
          component: NamedItem(
            name: 'Pair',
            item: ButterflyComponent(elements: [a, b, connector]),
          ),
        ),
      );
      final context = _Context();
      when(() => context.getState()).thenReturn(current());
      when(() => context.getEditorController()).thenReturn(editorController);
      await handler.preparePaste(context);
      return handler.transformElements(target, '', editorController);
    }

    void expectStamped(List<PadElement> page, List<PadElement> stamped) {
      final index = ConnectorIndex(page);
      expect(index.ambiguousIds, isEmpty);
      final stampedConnector = stamped.singleWhere((e) => e.isConnector);
      expect(index.isValid(stampedConnector), isTrue);
      final ids = stamped.map((e) => e.id).toSet();
      expect(ids, containsAll(stampedConnector.connector!.toJson().values));
      expect(ids.intersection({'a', 'b', 'c'}), isEmpty);
    }

    test('onto the original page', () async {
      final stamped = await stamp(const Rect.fromLTWH(0, 500, 400, 100));
      await dispatch(
        ElementsCreated(stamped, layer: 'layer-c'),
        () => content().length == 6,
      );
      expectStamped(content(), stamped);
      expect(element('c'), connector);
      await undo(isInitial);
    });

    test('onto a different page', () async {
      final stamped = await stamp(const Rect.fromLTWH(0, 0, 400, 100));
      List<PadElement> other() =>
          current().data.getPage(otherPageName)?.content ?? const [];
      await dispatch(
        ElementsCreated(stamped, pageName: otherPageName, layer: 'other-layer'),
        () => other().length == 3,
      );
      expectStamped(other(), stamped);
      expect(current().page, initialPage);
    });
  });

  test('connected shapes survive saving and reopening', () async {
    final moved = a.copyWith(
      firstPosition: const Point(0, 200),
      secondPosition: const Point(100, 300),
    );
    await dispatch(
      ElementsChanged({
        'a': [moved],
      }),
      () => element('a') == moved,
    );
    final state = current();
    final saved = state.data.setPage(state.page, state.pageName).$1;
    final reopened = NoteData.fromData(saved.exportAsBytes());
    final page = reopened.getPage(state.pageName)!;
    expect(page, state.page);
    final reopenedConnector = page.content.singleWhere((e) => e.isConnector);
    expect(ConnectorIndex(page.content).isValid(reopenedConnector), isTrue);
    expect(reopenedConnector, element('c'));
  });
}
