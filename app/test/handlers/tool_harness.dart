import 'package:archive/archive.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

class ToolEventContext extends Mock implements EventContext {}

/// A real document bloc and editor controller with a stubbed event
/// context, to drive tool handlers in tests.
class ToolHarness {
  ToolHarness({
    this.settings = const ButterflySettings(
      autosave: false,
      snapHaptics: false,
    ),
  });

  final ButterflySettings settings;
  late final MockButterflyFileSystem fileSystem;
  late final MockSettingsCubit settingsCubit;
  late final EditorController controller;
  late final WindowCubit windowCubit;
  late final DocumentBloc bloc;
  final context = ToolEventContext();

  /// Elements added through [ElementsCreated], in order.
  final created = <List<PadElement>>[];

  /// Number of [ElementsCreated] events, one per undo step.
  int get createEvents => created.length;

  /// [ElementsChanged] events, one per undo step.
  final changed = <Map<String, List<PadElement>>>[];
  BlocObserver? _previousObserver;

  Future<void> setUp({
    List<PadElement> content = const [],
    List<Background> backgrounds = const [],
    List<DocumentLayer> extraLayers = const [],
    Set<String>? invisibleLayers,
  }) async {
    registerFallbackValue(const AssetLocation(path: 'fallback.bfly'));
    fileSystem = MockButterflyFileSystem();
    settingsCubit = fileSystem.settingsCubit as MockSettingsCubit;
    when(() => settingsCubit.state).thenReturn(settings);
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => settingsCubit.addRecentHistory(any())).thenAnswer((_) async {});
    controller = EditorController(
      settingsCubit,
      TransformCubit(1),
      CameraViewport.unbaked(),
    );
    windowCubit = WindowCubit(fullScreen: false);
    var data = NoteData(Archive());
    final page = DocumentPage(
      layers: [
        DocumentLayer(id: 'layer', content: content),
        ...extraLayers,
      ],
      backgrounds: backgrounds,
    );
    final (pageData, pageName) = data.setPage(page, 'Page 1');
    data = pageData;
    _previousObserver = Bloc.observer;
    Bloc.observer = _Recorder(created, changed, _previousObserver!);
    bloc = DocumentBloc(
      fileSystem,
      controller,
      windowCubit,
      data,
      const AssetLocation(path: 'tools.bfly'),
      null,
      page,
      pageName,
      false,
      'layer',
      null,
      invisibleLayers,
    );
    await settle();
    final state = bloc.state;
    if (state is DocumentLoadSuccess) {
      await controller.rendererCubit.loadElements(controller, state);
    }
    _stub();
  }

  void _stub() {
    when(() => context.getCameraTransform())
        .thenAnswer((_) => controller.transformCubit.state);
    when(() => context.getTransformCubit())
        .thenReturn(controller.transformCubit);
    when(() => context.getDocumentBloc()).thenReturn(bloc);
    when(() => context.getEditorController()).thenReturn(controller);
    when(() => context.getViewState()).thenReturn(const EditorViewState());
    when(() => context.getToolState())
        .thenAnswer((_) => controller.toolCubit.state);
    when(() => context.getInputState())
        .thenAnswer((_) => controller.inputCubit.state);
    when(() => context.getRendererState())
        .thenAnswer((_) => controller.rendererCubit.state);
    when(() => context.getSettings()).thenReturn(settings);
    when(() => context.getSettingsCubit()).thenReturn(settingsCubit);
    when(() => context.getState()).thenAnswer((_) {
      final state = bloc.state;
      return state is DocumentLoadSuccess ? state : null;
    });
    when(() => context.getPage()).thenAnswer((_) {
      final state = bloc.state;
      return state is DocumentLoadSuccess ? state.page : null;
    });
    when(() => context.getInfo()).thenAnswer((_) {
      final state = bloc.state;
      return state is DocumentLoadSuccess ? state.info : null;
    });
    when(() => context.getData()).thenAnswer((_) {
      final state = bloc.state;
      return state is DocumentLoadSuccess ? state.data : null;
    });
    when(() => context.viewportSize).thenReturn(const Size(800, 600));
    when(() => context.isShiftPressed).thenReturn(false);
    when(() => context.isAltPressed).thenReturn(false);
    when(() => context.isCtrlPressed).thenReturn(false);
    when(() => context.refresh()).thenAnswer((_) async {});
    when(() => context.refreshForegrounds()).thenAnswer((_) async {});
    when(() => context.delayedBake()).thenAnswer((_) async {});
    when(() => context.bake()).thenAnswer((_) async {});
  }

  /// Gives the context a real [BuildContext] with the bloc, for handlers
  /// that switch tools or open dialogs.
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext buildContext;
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<DocumentBloc>.value(value: bloc),
            BlocProvider<SettingsCubit>.value(value: settingsCubit),
            BlocProvider<TransformCubit>.value(
              value: controller.transformCubit,
            ),
          ],
          child: RepositoryProvider<EditorController>.value(
            value: controller,
            child: Focus(
              autofocus: true,
              child: Builder(
                builder: (context) {
                  buildContext = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );
    when(() => context.buildContext).thenReturn(buildContext);
    when(() => context.getFileSystem()).thenReturn(fileSystem);
    when(() => context.devicePixelRatio).thenReturn(1);
    return buildContext;
  }

  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  /// Bakes the page as the canvas would at 800 × 600.
  Future<void> bake() => controller.rendererCubit.bake(
    controller,
    state,
    viewportSize: const Size(800, 600),
    pixelRatio: 1,
  );

  DocumentLoadSuccess get state => bloc.state as DocumentLoadSuccess;

  List<PadElement> get content => [
    for (final layer in state.page.layers) ...layer.content,
  ];

  /// One drag with one pointer from [from] through [path] in screen pixels.
  Future<void> drag(
    Handler handler,
    Offset from,
    List<Offset> path, {
    int pointer = 1,
    Future<void> Function()? beforeEnd,
  }) async {
    handler.onPointerDown(
      PointerDownEvent(pointer: pointer, position: from),
      context,
    );
    handler.onScaleStart(ScaleStartDetails(localFocalPoint: from), context);
    var last = from;
    for (final point in path) {
      handler.onPointerMove(
        PointerMoveEvent(
          pointer: pointer,
          position: point,
          delta: point - last,
        ),
        context,
      );
      handler.onScaleUpdate(
        ScaleUpdateDetails(localFocalPoint: point, pointerCount: 1),
        context,
      );
      last = point;
    }
    await beforeEnd?.call();
    handler.onPointerUp(
      PointerUpEvent(pointer: pointer, position: last),
      context,
    );
    handler.onScaleEnd(ScaleEndDetails(), context);
    await settle();
  }

  Future<void> dispose() async {
    if (_previousObserver case final previous?) Bloc.observer = previous;
    if (!bloc.isClosed) await bloc.close();
    if (!controller.isClosed) await controller.close();
    if (!windowCubit.isClosed) await windowCubit.close();
  }
}

class _Recorder extends BlocObserver {
  _Recorder(this._created, this._changed, this._previous);

  final List<List<PadElement>> _created;
  final List<Map<String, List<PadElement>>> _changed;
  final BlocObserver _previous;

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    _previous.onEvent(bloc, event);
    if (event is ElementsCreated) _created.add(event.elements);
    if (event is ElementsChanged) _changed.add(event.elements);
  }
}
