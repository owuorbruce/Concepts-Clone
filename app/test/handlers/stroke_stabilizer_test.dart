import 'dart:ui';

import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/handlers/stroke_stabilizer.dart';
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

/// A zig-zag around the line y = 100.
List<Offset> _zigZag() => [
  for (var i = 0; i <= 40; i++) Offset(i * 10.0, i.isEven ? 90 : 110),
];

double _averageDeviation(List<Offset> points) =>
    points.map((p) => (p.dy - 100).abs()).reduce((a, b) => a + b) /
    points.length;

void main() {
  group('StrokeStabilizer', () {
    test('no smoothing returns the raw points unchanged', () {
      final stabilizer = StrokeStabilizer(0);
      final raw = [
        const Offset(0.1, 0.3),
        const Offset(10.7, 3.3),
        const Offset(-4.9, 22.123456789),
        ..._zigZag(),
      ];
      expect(raw.map(stabilizer.add).toList(), raw);
      expect(stabilizer.finish(raw.last), isEmpty);
    });

    test('full smoothing calms a zig-zag', () {
      final raw = _zigZag();
      // Skip the start, where the line settles from the first point.
      final calm = raw.map(StrokeStabilizer(1).add).toList().sublist(20);
      final rough = raw.map(StrokeStabilizer(0).add).toList().sublist(20);
      expect(
        _averageDeviation(calm),
        lessThan(_averageDeviation(rough) * 0.25),
      );
    });

    test('values outside 0 to 1 are clamped', () {
      expect(StrokeStabilizer(-1).alpha, 1);
      expect(StrokeStabilizer(2).alpha, closeTo(0.1, 1e-9));
    });

    test('finish ends exactly at the raw point', () {
      final stabilizer = StrokeStabilizer(1);
      stabilizer.add(Offset.zero);
      stabilizer.add(const Offset(100, 50));
      const tip = Offset(100, 50);
      final catchUp = stabilizer.finish(tip);
      expect(catchUp, hasLength(StrokeStabilizer.finishSteps));
      expect(catchUp.last, tip);
      expect(stabilizer.last, tip);
      for (var i = 1; i < catchUp.length; i++) {
        expect(
          (catchUp[i] - catchUp[i - 1]).distance,
          closeTo((catchUp[1] - catchUp[0]).distance, 1e-9),
        );
      }
      expect(stabilizer.finish(tip + const Offset(0.3, 0)), isEmpty);
    });
  });

  group('pen strokes', () {
    setUpAll(() {
      registerFallbackValue(Offset.zero);
      registerFallbackValue(ElementsCreated(const []));
    });

    /// Draws [screen] with a pen of [smoothing] at [zoom] and returns the
    /// submitted stroke in screen pixels.
    Future<List<Offset>> draw(
      WidgetTester tester, {
      required double zoom,
      required double smoothing,
      required List<Offset> screen,
    }) async {
      final handler = PenHandler(
        PenTool(property: PenProperty(smoothing: smoothing)),
      );
      final transform = TransformCubit(1)
        ..teleport(const Offset(-37, 52), zoom);
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

      for (final (i, point) in screen.indexed) {
        handler.addPoint(
          buildContext,
          1,
          point,
          viewport,
          0.5,
          PointerDeviceKind.stylus,
          refresh: false,
          shouldCreate: i == 0,
        );
      }
      handler.onPointerUp(
        PointerUpEvent(
          pointer: 1,
          position: screen.last,
          kind: PointerDeviceKind.stylus,
        ),
        context,
      );
      final element = created.single.elements.single as PenElement;
      return [
        for (final point in element.points)
          transform.state.globalToLocal(Offset(point.x, point.y)),
      ];
    }

    testWidgets('smoothing is the same in screen pixels at every zoom', (
      tester,
    ) async {
      final screen = _zigZag();
      final atOne = await draw(
        tester,
        zoom: 1,
        smoothing: 0.75,
        screen: screen,
      );
      final atFour = await draw(
        tester,
        zoom: 4,
        smoothing: 0.75,
        screen: screen,
      );
      expect(atOne, hasLength(atFour.length));
      for (var i = 0; i < atOne.length; i++) {
        expect(atFour[i], offsetMoreOrLessEquals(atOne[i], epsilon: 1e-6));
      }
      // The stroke is steadied, and still ends at the pen tip.
      expect(_averageDeviation(atOne.skip(5).toList()), lessThan(5));
      expect(atOne.last, offsetMoreOrLessEquals(screen.last, epsilon: 1e-6));
    });

    testWidgets('no smoothing stores the input exactly', (tester) async {
      final screen = _zigZag();
      final points = await draw(tester, zoom: 2, smoothing: 0, screen: screen);
      expect(points, hasLength(screen.length));
      for (var i = 0; i < screen.length; i++) {
        expect(points[i], offsetMoreOrLessEquals(screen[i], epsilon: 1e-6));
      }
    });
  });
}
