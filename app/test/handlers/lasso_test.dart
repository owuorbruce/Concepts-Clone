import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:butterfly/cubits/editor_runtime.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_sysapi/lw_sysapi.dart';
import 'package:mocktail/mocktail.dart';

import 'tool_harness.dart';

class _Clipboard extends Mock implements ClipboardManager {}

PenElement _stroke(
  String id,
  List<Offset> points, {
  double width = 2,
  String brush = '',
}) => PenElement(
  id: id,
  property: PenProperty(strokeWidth: width, brush: brush),
  points: [for (final p in points) PathPoint(p.dx, p.dy, 1)],
);

List<Offset> _rect(double l, double t, double r, double b) => [
  Offset(l, t),
  Offset(r, t),
  Offset(r, b),
  Offset(l, b),
];

/// A dense lasso along [corners], like a pen drawing it.
List<Offset> _dense(List<Offset> corners, {int perSide = 20}) => [
  for (var i = 0; i < corners.length; i++)
    for (var j = 0; j < perSide; j++)
      Offset.lerp(corners[i], corners[(i + 1) % corners.length], j / perSide)!,
];

void main() {
  late ToolHarness harness;

  Future<void> setUp(
    WidgetTester tester,
    List<PadElement> content, {
    List<DocumentLayer> extraLayers = const [],
    Set<String>? invisibleLayers,
  }) async {
    harness = ToolHarness();
    await tester.runAsync(
      () => harness.setUp(
        content: content,
        extraLayers: extraLayers,
        invisibleLayers: invisibleLayers,
      ),
    );
    addTearDown(() => tester.runAsync(harness.dispose));
    await harness.pumpContext(tester);
  }

  SelectHandler lassoHandler([
    HitElementMode mode = HitElementMode.touchAnywhere,
  ]) => SelectHandler(SelectTool(mode: SelectMode.lasso, hitElementMode: mode));

  /// Draws [points] with one pointer and lifts it.
  Future<void> lasso(
    WidgetTester tester,
    SelectHandler handler,
    List<Offset> points, {
    int pointer = 1,
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    bool lift = true,
  }) => tester.runAsync(() async {
    handler.onPointerDown(
      PointerDownEvent(pointer: pointer, kind: kind, position: points.first),
      harness.context,
    );
    handler.onScaleStart(
      ScaleStartDetails(localFocalPoint: points.first),
      harness.context,
    );
    for (final point in points.skip(1)) {
      handler.onPointerMove(
        PointerMoveEvent(pointer: pointer, kind: kind, position: point),
        harness.context,
      );
      handler.onScaleUpdate(
        ScaleUpdateDetails(localFocalPoint: point, pointerCount: 1),
        harness.context,
      );
    }
    if (!lift) return;
    await handler.onPointerUp(
      PointerUpEvent(pointer: pointer, kind: kind, position: points.last),
      harness.context,
    );
    await handler.onScaleEnd(ScaleEndDetails(), harness.context);
    await harness.settle();
  });

  Set<String?> ids(SelectHandler handler) => {
    for (final renderer in handler.selected) renderer.element.id,
  };

  testWidgets('1: the pen-down point is the lasso first point', (tester) async {
    await setUp(tester, []);
    final handler = lassoHandler();
    await lasso(tester, handler, const [
      Offset(10, 10),
      Offset(80, 12),
      Offset(60, 90),
    ], lift: false);
    expect(handler.isLassoActive, isTrue);
    expect(handler.lassoPoints!.first, const Offset(10, 10));
  });

  testWidgets('2: tiny lassos select nothing and keep the selection', (
    tester,
  ) async {
    await setUp(tester, [
      _stroke('a', const [Offset(100, 100), Offset(200, 100)]),
      _stroke('b', const [Offset(300, 300), Offset(301, 301)]),
    ]);
    final handler = lassoHandler();
    await tester.runAsync(
      () async => handler.selectAll(harness.bloc, (r) => r.element.id == 'a'),
    );
    // Two points: no hit test.
    await lasso(tester, handler, const [Offset(290, 290), Offset(310, 310)]);
    expect(ids(handler), {'a'});
    // Three points around b but under 16 px².
    await lasso(tester, handler, const [
      Offset(298, 298),
      Offset(304, 298),
      Offset(301, 302),
    ]);
    expect(ids(handler), {'a'});
    expect(
      SelectHandler.prepareLasso(const [
        Offset(0, 0),
        Offset(3, 0),
        Offset(0, 3),
      ], 1),
      isNull,
    );
    expect(SelectHandler.prepareLasso(_rect(0, 0, 10, 10), 1), isNotNull);
  });

  testWidgets('3: Touching selects a wide stroke grazed outside its center', (
    tester,
  ) async {
    await setUp(tester, [
      _stroke('marker', const [
        Offset(100, 300),
        Offset(300, 300),
        Offset(500, 300),
      ], width: 40),
    ]);
    final handler = lassoHandler();
    // From 312 to 360: past the centerline, inside the 20 px half width.
    await lasso(tester, handler, _dense(_rect(250, 312, 350, 360)));
    expect(ids(handler), {'marker'});
  });

  testWidgets('4: Enclosed tests segments, not only points', (tester) async {
    await setUp(tester, [
      _stroke('line', const [Offset(100, 300), Offset(500, 300)]),
    ]);
    final handler = lassoHandler(HitElementMode.full);
    // A C around the line: the notch at the top reaches below it, so the
    // line's middle runs outside while both its points are inside.
    final cShape = [
      const Offset(50, 250),
      const Offset(280, 250),
      const Offset(280, 330),
      const Offset(320, 330),
      const Offset(320, 250),
      const Offset(550, 250),
      const Offset(550, 350),
      const Offset(50, 350),
    ];
    await lasso(tester, handler, _dense(cShape));
    expect(ids(handler), isEmpty);
    await lasso(tester, handler, _dense(_rect(50, 250, 550, 350)));
    expect(ids(handler), {'line'});
  });

  testWidgets('5: a rotated object is enclosed by its rotated shape', (
    tester,
  ) async {
    await setUp(tester, [
      ShapeElement(
        id: 'bar',
        firstPosition: const Point(200, 290),
        secondPosition: const Point(400, 310),
        rotation: 45,
      ),
    ]);
    final handler = lassoHandler(HitElementMode.full);
    // A thin diamond along the 45° diagonal through the center (300, 300).
    Offset along(double t, double n) =>
        const Offset(300, 300) +
        Offset(cos(pi / 4), sin(pi / 4)) * t +
        Offset(-sin(pi / 4), cos(pi / 4)) * n;
    await lasso(
      tester,
      handler,
      _dense([
        along(-115, -18),
        along(115, -18),
        along(115, 18),
        along(-115, 18),
      ]),
    );
    expect(ids(handler), {'bar'});
    // A box around its unrotated bounds does not enclose it.
    await lasso(tester, handler, _dense(_rect(190, 285, 410, 315)));
    expect(ids(handler), isEmpty);
  });

  testWidgets('6: adding the same element twice keeps one copy', (
    tester,
  ) async {
    await setUp(tester, [
      _stroke('a', const [Offset(100, 100), Offset(200, 100)]),
    ]);
    when(() => harness.context.isCtrlPressed).thenReturn(true);
    final handler = lassoHandler();
    final around = _dense(_rect(80, 80, 220, 120));
    await lasso(tester, handler, around);
    await lasso(tester, handler, around);
    expect(handler.selected, hasLength(1));
  });

  testWidgets('7: drags on a selected element move; elsewhere they lasso', (
    tester,
  ) async {
    await setUp(tester, [
      _stroke('left', const [Offset(100, 100), Offset(150, 100)]),
      _stroke('right', const [Offset(400, 300), Offset(450, 300)]),
    ]);
    final handler = lassoHandler();
    await tester.runAsync(() async => handler.selectAll(harness.bloc));
    // Inside the selection's box but on empty canvas: a new lasso.
    await lasso(tester, handler, const [
      Offset(260, 190),
      Offset(300, 190),
      Offset(300, 230),
    ], lift: false);
    expect(handler.isLassoActive, isTrue);
    handler.cancelLasso(harness.context);
    // On a selected stroke: a move.
    await tester.runAsync(() async {
      const start = Offset(120, 100);
      handler.onPointerDown(
        const PointerDownEvent(pointer: 3, position: start),
        harness.context,
      );
      expect(handler.isLassoActive, isFalse);
      handler.onScaleStart(
        ScaleStartDetails(localFocalPoint: start),
        harness.context,
      );
      handler.onScaleUpdate(
        ScaleUpdateDetails(
          localFocalPoint: start + const Offset(0, 50),
          pointerCount: 1,
        ),
        harness.context,
      );
      await handler.onScaleEnd(ScaleEndDetails(), harness.context);
      await harness.settle();
    });
    expect(harness.changed, hasLength(1));
    final moved = harness.changed.single['left']!.single as PenElement;
    expect(moved.points.first.y, closeTo(150, 1e-6));
  });

  testWidgets('8: a second finger cancels the lasso; selection unchanged', (
    tester,
  ) async {
    await setUp(tester, [
      _stroke('a', const [Offset(100, 100), Offset(200, 100)]),
      _stroke('b', const [Offset(100, 300), Offset(200, 300)]),
    ]);
    final handler = lassoHandler();
    await tester.runAsync(
      () async => handler.selectAll(harness.bloc, (r) => r.element.id == 'a'),
    );
    final around = _dense(_rect(80, 280, 220, 320));
    await lasso(
      tester,
      handler,
      around,
      kind: PointerDeviceKind.touch,
      lift: false,
    );
    handler.onPointerDown(
      const PointerDownEvent(
        pointer: 2,
        kind: PointerDeviceKind.touch,
        position: Offset(400, 400),
      ),
      harness.context,
    );
    expect(handler.isLassoActive, isFalse);
    await tester.runAsync(() async {
      await handler.onPointerUp(
        PointerUpEvent(
          pointer: 1,
          kind: PointerDeviceKind.touch,
          position: around.last,
        ),
        harness.context,
      );
      await harness.settle();
    });
    expect(ids(handler), {'a'});
  });

  testWidgets('5 (pen): one finger touch never extends a pen lasso', (
    tester,
  ) async {
    await setUp(tester, []);
    final handler = lassoHandler();
    await lasso(tester, handler, _dense(_rect(0, 0, 50, 50)), lift: false);
    final count = handler.lassoPoints!.length;
    handler.onPointerDown(
      const PointerDownEvent(
        pointer: 7,
        kind: PointerDeviceKind.touch,
        position: Offset(500, 500),
      ),
      harness.context,
    );
    handler.onPointerMove(
      const PointerMoveEvent(
        pointer: 7,
        kind: PointerDeviceKind.touch,
        position: Offset(520, 520),
      ),
      harness.context,
    );
    expect(handler.isLassoActive, isTrue);
    expect(handler.lassoPoints!.length, count);
    // A second finger: pan and zoom, and the lasso is gone.
    handler.onPointerDown(
      const PointerDownEvent(
        pointer: 8,
        kind: PointerDeviceKind.touch,
        position: Offset(600, 500),
      ),
      harness.context,
    );
    expect(handler.isLassoActive, isFalse);
  });

  testWidgets('9: hidden layers and other layers when locked are skipped', (
    tester,
  ) async {
    await setUp(
      tester,
      [
        _stroke('here', const [Offset(100, 100), Offset(200, 100)]),
      ],
      extraLayers: [
        DocumentLayer(
          id: 'hidden',
          content: [
            _stroke('ghost', const [Offset(100, 110), Offset(200, 110)]),
          ],
        ),
        DocumentLayer(
          id: 'other',
          content: [
            _stroke('other', const [Offset(100, 120), Offset(200, 120)]),
          ],
        ),
      ],
      invisibleLayers: {'hidden'},
    );
    final handler = lassoHandler();
    final around = _dense(_rect(40, 40, 260, 180));
    await lasso(tester, handler, around);
    expect(ids(handler), {'here', 'other'});
    when(() => harness.context.getViewState()).thenReturn(
      const EditorViewState(locks: PersistentLockState(lockLayer: true)),
    );
    await lasso(tester, handler, around);
    expect(ids(handler), {'here'});
  });

  testWidgets('10: a 2,000-point lasso over 500 elements is fast', (
    tester,
  ) async {
    final random = Random(3);
    await setUp(tester, [
      for (var i = 0; i < 500; i++)
        () {
          final x = random.nextDouble() * 760 + 20;
          final y = random.nextDouble() * 560 + 20;
          return _stroke('s$i', [
            for (var j = 0; j < 30; j++) Offset(x + j * 2, y + sin(j / 3) * 6),
          ]);
        }(),
    ]);
    final handler = lassoHandler();
    final circle = [
      for (var i = 0; i < 2000; i++)
        const Offset(400, 300) + Offset.fromDirection(i / 2000 * 2 * pi, 250),
    ];
    // Best of three, so other test files running alongside don't count.
    var best = double.infinity;
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(() async => handler.clearSelection(harness.bloc));
      await lasso(tester, handler, circle, lift: false);
      expect(handler.isLassoActive, isTrue);
      // Drawing takes longer than a frame, so the live highlight has run
      // (and warmed the hit tests) by the time the pen lifts.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      // Timed inside the real async zone, without the test binding's own
      // overhead around it.
      final watch = Stopwatch();
      await tester.runAsync(() async {
        watch.start();
        await handler.onPointerUp(
          PointerUpEvent(pointer: 1, position: circle.last),
          harness.context,
        );
        watch.stop();
      });
      best = min(best, watch.elapsedMicroseconds / 1000);
      expect(handler.selected, isNotEmpty);
    }
    final ms = best;
    // ignore: avoid_print
    print(
      'Lasso of 2,000 points over 500 elements: ${ms.toStringAsFixed(2)} ms '
      '(${handler.selected.length} selected)',
    );
    expect(handler.selected, isNotEmpty);
    expect(ms, lessThan(16));
  });

  testWidgets('11: undo of a move is one step; copy writes each once', (
    tester,
  ) async {
    await setUp(tester, [
      _stroke('a', const [Offset(100, 100), Offset(300, 100)]),
      _stroke('b', const [Offset(100, 200), Offset(300, 200)]),
    ]);
    final handler = lassoHandler();
    when(() => harness.context.isCtrlPressed).thenReturn(true);
    final around = _dense(_rect(40, 40, 360, 260));
    await lasso(tester, handler, around);
    await lasso(tester, handler, around);
    expect(handler.selected, hasLength(2));
    when(() => harness.context.isCtrlPressed).thenReturn(false);
    await tester.runAsync(() async {
      // On stroke a, away from the selection's handles.
      const start = Offset(150, 100);
      handler.onPointerDown(
        const PointerDownEvent(pointer: 4, position: start),
        harness.context,
      );
      handler.onScaleStart(
        ScaleStartDetails(localFocalPoint: start),
        harness.context,
      );
      handler.onScaleUpdate(
        ScaleUpdateDetails(
          localFocalPoint: start + const Offset(40, 0),
          pointerCount: 1,
        ),
        harness.context,
      );
      await handler.onScaleEnd(ScaleEndDetails(), harness.context);
      await harness.settle();
    });
    expect(harness.changed, hasLength(1));
    double firstX(String id) => (harness.content.firstWhere(
      (e) => e.id == id,
    ) as PenElement).points.first.x;
    expect(firstX('a'), closeTo(140, 1e-6));
    await tester.runAsync(() async {
      harness.bloc.undo();
      await harness.settle();
    });
    expect(firstX('a'), closeTo(100, 1e-6));
    expect(firstX('b'), closeTo(100, 1e-6));

    registerFallbackValue((data: Uint8List(0), type: ''));
    final clipboard = _Clipboard();
    Object? written;
    when(() => clipboard.setContent(any())).thenAnswer((invocation) {
      written = invocation.positionalArguments.single;
      return true;
    });
    await tester.runAsync(() async => handler.selectAll(harness.bloc));
    await tester.runAsync(() => handler.copySelection(harness.bloc, clipboard));
    final data = (written! as ({Uint8List data, String type})).data;
    final page = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    final copied = [
      for (final layer in page['layers'] as List)
        for (final element in (layer as Map)['content'] as List)
          (element as Map)['id'],
    ];
    expect(copied..sort(), ['a', 'b']);
  });
}
