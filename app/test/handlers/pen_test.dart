import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

class _Bloc extends Mock implements DocumentBloc {}

class _State extends Mock implements DocumentLoadSuccess {}

class _Controller extends Mock implements EditorController {}

class _Input extends Mock implements EditorInputCubit {}

class _Settings extends Mock implements SettingsCubit {}

class _Context extends Mock implements EventContext {}

void main() {
  setUpAll(() {
    registerFallbackValue(Offset.zero);
    registerFallbackValue(ElementsCreated(const []));
  });

  /// Draws a stroke from events of [kind] and returns its points.
  Future<List<PathPoint>> draw(
    WidgetTester tester,
    PointerDeviceKind kind,
  ) async {
    final handler = PenHandler(
      PenTool(property: const PenProperty(smoothing: 0.5)),
    );
    final transform = TransformCubit(1);
    addTearDown(transform.close);
    final toolCubit = ToolCubit(ToolRuntimeState(handler: handler));
    addTearDown(toolCubit.close);
    final bloc = _Bloc();
    final state = _State();
    final controller = _Controller();
    final input = _Input();
    final settings = _Settings();
    final created = <ElementsCreated>[];
    when(() => bloc.state).thenReturn(state);
    when(() => bloc.isInBounds(any())).thenReturn(true);
    when(() => bloc.add(any())).thenAnswer((call) {
      final event = call.positionalArguments.single;
      if (event is ElementsCreated) created.add(event);
    });
    when(() => bloc.refresh(allowBake: any(named: 'allowBake')))
        .thenAnswer((_) async {});
    when(() => bloc.delayedRefreshForegrounds()).thenAnswer((_) async {});
    when(() => state.currentCollection).thenReturn('');
    when(() => state.pageName).thenReturn('');
    when(() => state.currentLayer).thenReturn('');
    when(() => controller.toolCubit).thenReturn(toolCubit);
    when(() => controller.inputCubit).thenReturn(input);
    when(() => input.effectivePenOnlyInput).thenReturn(false);
    when(() => settings.state).thenReturn(const ButterflySettings());

    late BuildContext buildContext;
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<DocumentBloc>.value(value: bloc),
          RepositoryProvider<EditorController>.value(value: controller),
          RepositoryProvider<TransformCubit>.value(value: transform),
          RepositoryProvider<SettingsCubit>.value(value: settings),
        ],
        child: Builder(
          builder: (context) {
            buildContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    const viewport = Size(800, 600);
    final context = _Context();
    when(() => context.buildContext).thenReturn(buildContext);
    when(() => context.viewportSize).thenReturn(viewport);
    when(() => context.getDocumentBloc()).thenReturn(bloc);

    const start = Duration(seconds: 100);
    for (var i = 0; i < 10; i++) {
      final position = Offset(10.0 + i * 20, 50);
      final event = PointerMoveEvent(
        pointer: 1,
        kind: kind,
        position: position,
        timeStamp: start + Duration(milliseconds: i * 16),
        tilt: 0.4 + i * 0.01,
        orientation: 1.2,
      );
      handler.addPoint(
        buildContext,
        1,
        position,
        viewport,
        0.5,
        kind,
        refresh: false,
        shouldCreate: i == 0,
        event: event,
      );
    }
    handler.onPointerUp(
      PointerUpEvent(
        pointer: 1,
        kind: kind,
        position: const Offset(190, 50),
        timeStamp: start + const Duration(milliseconds: 9 * 16),
        tilt: 0.49,
        orientation: 1.2,
      ),
      context,
    );
    return (created.single.elements.single as PenElement).points;
  }

  testWidgets('13: stylus events record tilt, azimuth and time', (
    tester,
  ) async {
    final points = await draw(tester, PointerDeviceKind.stylus);
    expect(points.first.time, 0);
    expect(points.first.tilt, closeTo(0.4, 1e-9));
    expect(points.first.azimuth, closeTo(1.2, 1e-9));
    expect(points[5].time, 80);
    expect(points[5].tilt, closeTo(0.45, 1e-9));
    // The stabilizer's catch-up points copy the last event.
    for (final point in points.skip(10)) {
      expect(point.time, 144);
      expect(point.tilt, closeTo(0.49, 1e-9));
    }
  });

  testWidgets('13: mouse events record only time', (tester) async {
    final points = await draw(tester, PointerDeviceKind.mouse);
    expect(points[3].time, 48);
    for (final point in points) {
      expect(point.tilt, isNull);
      expect(point.azimuth, isNull);
      expect(point.time, isNotNull);
    }
  });
}
