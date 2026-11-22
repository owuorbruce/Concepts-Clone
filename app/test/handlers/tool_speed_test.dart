import 'dart:math';

import 'package:butterfly/brushes/brush_registry.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/renderers/foregrounds/select.dart';
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tool_harness.dart';

/// 300 classic strokes, 100 brush strokes, 20 objects and 10 walls.
List<PadElement> _page() {
  final random = Random(7);
  PenElement stroke(String id, String brush) {
    final x = random.nextDouble() * 1600, y = random.nextDouble() * 1200;
    return PenElement(
      id: id,
      property: PenProperty(brush: brush, strokeWidth: 4),
      points: [
        for (var i = 0; i < 40; i++)
          PathPoint(x + i * 4, y + sin(i / 4) * 20, 1),
      ],
    );
  }

  return [
    for (var i = 0; i < 300; i++) stroke('classic-$i', ''),
    for (var i = 0; i < 100; i++)
      stroke('brush-$i', i.isEven ? 'amaze.pencil' : 'amaze.watercolor'),
    for (var i = 0; i < 20; i++)
      ShapeElement(
        id: 'object-$i',
        firstPosition: Point(i * 70.0, 900),
        secondPosition: Point(i * 70.0 + 50, 960),
      ),
    for (var i = 0; i < 10; i++)
      makeWall(
        Point(100.0, 100.0 + i * 100),
        Point(900.0, 100.0 + i * 100),
        6,
        kDefaultWallColor,
      ).copyWith(id: 'wall-$i'),
  ];
}

/// Debug builds are slower than profile ones; the bar there is 30 ms.
const _limitMs = kDebugMode ? 30.0 : 8.0;

void main() {
  testWidgets('12: no tool takes over 8 ms per move on a full page', (
    tester,
  ) async {
    await tester.runAsync(loadBrushRegistry);
    final harness = ToolHarness();
    await tester.runAsync(() => harness.setUp(content: _page()));
    addTearDown(() => tester.runAsync(harness.dispose));
    await harness.pumpContext(tester);
    final state = harness.state;
    final context = harness.context;
    final results = <String, double>{};

    Future<void> measure(
      String name,
      Handler handler, {
      bool scale = true,
      bool hover = false,
      Future<void> Function()? start,
    }) async {
      await tester.runAsync(() async {
        await start?.call();
        const from = Offset(400, 300);
        handler.onPointerDown(
          const PointerDownEvent(pointer: 9, position: from),
          context,
        );
        if (scale) {
          handler.onScaleStart(
            ScaleStartDetails(localFocalPoint: from),
            context,
          );
        }
        final watch = Stopwatch();
        const moves = 40;
        for (var i = 1; i <= moves; i++) {
          final point = from + Offset(i * 5.0, i * 3.0);
          watch.start();
          if (hover) {
            handler.onPointerHover(PointerHoverEvent(position: point), context);
          }
          await handler.onPointerMove(
            PointerMoveEvent(pointer: 9, position: point),
            context,
          );
          if (scale) {
            handler.onScaleUpdate(
              ScaleUpdateDetails(localFocalPoint: point, pointerCount: 1),
              context,
            );
          }
          handler.createForegrounds(
            harness.controller,
            state.data,
            state.page,
            state.info,
          );
          watch.stop();
        }
        results[name] = watch.elapsedMicroseconds / moves / 1000;
        handler.dispose(harness.bloc);
      });
    }

    // The per-element preview the move used before: a scale rebuilds every
    // selected element each frame.
    final scaling = SelectHandler(SelectTool());
    await measure(
      'select (scaling 450 elements, per-element preview)',
      scaling,
      start: () async {
        scaling.selectAll(harness.bloc);
        final rect = scaling.getSelectionRect()!;
        scaling.transform(
          harness.bloc,
          SelectionTransformCorner.bottomRight,
          position: rect.bottomRight,
        );
      },
    );

    for (final family in ToolFamily.values) {
      if (family.isAction) continue;
      for (final tool in family.variants) {
        final handler = Handler.fromTool(tool);
        final name = '${family.name}/${tool.runtimeType}';
        switch (handler) {
          case SelectHandler select:
            await measure(
              '$name (moving 450 elements)',
              select,
              start: () async {
                select.selectAll(harness.bloc);
                select.transform(
                  harness.bloc,
                  null,
                  position: const Offset(400, 300),
                );
              },
            );
          case PolygonHandler polygon:
            await measure(
              name,
              polygon,
              scale: false,
              hover: true,
              start: () async {
                polygon.addPoint(context, const Offset(300, 300));
              },
            );
          case LabelHandler() || TableHandler() || BarcodeHandler():
            // Tap tools: nothing happens while the pointer moves.
            continue;
          default:
            await measure(name, handler);
        }
      }
    }
    final sorted = results.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // ignore: avoid_print
    print(
      'Tool move times (ms per move):\n'
      '${sorted.map((e) => '  ${e.key}: ${e.value.toStringAsFixed(2)}').join('\n')}',
    );
    for (final entry in sorted) {
      expect(entry.value, lessThan(_limitMs), reason: entry.key);
    }
  });
}
