import 'dart:math';

import 'package:archive/archive.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:material_leap/material_leap.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

ShapeElement _rect(String id, double x, double y) => ShapeElement(
  id: id,
  firstPosition: Point(x, y),
  secondPosition: Point(x + 100, y + 100),
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorController editorController;
  late WindowCubit windowCubit;
  late DocumentBloc bloc;

  final a = _rect('a', 0, 0);
  final b = _rect('b', 300, 0);
  final connector = createConnector(a, b, id: 'c')!;

  setUpAll(() {
    registerFallbackValue(const AssetLocation(path: 'fallback.bfly'));
  });

  setUp(() {
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
    final page = DocumentPage(
      layers: [
        DocumentLayer(id: 'layer', content: [a, b, connector]),
      ],
    );
    final (data, pageName) = NoteData(Archive()).setPage(page, 'Page');
    bloc = DocumentBloc(
      fileSystem,
      editorController,
      windowCubit,
      data,
      const AssetLocation(path: 'connector.bfly'),
      null,
      page,
      pageName,
    );
  });

  tearDown(() async {
    if (!bloc.isClosed) await bloc.close();
    if (!editorController.isClosed) await editorController.close();
    if (!windowCubit.isClosed) await windowCubit.close();
  });

  ShapeElement? element(String id) =>
      (bloc.state as DocumentLoadSuccess).page.content.firstWhereOrNull(
        (e) => e.id == id,
      ) as ShapeElement?;

  test('moving a shape re-routes the connector in one undo step', () async {
    await _settle();
    final moved = b.copyWith(
      firstPosition: const Point(300, 300),
      secondPosition: const Point(400, 400),
    );
    bloc.add(
      ElementsChanged({
        'b': [moved],
      }),
    );
    await _settle();
    final (start, end) = connectorEndpoints(a, moved);
    expect(element('c')!.firstPosition, start);
    expect(element('c')!.secondPosition, end);

    bloc.undo();
    await _settle();
    expect(element('b'), b);
    expect(element('c'), connector);

    bloc.redo();
    await _settle();
    expect(element('b'), moved);
    expect(element('c')!.secondPosition, end);
  });

  test(
    'deleting a shape removes its connector and undo restores both',
    () async {
      await _settle();
      bloc.add(const ElementsRemoved(['a']));
      await _settle();
      expect(element('a'), isNull);
      expect(element('c'), isNull);
      expect(element('b'), b);

      bloc.undo();
      await _settle();
      expect(element('a'), a);
      expect(element('c'), connector);
    },
  );

  test('deleting only the connector keeps the shapes', () async {
    await _settle();
    bloc.add(const ElementsRemoved(['c']));
    await _settle();
    expect(element('c'), isNull);
    expect(element('a'), a);
    expect(element('b'), b);
  });
}

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
