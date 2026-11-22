import 'dart:math';

import 'package:archive/archive.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/views/amaze/floor_plan/floor_plan.dart';
import 'package:butterfly/views/amaze/objects/object_placement.dart';
import 'package:butterfly/views/amaze/objects/object_store.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:butterfly_api/butterfly_text.dart' as text;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

class _Context extends Mock implements EventContext {}

class _Observer extends BlocObserver {
  final events = <Object?>[];

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.add(event);
  }

  int count<T>() => events.whereType<T>().length;
}

const _inch = kCanvasUnitsPerInch;
const _color = kDefaultWallColor;

/// The 10' × 8' box: wall centerlines 120" × 96" from (0, 0).
List<PenElement> _box() {
  const w = 120 * _inch, h = 96 * _inch;
  const corners = [Point(0.0, 0.0), Point(w, 0.0), Point(w, h), Point(0.0, h)];
  return [
    for (var i = 0; i < 4; i++)
      makeWall(
        corners[i],
        corners[(i + 1) % 4],
        4.5,
        _color,
      ).copyWith(id: 'wall-$i'),
  ];
}

const _interiorSquareFeet = (120 - 4.5) * (96 - 4.5) / 144;

void main() {
  late MockButterflyFileSystem fileSystem;
  late MockSettingsCubit settingsCubit;
  late EditorController controller;
  late WindowCubit windowCubit;
  late DocumentBloc bloc;
  late _Observer observer;
  late BlocObserver previousObserver;
  late _Context context;

  setUpAll(() {
    registerFallbackValue(const AssetLocation(path: 'fallback.bfly'));
  });

  setUp(() {
    fileSystem = MockButterflyFileSystem();
    settingsCubit = fileSystem.settingsCubit as MockSettingsCubit;
    when(() => settingsCubit.state)
        .thenReturn(const ButterflySettings(autosave: false));
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => settingsCubit.addRecentHistory(any())).thenAnswer((_) async {});
    controller = EditorController(
      settingsCubit,
      TransformCubit(1),
      CameraViewport.unbaked(),
    );
    windowCubit = WindowCubit(fullScreen: false);
    const page = DocumentPage(layers: [DocumentLayer(id: 'layer')]);
    final (data, name) = NoteData(Archive()).setPage(page, 'Page 1');
    bloc = DocumentBloc(
      fileSystem,
      controller,
      windowCubit,
      data,
      const AssetLocation(path: 'walls.bfly'),
      null,
      page,
      name,
    );
    observer = _Observer();
    previousObserver = Bloc.observer;
    Bloc.observer = observer;
    disarmOpening();
  });

  tearDown(() async {
    Bloc.observer = previousObserver;
    disarmOpening();
    if (!bloc.isClosed) await bloc.close();
    if (!controller.isClosed) await controller.close();
    if (!windowCubit.isClosed) await windowCubit.close();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }

  /// A mocked event context on the real bloc, with a build context that
  /// has the app's localizations.
  Future<void> setUpContext(WidgetTester tester) async {
    late BuildContext buildContext;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              buildContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await settle(tester);
    context = _Context();
    when(() => context.buildContext).thenReturn(buildContext);
    when(() => context.getDocumentBloc()).thenReturn(bloc);
    when(() => context.getEditorController()).thenReturn(controller);
    when(() => context.getCameraTransform())
        .thenAnswer((_) => controller.transformCubit.state);
    when(() => context.getState())
        .thenAnswer((_) => bloc.state as DocumentLoadSuccess);
    when(() => context.refresh()).thenAnswer((_) async {});
    when(() => context.refreshForegrounds()).thenAnswer((_) async {});
  }

  List<PadElement> content() =>
      (bloc.state as DocumentLoadSuccess).page.content;

  List<PenElement> walls() => content()
      .whereType<PenElement>()
      .where((e) => e.extra[kWallExtraKey] is Map)
      .toList();

  List<PenElement> rooms() =>
      content().whereType<PenElement>().where(isRoomFill).toList();

  Future<void> drag(
    WidgetTester tester,
    WallHandler handler,
    Offset from,
    Offset to,
  ) async {
    handler.onScaleStart(ScaleStartDetails(localFocalPoint: from), context);
    handler.onScaleUpdate(
      ScaleUpdateDetails(localFocalPoint: to, pointerCount: 1),
      context,
    );
    handler.onScaleEnd(ScaleEndDetails(), context);
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, WallHandler handler, Offset at) async {
    await handler.onTapUp(
      TapUpDetails(kind: PointerDeviceKind.touch, localPosition: at),
      context,
    );
    await settle(tester);
  }

  Future<void> addBox(WidgetTester tester) async {
    bloc.add(ElementsCreated(_box()));
    await settle(tester);
    expect(walls(), hasLength(4));
  }

  group('drawing walls', () {
    testWidgets('a drag makes one valid wall', (tester) async {
      await setUpContext(tester);
      final handler = WallHandler(WallTool());
      await drag(
        tester,
        handler,
        const Offset(100, 100),
        const Offset(1060, 100),
      );
      expect(observer.count<ElementsCreated>(), 1);
      final geometry = readWall(walls().single)!;
      expect(geometry.a.x, closeTo(100, 1e-6));
      expect(geometry.b.x, closeTo(1060, 1e-6));
      expect(geometry.b.y, closeTo(100, 1e-6));
      expect(geometry.thicknessIn, closeTo(4.5, 1e-9));
    });

    testWidgets('the next wall starts on the last wall end', (tester) async {
      await setUpContext(tester);
      final handler = WallHandler(WallTool());
      await drag(
        tester,
        handler,
        const Offset(100, 100),
        const Offset(1060, 100),
      );
      // 7 px from the end, inside the 16 px snap distance.
      await drag(
        tester,
        handler,
        const Offset(1065, 105),
        const Offset(1065, 900),
      );
      final second = readWall(walls().last)!;
      expect(second.a.x, closeTo(1060, 1e-6));
      expect(second.a.y, closeTo(100, 1e-6));
    });

    testWidgets('the end snaps to 15° and whole inches', (tester) async {
      await setUpContext(tester);
      final handler = WallHandler(WallTool());
      const length = 1000.0;
      final angle = 7 * pi / 180;
      await drag(
        tester,
        handler,
        const Offset(0, 300),
        Offset(length * cos(angle), 300 + length * sin(angle)),
      );
      final geometry = readWall(walls().single)!;
      expect(geometry.b.y, closeTo(300, 1e-6));
      expect(geometry.length % _inch, closeTo(0, 1e-6));
    });

    testWidgets('a thicker tool draws a thicker wall', (tester) async {
      await setUpContext(tester);
      final handler = WallHandler(WallTool(thicknessIn: 6));
      await drag(tester, handler, const Offset(0, 0), const Offset(960, 0));
      expect(readWall(walls().single)!.thicknessIn, closeTo(6, 1e-9));
    });

    test('lengths show in feet and inches, areas in square feet', () {
      expect(formatFeetInches(150 * _inch), '12\' 6"');
      expect(formatFeetInches(7 * _inch), '7"');
      expect(formatSquareFeet(144 * _inch * _inch * 80), '80.0');
    });
  });

  group('rooms', () {
    testWidgets('a tap inside the box makes a room of the interior', (
      tester,
    ) async {
      await setUpContext(tester);
      await addBox(tester);
      final handler = WallHandler(WallTool());

      await tap(tester, handler, const Offset(60 * _inch, 48 * _inch));
      expect(observer.count<ElementsCreated>(), 2);
      final room = rooms().single;
      final area = polygonArea(roomPolygon(room)) / kCanvasUnitsPerSquareFoot;
      expect(area, closeTo(_interiorSquareFeet, 0.1));
      expect(roomNameOf(room), 'Room 1');
      expect(room.property.fillPaint.previewColor.a, (0.15 * 255).round());
      final label = content().whereType<TextElement>().single;
      expect(label.extra[kRoomLabelExtraKey], roomIdOf(room));
      final labelText =
          (label.area.paragraph.textSpans.single as text.TextSpan).text;
      expect(
        labelText,
        'Room 1\n${_interiorSquareFeet.toStringAsFixed(1)} sq ft',
      );
    });

    testWidgets('a tap outside or on a wall makes nothing', (tester) async {
      await setUpContext(tester);
      await addBox(tester);
      final handler = WallHandler(WallTool());
      await tap(tester, handler, const Offset(-50 * _inch, -50 * _inch));
      await tap(tester, handler, const Offset(60 * _inch, 0));
      expect(rooms(), isEmpty);
      expect(observer.count<ElementsCreated>(), 1);
    });
  });

  group('doors', () {
    Future<ObjectEntry> door(WidgetTester tester) async {
      final data = (await tester.runAsync(() async {
        final bytes = await rootBundle.load(
          'assets/object_packs/architecture.bfly',
        );
        return NoteData.fromData(Uint8List.sublistView(bytes));
      }))!;
      final item = data.getNamedComponents().firstWhere(
        (e) => e.name == 'Doors — Door 30″ left',
      );
      return ObjectEntry.fromComponent('architecture', 'Architecture', item);
    }

    double gap(List<PenElement> pieces) {
      final sorted = [...pieces]
        ..sort((a, b) => readWall(a)!.a.x.compareTo(readWall(b)!.a.x));
      final left = readWall(sorted.first)!, right = readWall(sorted.last)!;
      return right.outerStart.x - left.outerEnd.x;
    }

    testWidgets('a placed pack wall is a valid wall', (tester) async {
      final data = (await tester.runAsync(() async {
        final bytes = await rootBundle.load(
          'assets/object_packs/architecture.bfly',
        );
        return NoteData.fromData(Uint8List.sublistView(bytes));
      }))!;
      final item = data.getNamedComponents().firstWhere(
        (e) => e.name == 'Walls — Wall 6″ × 96″',
      );
      final placed = placeComponentAt(item.item, const Offset(1000, 2000));
      final wall = placed.single as PenElement;
      final geometry = readWall(wall)!;
      expect(geometry.thicknessIn, closeTo(6, 1e-9));
      // 96 in outside to outside: a centerline 6 in shorter.
      expect(geometry.length, closeTo(90 * _inch, 1e-6));
      expect(geometry.a.y, closeTo(2000, 1e-6));
      expect((geometry.a.x + geometry.b.x) / 2, closeTo(1000, 1e-6));
      expect(wall.extra['source'], isA<Map<Object?, Object?>>());
    });

    testWidgets('an armed door opens the tapped wall in one step', (
      tester,
    ) async {
      await setUpContext(tester);
      await addBox(tester);
      final entry = await door(tester);
      armOpening(entry);
      final handler = WallHandler(WallTool());
      final before = content().length;

      // Just inside the bottom wall of the box, at x = 60 in.
      await tap(tester, handler, const Offset(60 * _inch, 3 * _inch));
      expect(observer.count<ElementsChanged>(), 1);
      expect(armedOpening.value, isNull);
      expect(content().where((e) => e.id == 'wall-0'), isEmpty);
      final pieces = walls()
          .where(
            (e) =>
                readWall(e)!.a.y.abs() < 1e-6 && readWall(e)!.b.y.abs() < 1e-6,
          )
          .toList();
      expect(pieces, hasLength(2));
      expect(gap(pieces), closeTo(30 * _inch, 1e-6));
      final opening = content()
          .where((e) => e.extra[kOpeningExtraKey] is Map)
          .toList();
      expect(opening, isNotEmpty);
      final groups = opening
          .map((e) => (e.extra[kOpeningExtraKey] as Map)['groupId'])
          .toSet();
      expect(groups, hasLength(1));
      // The swing opens into the box, the side that was tapped.
      final swingPoints = opening.whereType<PenElement>().expand(
        (e) => e.points,
      );
      expect(swingPoints.every((p) => p.y > -3 * _inch), isTrue);
      expect(swingPoints.any((p) => p.y > 20 * _inch), isTrue);
      expect(content().length, before - 1 + 2 + opening.length);

      bloc.undo();
      await settle(tester);
      expect(content().where((e) => e.id == 'wall-0'), hasLength(1));
      expect(content().where((e) => e.extra[kOpeningExtraKey] is Map), isEmpty);
      expect(walls(), hasLength(4));
    });

    testWidgets('a tap away from walls keeps the door armed', (tester) async {
      await setUpContext(tester);
      await addBox(tester);
      final entry = await door(tester);
      armOpening(entry);
      final handler = WallHandler(WallTool());
      await tap(tester, handler, const Offset(60 * _inch, 48 * _inch));
      expect(observer.count<ElementsChanged>(), 0);
      expect(armedOpening.value, entry);
    });

    testWidgets('with a door in place a tap inside still finds the room', (
      tester,
    ) async {
      await setUpContext(tester);
      await addBox(tester);
      armOpening(await door(tester));
      final handler = WallHandler(WallTool());
      await tap(tester, handler, const Offset(60 * _inch, 3 * _inch));
      expect(armedOpening.value, isNull);
      await tap(tester, handler, const Offset(60 * _inch, 60 * _inch));
      final room = rooms().single;
      final area = polygonArea(roomPolygon(room)) / kCanvasUnitsPerSquareFoot;
      // The door leaf takes a little of the room.
      expect(area, lessThanOrEqualTo(_interiorSquareFeet + 0.1));
      expect(area, greaterThan(_interiorSquareFeet - 1));
    });
  });

  group('combine and subtract', () {
    List<Offset> square(double left, double top, double size) => [
      Offset(left, top),
      Offset(left + size, top),
      Offset(left + size, top + size),
      Offset(left, top + size),
    ];

    Future<(PenElement, PenElement)> addRooms(
      WidgetTester tester,
      List<Offset> a,
      List<Offset> b,
    ) async {
      bloc.add(
        ElementsCreated([
          ...makeRoom(polygon: a, color: _color, name: 'Room 1', areaText: ''),
          ...makeRoom(polygon: b, color: _color, name: 'Room 2', areaText: ''),
        ]),
      );
      await settle(tester);
      final fills = rooms();
      return (fills[0], fills[1]);
    }

    Future<void> merge(
      WidgetTester tester,
      PenElement first,
      PenElement second, {
      required bool subtract,
    }) async {
      final changes = mergeRoomChanges(
        content: content(),
        first: first,
        second: second,
        subtract: subtract,
        roomName: (n) => 'Room $n',
        areaText: (area) => '$area sq ft',
      )!;
      bloc.add(ElementsChanged(changes));
      await settle(tester);
    }

    testWidgets('combine makes one room of the union', (tester) async {
      await setUpContext(tester);
      final (a, b) = await addRooms(
        tester,
        square(0, 0, 1000),
        square(500, 500, 1000),
      );
      await merge(tester, a, b, subtract: false);
      expect(observer.count<ElementsChanged>(), 1);
      final room = rooms().single;
      expect(polygonArea(roomPolygon(room)), closeTo(1750000, 1500));
      expect(roomNameOf(room), 'Room 1');
      expect(content().whereType<TextElement>(), hasLength(1));

      bloc.undo();
      await settle(tester);
      expect(rooms(), hasLength(2));
      expect(content().whereType<TextElement>(), hasLength(2));
    });

    testWidgets('subtract leaves the first room minus the second', (
      tester,
    ) async {
      await setUpContext(tester);
      final (a, b) = await addRooms(
        tester,
        square(0, 0, 1000),
        square(500, 500, 1000),
      );
      await merge(tester, a, b, subtract: true);
      final room = rooms().single;
      expect(polygonArea(roomPolygon(room)), closeTo(750000, 1500));
      expect(roomNameOf(room), 'Room 1');
    });

    testWidgets('a result with a hole is refused', (tester) async {
      await setUpContext(tester);
      final (a, b) = await addRooms(
        tester,
        square(0, 0, 3000),
        square(1000, 1000, 1000),
      );
      expect(mergeRooms(a, b, subtract: true), isA<MergeWithHole>());
      expect(
        mergeRoomChanges(
          content: content(),
          first: a,
          second: b,
          subtract: true,
          roomName: (n) => 'Room $n',
          areaText: (area) => area,
        ),
        isNull,
      );
    });
  });

  test('11: a cut piece reads its cut end at the true cut position', () {
    // A 120" wall along x from its centerline start at 0.
    final wall = makeWall(
      const Point(0.0, 0.0),
      const Point(120 * kCanvasUnitsPerInch, 0.0),
      6,
      kDefaultWallColor,
    );
    final geometry = readWall(wall)!;
    // Cut 30" to 60" along the outline, which starts 3" before the start.
    final pieces = cutWall(wall, 30, 60);
    expect(pieces, hasLength(2));
    final first = readWall(pieces.first)!;
    final second = readWall(pieces.last)!;
    final outerStart = geometry.outerStart.x;
    // The first piece keeps its round start and ends flat at the cut.
    expect(first.a.x, closeTo(geometry.a.x, 0.01));
    expect(first.b.x, closeTo(outerStart + 30 * kCanvasUnitsPerInch, 0.01));
    expect(first.flatEnd, isTrue);
    expect(first.flatStart, isFalse);
    // The second starts flat at the cut and keeps the wall's end.
    expect(second.a.x, closeTo(outerStart + 60 * kCanvasUnitsPerInch, 0.01));
    expect(second.b.x, closeTo(geometry.b.x, 0.01));
    expect(second.flatStart, isTrue);
    // A new wall drawn from the cut end meets it exactly.
    expect(second.outerStart.x, closeTo(second.a.x, 0.01));
    // Walls saved before have no flat key and read as before.
    expect(wall.extra[kWallExtraKey], isNot(contains('flat')));
    expect(geometry.flatStart || geometry.flatEnd, isFalse);
  });
}
