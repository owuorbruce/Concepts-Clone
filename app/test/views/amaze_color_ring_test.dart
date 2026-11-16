import 'dart:math' as math;

import 'package:butterfly/models/marker_palette.dart';
import 'package:butterfly/services/marker_palette_loader.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/views/amaze/color/color_wheel_picker.dart';
import 'package:butterfly/views/amaze/color/marker_ring.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ring = ValueKey('amaze-color-ring');
const _code = ValueKey('amaze-color-code');
const _degree = math.pi / 180;

/// Tool wheel radii from the smallest wheel to the old default one.
const _smallRadii = [80.0, 88.0, 120.0, 160.0];

/// What the picker reported through its callbacks.
class _Session {
  final picks = <SRGBColor>[];
  final closed = <SRGBColor?>[];
  var eyedroppers = 0;
}

/// Tool wheel centers that keep a wheel of [radius] on [screen]: the
/// middle, the four edges and the four corners.
List<Offset> _positions(Size screen, double radius) {
  final xs = [radius, screen.width / 2, screen.width - radius];
  final ys = [radius, screen.height / 2, screen.height - radius];
  return [
    for (final x in xs)
      for (final y in ys) Offset(x, y),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MarkerPalette palette;

  setUpAll(() async {
    palette = (await loadMarkerPalette())!;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  void expectSound(MarkerRingGeometry geometry, String reason) {
    final swatches = geometry.swatches;
    expect(swatches, hasLength(358));
    expect(swatches.map((s) => s.marker.code).toSet(), hasLength(358));
    for (var i = 0; i < swatches.length; i++) {
      final a = swatches[i];
      expect(
        a.shortSide,
        greaterThanOrEqualTo(kMarkerMinSwatchSide),
        reason: '${a.marker.code} in $reason',
      );
      expect(
        MarkerRingGeometry.labelSize(a),
        greaterThanOrEqualTo(kMarkerMinLabelSize),
      );
      expect(a.innerRadius, greaterThan(geometry.innerRadius));
      for (var j = i + 1; j < swatches.length; j++) {
        final b = swatches[j];
        expect(
          a.overlaps(b),
          isFalse,
          reason: '${a.marker.code} and ${b.marker.code} overlap in $reason',
        );
      }
    }
  }

  group('geometry', () {
    test('358 swatches of at least 28 px, none overlapping', () {
      expectSound(MarkerRingGeometry(palette), 'the full layout');
      for (final radius in _smallRadii) {
        expectSound(
          MarkerRingGeometry(palette, innerRadius: radius),
          'the full layout around $radius',
        );
      }
      for (final radius in [..._smallRadii, 240.0]) {
        expectSound(
          MarkerRingGeometry(
            palette,
            innerRadius: radius,
            ringRatio: MarkerRingGeometry.minRingRatio(radius),
            spread: 0,
          ),
          'the smallest layout around $radius',
        );
      }
    });

    test('hue families run clockwise from YR at 12 o\'clock', () {
      final geometry = MarkerRingGeometry(palette);
      const order = [
        'YR',
        'E',
        'Y',
        'YG',
        'G',
        'BG',
        'B',
        'BV',
        'V',
        'RV',
        'R',
      ];
      expect(geometry.families, order);
      final (first, firstSweep) = geometry.familySpans['YR']!;
      expect(first, lessThan(-math.pi / 2));
      expect(first + firstSweep, greaterThan(-math.pi / 2));
      var previous = first;
      for (final family in order.skip(1)) {
        final (start, _) = geometry.familySpans[family]!;
        expect(start, greaterThan(previous), reason: family);
        previous = start;
      }
      expect(previous - first, lessThan(2 * math.pi));
      // Every swatch of a family is inside the family's span.
      for (final swatch in geometry.swatches) {
        final span = geometry.familySpans[swatch.marker.family];
        if (span == null) continue;
        expect(swatch.start, greaterThanOrEqualTo(span.$1 - 1e-9));
        expect(
          swatch.start + swatch.sweep,
          lessThanOrEqualTo(span.$1 + span.$2),
        );
      }
    });

    test('columns hold one first digit, darkest inside', () {
      final geometry = MarkerRingGeometry(palette);
      double inner(String code) => geometry.byCode(code)!.innerRadius;
      // The data has no B09; B06 is the darkest of the B0 column.
      expect(geometry.byCode('B09'), isNull);
      expect(inner('B0000'), greaterThan(inner('B000')));
      expect(inner('B000'), greaterThan(inner('B00')));
      expect(inner('B00'), greaterThan(inner('B01')));
      expect(inner('B01'), greaterThan(inner('B06')));
      expect(inner('E0000'), greaterThan(inner('E00')));
      expect(inner('E00'), greaterThan(inner('E09')));
      for (final codes in [
        ['B00', 'B0000', 'B06'],
        ['B12', 'B14', 'B18'],
        ['R20', 'R29'],
      ]) {
        final starts = {for (final c in codes) geometry.byCode(c)!.start};
        expect(starts, hasLength(1), reason: '$codes share a column');
      }
      expect(
        geometry.byCode('B12')!.start,
        greaterThan(geometry.byCode('B06')!.start),
      );
      expect(inner('R20'), greaterThan(inner('R29')));
    });

    test('gray ring at 3 tool wheel radii with the fluorescents inside', () {
      for (final radius in [120.0, 160.0, 240.0]) {
        final geometry = MarkerRingGeometry(palette, innerRadius: radius);
        bool gray(MarkerSwatchGeometry s) =>
            kMarkerGrayFamilies.contains(s.marker.family);
        final grays = geometry.swatches.where(gray).toList();
        expect(grays, hasLength(46));
        for (final swatch in grays) {
          expect(swatch.innerRadius / radius, inInclusiveRange(2.8, 3.2));
        }
        final grayInner = grays.map((s) => s.innerRadius).reduce(math.min);
        final fluorescents = geometry.swatches
            .where((s) => s.marker.family.startsWith('F'))
            .toList();
        expect(fluorescents, hasLength(8));
        for (final swatch in fluorescents) {
          expect(swatch.outerRadius, lessThan(grayInner));
          expect(swatch.innerRadius, greaterThan(radius));
        }
        // 0 sits beside the fluorescent arc, at the same radius.
        final zero = geometry.byCode('0')!;
        final frv = geometry.byCode('FRV')!;
        expect(zero.innerRadius, frv.innerRadius);
        expect(wrapAngle(frv.start - zero.start).abs(), lessThan(20 * _degree));
        // The darkest grays are thicker than the light ones.
        double depth(String code) {
          final swatch = geometry.byCode(code)!;
          return swatch.outerRadius - swatch.innerRadius;
        }

        expect(depth('W-10'), greaterThan(depth('W-1')));
        expect(depth('C-9'), greaterThan(depth('C-0')));
        // Hue bars start outside the gray ring.
        final bars = geometry.swatches
            .where((s) => kMarkerHueFamilies.contains(s.marker.family))
            .map((s) => s.innerRadius)
            .reduce(math.min);
        expect(bars, greaterThan(geometry.ringOuter));
        // Radii are multiples of the tool wheel radius.
        expect(geometry.ringInner, closeTo(3 * radius, 1e-9));
      }
    });

    for (final radius in _smallRadii) {
      test('every swatch resolves to its own code under rotation around '
          '$radius', () {
        final geometry = MarkerRingGeometry(palette, innerRadius: radius);
        const center = Offset(640, 400);
        for (final degrees in [0.0, 77.0, 215.0]) {
          final rotation = degrees * _degree;
          for (final swatch in geometry.swatches) {
            final point = geometry.positionOf(
              swatch,
              center: center,
              rotation: rotation,
            );
            expect(
              geometry.hitTest(point - center, rotation: rotation)?.marker.code,
              swatch.marker.code,
              reason: '${swatch.marker.code} at $degrees°',
            );
            expect(
              geometry.containsWheel(point - center, rotation: rotation),
              isTrue,
            );
          }
        }
        // The tool wheel and the canvas beyond the bars are not the wheel.
        expect(geometry.containsWheel(Offset(radius / 2, 0)), isFalse);
        expect(
          geometry.containsWheel(Offset(geometry.outerRadius + 20, 0)),
          isFalse,
        );
        expect(geometry.hitTest(Offset(radius + 10, 0)), isNull);
      });

      test('every swatch can be spun fully on screen from any position '
          'around $radius', () {
        for (final screen in [const Size(1280, 800), const Size(800, 1280)]) {
          for (final center in _positions(screen, radius)) {
            final geometry = MarkerRingGeometry.fit(
              palette,
              innerRadius: radius,
              center: center,
              screen: screen,
            );
            expect(geometry.swatches, hasLength(358));
            for (final swatch in geometry.swatches) {
              expect(
                swatch.shortSide,
                greaterThanOrEqualTo(kMarkerMinSwatchSide),
              );
              final rotation = MarkerRingGeometry.rotationToShow(
                swatch,
                center: center,
                screen: screen,
              );
              expect(
                rotation,
                isNotNull,
                reason: '${swatch.marker.code} from $center on $screen',
              );
              final bounds = (Offset.zero & screen).inflate(1e-6);
              for (final point in swatch.hull(center, rotation!)) {
                expect(bounds.contains(point), isTrue);
              }
            }
          }
        }
      });

      test('codes are never upside down around $radius', () {
        final geometry = MarkerRingGeometry(palette, innerRadius: radius);
        for (final degrees in [0.0, 77.0, 215.0]) {
          for (final swatch in geometry.swatches) {
            final angle = swatch.midAngle + degrees * _degree;
            final rotation = MarkerRingGeometry.textRotation(angle);
            expect(rotation.abs(), lessThanOrEqualTo(math.pi / 2 + 1e-9));
            // The text runs along the ring: upright, or turned half way
            // round on the lower half.
            final along = wrapAngle(angle + math.pi / 2);
            final flipped = wrapAngle(rotation - along).abs() > 1;
            if (along.abs() < math.pi / 2 - 1e-6) expect(flipped, isFalse);
            if (along.abs() > math.pi / 2 + 1e-6) expect(flipped, isTrue);
          }
        }
        expect(MarkerRingGeometry.textRotation(-math.pi / 2), closeTo(0, 1e-9));
        expect(MarkerRingGeometry.textRotation(math.pi / 2), closeTo(0, 1e-9));
      });
    }

    test('the gray ring is never inside 330 px', () {
      for (final radius in [80.0, 88.0, 100.0]) {
        final geometry = MarkerRingGeometry(palette, innerRadius: radius);
        expect(geometry.ringInner, closeTo(330, 1), reason: '$radius');
        // The light disc reaches from the tool wheel to the inner arc.
        expect(geometry.discInner, greaterThan(radius));
      }
      expect(
        MarkerRingGeometry(palette, innerRadius: 160).ringInner,
        closeTo(480, 1),
      );
      // Where the screen allows the full-size layout, fit keeps it.
      for (final (radius, ring) in [(88.0, 330.0), (160.0, 480.0)]) {
        final roomy = MarkerRingGeometry.fit(
          palette,
          innerRadius: radius,
          center: const Offset(1280, 800),
          screen: const Size(2560, 1600),
        );
        expect(roomy.ringInner, closeTo(ring, 1), reason: '$radius');
        expect(roomy.spread, 1);
      }
      // The smallest layout keeps the floor too.
      expect(MarkerRingGeometry.minRingRatio(88) * 88, closeTo(330, 1));
    });

    test('the layout is full size where there is room for it', () {
      // In a corner of a large screen nothing has to give.
      final roomy = MarkerRingGeometry.fit(
        palette,
        innerRadius: 120,
        center: const Offset(120, 120),
        screen: const Size(2560, 1600),
      );
      expect(roomy.ringRatio, kMarkerRingRatio);
      expect(roomy.spread, 1);
      // In the middle of 1280x800 the ring has to move in.
      final tight = MarkerRingGeometry.fit(
        palette,
        innerRadius: 160,
        center: const Offset(640, 400),
        screen: const Size(1280, 800),
      );
      expect(tight.spread, 0);
      expect(tight.ringRatio, lessThan(kMarkerRingRatio));
      expect(
        tight.ringRatio,
        greaterThanOrEqualTo(MarkerRingGeometry.minRingRatio(160)),
      );
    });
  });

  void setScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Pumps an app with a button that opens the picker, and opens it.
  Future<_Session> open(
    WidgetTester tester, {
    bool noData = false,
    SRGBColor initial = SRGBColor.white,
    Offset? center = const Offset(640, 400),
    double innerRadius = 160,
    _Session? session,
  }) async {
    final result = session ?? _Session();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: FilledButton(
                key: const ValueKey('open-color'),
                onPressed: () => showAmazeColorWheel(
                  context,
                  center: center,
                  innerRadius: innerRadius,
                  initial: initial,
                  paletteLoader: () async => noData ? null : palette,
                  onPick: result.picks.add,
                  onClosed: result.closed.add,
                  onEyedropper: () => result.eyedroppers++,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-color')));
    await tester.pumpAndSettle();
    return result;
  }

  MarkerWheelPainter painter(WidgetTester tester) {
    return tester.widget<CustomPaint>(find.byKey(_ring)).painter!
        as MarkerWheelPainter;
  }

  Size screenOf(WidgetTester tester) => tester.view.physicalSize;

  /// Where [code]'s swatch is on screen now.
  Offset positionOf(WidgetTester tester, String code) {
    final state = painter(tester);
    return state.geometry.positionOf(
      state.geometry.byCode(code)!,
      center: state.center,
      rotation: state.rotation,
    );
  }

  /// A point of the gray ring that is on screen, to drag the wheel by.
  Offset grip(WidgetTester tester) {
    final state = painter(tester);
    final radius = (state.geometry.ringInner + state.geometry.ringOuter) / 2;
    final bounds = (Offset.zero & screenOf(tester)).deflate(4);
    for (var degrees = 0; degrees < 360; degrees += 5) {
      final point =
          state.center + Offset.fromDirection(degrees * _degree, radius);
      if (bounds.contains(point)) return point;
    }
    fail('The gray ring is off screen');
  }

  /// Drags the wheel round by [angle] and lets go without a fling.
  Future<void> spinBy(WidgetTester tester, double angle) async {
    final center = painter(tester).center;
    final start = grip(tester);
    final arm = start - center;
    final gesture = await tester.startGesture(start);
    final steps = math.max(2, (angle.abs() / (4 * _degree)).ceil());
    var time = Duration.zero;
    Offset at(int step) =>
        center +
        Offset.fromDirection(
          arm.direction + angle * step / steps,
          arm.distance,
        );
    for (var step = 1; step <= steps; step++) {
      time += const Duration(milliseconds: 16);
      await gesture.moveTo(at(step), timeStamp: time);
    }
    // Resting before the release leaves no speed to fling with.
    for (var i = 0; i < 3; i++) {
      time += const Duration(milliseconds: 200);
      await gesture.moveTo(at(steps), timeStamp: time);
    }
    await gesture.up(timeStamp: time + const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  /// Spins [code]'s swatch fully on screen and returns where it is.
  Future<Offset> reveal(WidgetTester tester, String code) async {
    final state = painter(tester);
    final target = MarkerRingGeometry.rotationToShow(
      state.geometry.byCode(code)!,
      center: state.center,
      screen: screenOf(tester),
      from: state.rotation,
    )!;
    if (target != state.rotation) {
      await spinBy(tester, target - state.rotation);
    }
    final position = positionOf(tester, code);
    expect((Offset.zero & screenOf(tester)).contains(position), isTrue);
    return position;
  }

  Future<void> tapCode(WidgetTester tester, String code) async {
    await tester.tapAt(await reveal(tester, code));
    await tester.pumpAndSettle();
  }

  String label(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(_code)).data!;

  /// A point on screen that is neither the wheel nor the tool wheel.
  Offset canvasPoint(WidgetTester tester) {
    final state = painter(tester);
    final screen = screenOf(tester);
    for (var x = 4.0; x < screen.width; x += 12) {
      for (var y = 4.0; y < screen.height; y += 12) {
        final local = Offset(x, y) - state.center;
        if (local.distance > state.geometry.ringOuter + 40 &&
            !state.geometry.containsWheel(local, rotation: state.rotation)) {
          return Offset(x, y);
        }
      }
    }
    fail('The wheel covers the whole screen');
  }

  group('spin', () {
    testWidgets('a 90° drag turns every swatch by 90° and is remembered', (
      tester,
    ) async {
      setScreen(tester, const Size(1280, 800));
      await open(tester);
      final before = painter(tester);
      expect(before.rotation, 0);
      final geometry = before.geometry;
      final angles = {
        for (final swatch in geometry.swatches)
          swatch.marker.code:
              (positionOf(tester, swatch.marker.code) - before.center)
                  .direction,
      };
      await spinBy(tester, math.pi / 2);
      final after = painter(tester);
      expect(after.rotation, closeTo(math.pi / 2, _degree));
      for (final swatch in geometry.swatches) {
        final code = swatch.marker.code;
        final now = (positionOf(tester, code) - after.center).direction;
        expect(
          wrapAngle(now - angles[code]! - math.pi / 2).abs(),
          lessThan(_degree),
          reason: code,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble(kAmazeColorAnglePreference),
        closeTo(after.rotation, 1e-9),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(_ring), findsNothing);
      await open(tester);
      expect(painter(tester).rotation, closeTo(after.rotation, 1e-9));
    });

    testWidgets('a fling keeps turning, then stops', (tester) async {
      setScreen(tester, const Size(1280, 800));
      await open(tester);
      final center = painter(tester).center;
      final start = grip(tester);
      final arm = start - center;
      final gesture = await tester.startGesture(start);
      var time = Duration.zero;
      for (var step = 1; step <= 8; step++) {
        time += const Duration(milliseconds: 8);
        await gesture.moveTo(
          center +
              Offset.fromDirection(
                arm.direction + step * 3 * _degree,
                arm.distance,
              ),
          timeStamp: time,
        );
      }
      await gesture.up(timeStamp: time);
      await tester.pump();
      final released = painter(tester).rotation;
      expect(released, closeTo(24 * _degree, _degree));
      await tester.pump(const Duration(milliseconds: 100));
      final coasting = painter(tester).rotation;
      expect(coasting, greaterThan(released));
      await tester.pump(const Duration(milliseconds: 100));
      expect(painter(tester).rotation, greaterThan(coasting));
      await tester.pumpAndSettle();
      final stopped = painter(tester).rotation;
      await tester.pump(const Duration(seconds: 1));
      expect(painter(tester).rotation, stopped);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble(kAmazeColorAnglePreference),
        closeTo(stopped % (2 * math.pi), 1e-9),
      );
    });

    testWidgets('the mouse wheel and the arrow keys spin', (tester) async {
      setScreen(tester, const Size(1280, 800));
      await open(tester);
      final start = painter(tester).rotation;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(grip(tester)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
      await tester.pumpAndSettle();
      final scrolled = painter(tester).rotation;
      expect(scrolled, isNot(start));

      /// The family at the top of the wheel.
      String top() {
        final state = painter(tester);
        final local = -math.pi / 2 - state.rotation;
        return state.geometry.families.firstWhere((family) {
          final (start, sweep) = state.geometry.familySpans[family]!;
          return (local - start) % (2 * math.pi) <= sweep;
        });
      }

      final first = top();
      final families = painter(tester).geometry.families;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final next = families[(families.indexOf(first) + 1) % families.length];
      expect(top(), next);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(top(), first);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(top(), families[(families.indexOf(first) - 1) % families.length]);
    });
  });

  group('tap', () {
    for (final screen in [const Size(1280, 800), const Size(800, 1280)]) {
      testWidgets(
        'a tap applies at once and keeps the picker open on $screen',
        (tester) async {
          setScreen(tester, screen);
          final session = await open(
            tester,
            center: screen.center(Offset.zero),
          );
          await tapCode(tester, 'R29');
          expect(session.picks.map((c) => c.value), [0xFFEF0047]);
          expect(find.byKey(_ring), findsOneWidget);
          expect(label(tester), 'R29');
          expect(find.text('Lipstick Red'), findsOneWidget);
          expect(painter(tester).selected, {'R29'});

          await tapCode(tester, 'B29');
          expect(session.picks, hasLength(2));
          expect(session.picks.last, palette.byCode('B29')!.color);
          expect(painter(tester).selected, {'B29'});
          // The color the tool already has is not applied again.
          await tapCode(tester, 'B29');
          expect(session.picks, hasLength(2));
          expect(session.closed, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('a drag that starts on a swatch spins and applies nothing', (
      tester,
    ) async {
      setScreen(tester, const Size(1280, 800));
      final session = await open(tester);
      final start = await reveal(tester, 'R29');
      final before = painter(tester).rotation;
      final center = painter(tester).center;
      final arm = start - center;
      final gesture = await tester.startGesture(start);
      var time = Duration.zero;
      for (var step = 1; step <= 5; step++) {
        time += const Duration(milliseconds: 16);
        await gesture.moveTo(
          center +
              Offset.fromDirection(
                arm.direction + step * _degree,
                arm.distance,
              ),
          timeStamp: time,
        );
      }
      for (var i = 0; i < 3; i++) {
        time += const Duration(milliseconds: 200);
        await gesture.moveTo(
          center +
              Offset.fromDirection(arm.direction + 5 * _degree, arm.distance),
          timeStamp: time,
        );
      }
      await gesture.up(timeStamp: time);
      await tester.pumpAndSettle();
      expect(painter(tester).rotation, closeTo(before + 5 * _degree, 1e-6));
      expect(session.picks, isEmpty);
      expect(label(tester), isNot('R29'));

      // A pointer that stays within the tap slop is still a tap.
      final position = await reveal(tester, 'R29');
      final tap = await tester.startGesture(position);
      await tap.moveBy(const Offset(3, 3));
      await tap.up();
      await tester.pumpAndSettle();
      expect(session.picks, hasLength(1));
    });

    testWidgets('swatch, white and black keep the opacity', (tester) async {
      setScreen(tester, const Size(1280, 800));
      final session = await open(tester, initial: const SRGBColor(0x80C85028));
      await tapCode(tester, 'R29');
      await tester.tap(find.byKey(const ValueKey('amaze-color-white')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('amaze-color-black')));
      await tester.pumpAndSettle();
      expect(session.picks.map((c) => c.value), [
        0x80EF0047,
        0x80FFFFFF,
        0x80000000,
      ]);
      expect(find.byKey(_ring), findsOneWidget);
    });

    testWidgets('a tapped duplicate keeps its own code', (tester) async {
      setScreen(tester, const Size(1280, 800));
      final session = await open(tester);
      await tapCode(tester, '110');
      expect(label(tester), '110');
      expect(find.text('Special Black'), findsOneWidget);
      expect(painter(tester).selected, {'110'});
      expect(session.picks, [SRGBColor.black]);
      // The other code with the same color changes the label only.
      await tapCode(tester, '100');
      expect(label(tester), '100');
      expect(session.picks, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await open(tester, initial: SRGBColor.black);
      expect(label(tester), '100 / 110');
      expect(painter(tester).selected, {'100', '110'});
      // A color that is no marker shows its hex value.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await open(tester, initial: const SRGBColor(0xFF123456));
      expect(label(tester), '#123456');
    });
  });

  group('close', () {
    testWidgets('Escape reports the last applied color once', (tester) async {
      setScreen(tester, const Size(1280, 800));
      final session = await open(tester);
      await tapCode(tester, 'R29');
      await tapCode(tester, 'B29');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(_ring), findsNothing);
      expect(session.closed, [palette.byCode('B29')!.color]);
      expect(session.eyedroppers, 0);
    });

    testWidgets('a pointer on the canvas closes without a color', (
      tester,
    ) async {
      setScreen(tester, const Size(1280, 800));
      final session = await open(tester);
      final gesture = await tester.startGesture(canvasPoint(tester));
      await tester.pumpAndSettle();
      // It closes when the pointer goes down, not when it comes up.
      expect(find.byKey(_ring), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(session.closed, [null]);
      expect(session.picks, isEmpty);
    });

    testWidgets('a tap on the tool wheel center closes', (tester) async {
      setScreen(tester, const Size(1280, 800));
      final session = await open(tester);
      await tester.tapAt(painter(tester).center);
      await tester.pumpAndSettle();
      expect(find.byKey(_ring), findsNothing);
      expect(session.closed, [null]);
    });

    testWidgets('the eyedropper closes, then asks for a sample', (
      tester,
    ) async {
      setScreen(tester, const Size(1280, 800));
      final session = await open(tester);
      await tapCode(tester, 'R29');
      await tester.tap(find.byKey(const ValueKey('amaze-color-eyedropper')));
      await tester.pumpAndSettle();
      expect(find.byKey(_ring), findsNothing);
      expect(session.closed.map((c) => c?.value), [0xFFEF0047]);
      expect(session.eyedroppers, 1);
    });

    testWidgets('the empty disc around the tool wheel does nothing', (
      tester,
    ) async {
      setScreen(tester, const Size(1280, 800));
      final session = await open(tester);
      final state = painter(tester);
      // Left of the tool wheel, between it and the inner arc.
      await tester.tapAt(state.center - Offset(state.holeRadius + 12, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(_ring), findsOneWidget);
      expect(session.picks, isEmpty);
      expect(session.closed, isEmpty);
    });
  });

  testWidgets('missing data hides COPIC and opens HSL', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await open(tester, noData: true);
    expect(find.byKey(const ValueKey('amaze-color-mode-copic')), findsNothing);
    expect(find.byKey(const ValueKey('amaze-color-mode-hsl')), findsOneWidget);
    expect(find.byKey(const ValueKey('amaze-color-mode-rgb')), findsOneWidget);
    expect(find.byKey(_ring), findsNothing);
    expect(
      find.byKey(const ValueKey(('amaze-color-field', 'hue'))),
      findsOneWidget,
    );
  });

  testWidgets('the old panel, search box and buttons are gone', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await open(tester);
    for (final key in [
      'amaze-color-panel',
      'amaze-color-search',
      'amaze-color-done',
      'amaze-color-cancel',
      'amaze-color-strip',
      'amaze-color-family-R',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    expect(find.byType(TextField), findsNothing);
  });

  group('placement', () {
    const controls = [
      'amaze-color-mode-copic',
      'amaze-color-mode-hsl',
      'amaze-color-mode-rgb',
      'amaze-color-more',
      'amaze-color-eyedropper',
      'amaze-color-white',
      'amaze-color-black',
      'amaze-color-label',
    ];

    void expectOnScreen(WidgetTester tester, Size screen, String reason) {
      final rects = {
        for (final key in controls)
          key: tester.getRect(find.byKey(ValueKey(key))),
      };
      final bounds = Offset.zero & screen;
      for (final MapEntry(:key, value: rect) in rects.entries) {
        expect(
          bounds.contains(rect.topLeft) &&
              rect.right <= screen.width &&
              rect.bottom <= screen.height,
          isTrue,
          reason: '$key at $reason: $rect',
        );
        for (final other in rects.entries) {
          if (other.key == key) continue;
          expect(
            rect.deflate(1).overlaps(other.value.deflate(1)),
            isFalse,
            reason: '$key overlaps ${other.key} at $reason',
          );
        }
      }
    }

    testWidgets('in the middle the modes are above the tool wheel', (
      tester,
    ) async {
      setScreen(tester, const Size(1280, 800));
      await open(tester);
      final state = painter(tester);
      Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
      final copic = rect('amaze-color-mode-copic');
      final hsl = rect('amaze-color-mode-hsl');
      final rgb = rect('amaze-color-mode-rgb');
      // COPIC · HSL · RGB from left to right, above the tool wheel.
      expect(copic.center.dx, lessThan(hsl.center.dx));
      expect(hsl.center.dx, lessThan(rgb.center.dx));
      for (final mode in [copic, hsl, rgb]) {
        expect(mode.bottom, lessThan(state.center.dy - state.holeRadius));
      }
      // Black and white chips are up and to the right.
      for (final key in ['amaze-color-black', 'amaze-color-white']) {
        expect(rect(key).center.dx, greaterThan(rgb.center.dx));
        expect(rect(key).center.dy, lessThan(state.center.dy));
      }
      // The eyedropper is to the right of the tool wheel.
      final eyedropper = rect('amaze-color-eyedropper');
      expect(eyedropper.left, greaterThan(state.center.dx + state.holeRadius));
      expect(eyedropper.center.dy, closeTo(state.center.dy, 1));
      // Every control is on the disc, inside the inner arc.
      for (final key in controls) {
        for (final corner in [
          rect(key).topLeft,
          rect(key).topRight,
          rect(key).bottomLeft,
          rect(key).bottomRight,
        ]) {
          final distance = (corner - state.center).distance;
          expect(distance, greaterThan(state.holeRadius), reason: key);
          expect(distance, lessThan(state.geometry.discInner), reason: key);
        }
      }
    });

    for (final screen in [const Size(1280, 800), const Size(800, 1280)]) {
      testWidgets('controls stay on screen at every position on $screen', (
        tester,
      ) async {
        setScreen(tester, screen);
        for (final center in _positions(screen, 160)) {
          await open(tester, center: center);
          expectOnScreen(tester, screen, '$center');
          expect(painter(tester).center, center);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final screen in [const Size(1280, 800), const Size(800, 1280)]) {
      testWidgets('controls clear a small tool wheel on $screen', (
        tester,
      ) async {
        setScreen(tester, screen);
        for (final radius in _smallRadii) {
          for (final center in _positions(screen, radius)) {
            final reason = 'radius $radius at $center';
            await open(tester, center: center, innerRadius: radius);
            expectOnScreen(tester, screen, reason);
            expect(painter(tester).holeRadius, radius);
            for (final key in controls) {
              final rect = tester.getRect(find.byKey(ValueKey(key)));
              final nearest = Offset(
                center.dx.clamp(rect.left, rect.right),
                center.dy.clamp(rect.top, rect.bottom),
              );
              expect(
                (nearest - center).distance,
                greaterThan(radius),
                reason: '$key over the tool wheel, $reason',
              );
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
          }
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('without a center the wheel is in the middle of the screen', (
      tester,
    ) async {
      setScreen(tester, const Size(1280, 800));
      await open(tester, center: null);
      expect(painter(tester).center, const Offset(640, 400));
      expect(painter(tester).holeRadius, 0);
      expect(
        tester.getCenter(find.byKey(const ValueKey('amaze-color-center'))),
        const Offset(640, 400),
      );
    });

    testWidgets('rotating and resizing while open lays out again', (
      tester,
    ) async {
      setScreen(tester, const Size(1280, 800));
      await open(tester, center: null);
      for (final screen in [
        const Size(800, 1280),
        const Size(1440, 900),
        const Size(1280, 800),
      ]) {
        tester.view.physicalSize = screen;
        await tester.pumpAndSettle();
        final state = painter(tester);
        expect(state.center, screen.center(Offset.zero));
        expectOnScreen(tester, screen, 'resized to $screen');
        expect(
          state.geometry.allReachable(center: state.center, screen: screen),
          isTrue,
          reason: '$screen',
        );
      }
      expect(tester.takeException(), isNull);
    });
  });
}
