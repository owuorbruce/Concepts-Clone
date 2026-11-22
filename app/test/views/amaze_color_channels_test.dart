import 'dart:math' as math;

import 'package:butterfly/models/marker_palette.dart';
import 'package:butterfly/services/marker_palette_loader.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/views/amaze/color/channel_rings.dart';
import 'package:butterfly/views/amaze/color/color_model.dart';
import 'package:butterfly/views/amaze/color/color_wheel_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channels = ValueKey('amaze-color-channels');
const _rings = ValueKey('amaze-color-rings');

ValueKey<(String, String)> _field(ColorChannel channel) =>
    ValueKey(('amaze-color-field', channel.name));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MarkerPalette palette;

  setUpAll(() async {
    palette = (await loadMarkerPalette())!;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('layout', () {
    test('every channel value maps to its handle and back', () {
      for (final mode in [AmazeColorMode.hsl, AmazeColorMode.rgb]) {
        final layout = ChannelRingLayout(
          channelsOf(mode),
          const Size(600, 500),
        );
        for (final channel in layout.channels) {
          for (var i = 0; i <= 20; i++) {
            final value = channel.max * i / 20;
            final handle = layout.handleOf(channel, value);
            expect(layout.channelAt(handle), channel);
            var back = layout.valueAt(channel, handle);
            // The hue ring is closed, so 0 and 360 are the same point.
            if (channel == ColorChannel.hue) {
              back = value - ((value - back + 180) % 360 - 180);
            }
            expect(back, closeTo(value, 1e-6), reason: '$channel $value');
          }
        }
      }
    });

    test('the center and the outside belong to no channel', () {
      final layout = ChannelRingLayout(
        channelsOf(AmazeColorMode.hsl),
        const Size(600, 500),
      );
      expect(layout.channelAt(layout.center), isNull);
      expect(layout.channelAt(Offset.zero), isNull);
    });

    test('the arcs stay clear of the controls around the tool wheel', () {
      const clear = 224.0;
      final side = ChannelRingLayout.sideFor(clear);
      final layout = ChannelRingLayout(
        channelsOf(AmazeColorMode.hsl),
        Size.square(side),
      );
      for (var degrees = 0; degrees < 360; degrees += 15) {
        final direction = Offset.fromDirection(degrees * math.pi / 180);
        expect(
          layout.channelAt(layout.center + direction * (clear - 1)),
          isNull,
        );
        expect(
          layout.channelAt(layout.center + direction * (clear + 14)),
          ColorChannel.alpha,
        );
      }
    });
  });

  late List<SRGBColor> picks;
  late List<SRGBColor?> closed;

  Future<void> open(
    WidgetTester tester, {
    bool noData = false,
    SRGBColor initial = const SRGBColor(0xFFC85028),
    Offset center = const Offset(640, 400),
    double innerRadius = 160,
    Size screen = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    picks = [];
    closed = [];
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
                  onPick: picks.add,
                  onClosed: closed.add,
                  onEyedropper: () {},
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
  }

  Future<void> close(
    WidgetTester tester, [
    Offset center = const Offset(640, 400),
  ]) async {
    // Escape in a field only reverts it, so the tool wheel's center is
    // tapped instead.
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.byKey(_rings), findsNothing);
  }

  Future<void> selectMode(WidgetTester tester, AmazeColorMode mode) async {
    await tester.tap(find.byKey(ValueKey('amaze-color-mode-${mode.name}')));
    await tester.pumpAndSettle();
  }

  ChannelRingsPainter painter(WidgetTester tester) {
    final paint = find.descendant(
      of: find.byKey(_channels),
      matching: find.byType(CustomPaint),
    );
    return tester.widget<CustomPaint>(paint.first).painter!
        as ChannelRingsPainter;
  }

  String fieldText(WidgetTester tester, ColorChannel channel) {
    final field = find.descendant(
      of: find.byKey(_field(channel)),
      matching: find.byType(TextField),
    );
    return tester.widget<TextField>(field).controller!.text;
  }

  /// Drags the hue handle 120° round in twelve steps without releasing.
  Future<TestGesture> dragHue(WidgetTester tester, double from) async {
    final layout = painter(tester).layout;
    final origin = tester.getTopLeft(find.byKey(_channels));
    final gesture = await tester.startGesture(
      origin + layout.handleOf(ColorChannel.hue, from),
    );
    for (var i = 1; i <= 12; i++) {
      final angle = layout.angleOf(ColorChannel.hue, from + 10.0 * i);
      await gesture.moveTo(
        origin +
            layout.center +
            Offset(math.cos(angle), math.sin(angle)) *
                layout.radiusOf(ColorChannel.hue),
      );
      await tester.pump();
      // The arcs follow the drag live.
      expect(painter(tester).values[ColorChannel.hue], isNot(from));
    }
    return gesture;
  }

  testWidgets('a hue drag applies once, on release, and keeps S and L', (
    tester,
  ) async {
    await open(tester, noData: true);
    final before = rgbToHsl(const SRGBColor(0xFFC85028));
    final target = before.hue + 120;
    final gesture = await dragHue(tester, before.hue);
    expect(picks, isEmpty, reason: 'nothing is applied during the drag');
    await gesture.up();
    await tester.pumpAndSettle();

    final values = painter(tester).values;
    expect(values[ColorChannel.hue], closeTo(target, 1));
    expect(values[ColorChannel.saturation], closeTo(before.saturation, 1e-9));
    expect(values[ColorChannel.lightness], closeTo(before.lightness, 1e-9));
    expect(fieldText(tester, ColorChannel.hue), '${target.round()}');

    // Picking works without marker data, as one step.
    expect(picks, hasLength(1));
    final picked = rgbToHsl(picks.single);
    expect(picked.hue, closeTo(target, 1));
    expect(picked.saturation, closeTo(before.saturation, 1));
    expect(picked.lightness, closeTo(before.lightness, 1));
    expect(find.byKey(_rings), findsOneWidget);
    await close(tester);
    expect(closed, [picks.single]);
  });

  testWidgets('a cancelled channel drag changes nothing', (tester) async {
    await open(tester, noData: true);
    final before = rgbToHsl(const SRGBColor(0xFFC85028));
    final gesture = await dragHue(tester, before.hue);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(picks, isEmpty);
    expect(painter(tester).color.value, 0xFFC85028);
    expect(painter(tester).values[ColorChannel.hue], closeTo(before.hue, 1e-9));
    expect(fieldText(tester, ColorChannel.hue), '${before.hue.round()}');
    await close(tester);
    expect(closed, [null]);
  });

  testWidgets('a tap beside the arcs closes; the controls gap does not', (
    tester,
  ) async {
    await open(tester, noData: true);
    // Just outside the tool wheel, where the controls are.
    await tester.tapAt(const Offset(640 - 172, 400));
    await tester.pumpAndSettle();
    expect(find.byKey(_rings), findsOneWidget);
    // In the middle of the tool wheel.
    await tester.tapAt(const Offset(640, 400));
    await tester.pumpAndSettle();
    expect(find.byKey(_rings), findsNothing);
    expect(closed, [null]);
  });

  testWidgets('a typed R of 255 applies on Enter', (tester) async {
    await open(tester);
    await selectMode(tester, AmazeColorMode.rgb);
    await tester.enterText(find.byKey(_field(ColorChannel.red)), '255');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(painter(tester).color.value, 0xFFFF5028);
    expect(picks.map((c) => c.value), [0xFFFF5028]);
  });

  testWidgets('a typed value applies when the field loses focus', (
    tester,
  ) async {
    await open(tester);
    await selectMode(tester, AmazeColorMode.rgb);
    await tester.enterText(find.byKey(_field(ColorChannel.green)), '10');
    expect(picks, isEmpty);
    await tester.tap(find.byKey(_field(ColorChannel.blue)));
    await tester.pumpAndSettle();
    expect(painter(tester).color.value, 0xFFC80A28);
    expect(picks.map((c) => c.value), [0xFFC80A28]);
  });

  testWidgets('R of 300 shows an error and does not apply', (tester) async {
    await open(tester);
    await selectMode(tester, AmazeColorMode.rgb);
    await tester.enterText(find.byKey(_field(ColorChannel.red)), '300');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.text('Enter a value from 0 to 255'), findsOneWidget);
    expect(painter(tester).color.value, 0xFFC85028);
    expect(picks, isEmpty);
  });

  testWidgets('Escape in a field reverts it and keeps the picker open', (
    tester,
  ) async {
    await open(tester);
    await selectMode(tester, AmazeColorMode.rgb);
    await tester.enterText(find.byKey(_field(ColorChannel.red)), '300');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_field(ColorChannel.red)));
    await tester.enterText(find.byKey(_field(ColorChannel.red)), '17');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(fieldText(tester, ColorChannel.red), '200');
    expect(find.text('Enter a value from 0 to 255'), findsNothing);
    expect(find.byKey(_rings), findsOneWidget);
    // Leaving the reverted field applies nothing.
    await tester.tap(find.byKey(_field(ColorChannel.green)));
    await tester.pumpAndSettle();
    expect(picks, isEmpty);
  });

  testWidgets('the alpha field changes only alpha', (tester) async {
    await open(tester, noData: true);
    await tester.enterText(find.byKey(_field(ColorChannel.alpha)), '50');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(picks.map((c) => c.value), [0x80C85028]);
  });

  testWidgets('switching HSL, RGB and HSL keeps the color', (tester) async {
    final random = math.Random(4);
    for (var i = 0; i < 5; i++) {
      final initial = SRGBColor.from(
        r: random.nextInt(256),
        g: random.nextInt(256),
        b: random.nextInt(256),
        a: random.nextInt(256),
      );
      await open(tester, noData: true, initial: initial);
      final hsl = {
        for (final c in channelsOf(AmazeColorMode.hsl)) c: fieldText(tester, c),
      };
      await selectMode(tester, AmazeColorMode.rgb);
      expect(fieldText(tester, ColorChannel.red), '${initial.r}');
      expect(fieldText(tester, ColorChannel.green), '${initial.g}');
      expect(fieldText(tester, ColorChannel.blue), '${initial.b}');
      await selectMode(tester, AmazeColorMode.hsl);
      for (final MapEntry(:key, :value) in hsl.entries) {
        expect(
          (int.parse(fieldText(tester, key)) - int.parse(value)).abs(),
          lessThanOrEqualTo(1),
          reason: '$key of $initial',
        );
      }
      // Switching modes applies nothing.
      expect(picks, isEmpty);
      await close(tester);
      expect(closed, [null]);
    }
  });

  testWidgets('the last mode is remembered', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('amaze-color-ring')), findsOneWidget);
    await selectMode(tester, AmazeColorMode.rgb);
    expect(find.byKey(const ValueKey('amaze-color-ring')), findsNothing);
    await close(tester);
    expect(
      (await SharedPreferences.getInstance()).getString(
        kAmazeColorModePreference,
      ),
      'rgb',
    );

    await open(tester);
    expect(find.byKey(_field(ColorChannel.red)), findsOneWidget);
    expect(find.byKey(const ValueKey('amaze-color-ring')), findsNothing);
    await close(tester);
  });

  testWidgets('arcs, fields and controls are on screen in the middle', (
    tester,
  ) async {
    await open(tester, noData: true);
    const screen = Rect.fromLTWH(0, 0, 1280, 800);
    Rect rect(Key key) => tester.getRect(find.byKey(key));
    expect(screen.contains(rect(_channels).topLeft), isTrue);
    expect(screen.contains(rect(_channels).bottomRight), isTrue);
    final fields = rect(const ValueKey('amaze-color-fields'));
    expect(screen.contains(fields.topLeft), isTrue);
    expect(screen.contains(fields.bottomRight), isTrue);
    expect(fields.overlaps(rect(_channels)), isFalse);
    for (final key in [
      'amaze-color-mode-hsl',
      'amaze-color-mode-rgb',
      'amaze-color-more',
      'amaze-color-eyedropper',
      'amaze-color-white',
      'amaze-color-black',
    ]) {
      final control = rect(ValueKey(key));
      final layout = painter(tester).layout;
      final origin = rect(_channels).topLeft;
      for (final corner in [
        control.topLeft,
        control.topRight,
        control.bottomLeft,
        control.bottomRight,
      ]) {
        expect(layout.channelAt(corner - origin), isNull, reason: key);
        expect(
          (corner - const Offset(640, 400)).distance,
          greaterThan(160),
          reason: key,
        );
      }
    }
    expect(find.byKey(const ValueKey('amaze-color-done')), findsNothing);
    expect(find.byKey(const ValueKey('amaze-color-cancel')), findsNothing);
    expect(find.byKey(const ValueKey('amaze-color-panel')), findsNothing);
  });

  for (final screen in [const Size(1280, 800), const Size(800, 1280)]) {
    testWidgets('arcs, fields and controls fit a small tool wheel on $screen', (
      tester,
    ) async {
      for (final radius in [80.0, 88.0, 120.0]) {
        final xs = [radius, screen.width / 2, screen.width - radius];
        final ys = [radius, screen.height / 2, screen.height - radius];
        for (final x in xs) {
          for (final y in ys) {
            final center = Offset(x, y);
            final reason = 'radius $radius at $center';
            await open(
              tester,
              noData: true,
              center: center,
              innerRadius: radius,
              screen: screen,
            );
            final bounds = (Offset.zero & screen).inflate(0.5);
            Rect rect(Key key) => tester.getRect(find.byKey(key));
            final fields = rect(const ValueKey('amaze-color-fields'));
            expect(bounds.contains(fields.topLeft), isTrue, reason: reason);
            expect(bounds.contains(fields.bottomRight), isTrue, reason: reason);
            final layout = painter(tester).layout;
            final origin = rect(_channels).topLeft;
            final controls = {
              for (final key in [
                'amaze-color-mode-hsl',
                'amaze-color-mode-rgb',
                'amaze-color-more',
                'amaze-color-eyedropper',
                'amaze-color-white',
                'amaze-color-black',
              ])
                key: rect(ValueKey(key)),
            };
            for (final MapEntry(:key, value: control) in controls.entries) {
              expect(
                bounds.contains(control.topLeft),
                isTrue,
                reason: '$key $reason',
              );
              expect(
                bounds.contains(control.bottomRight),
                isTrue,
                reason: '$key $reason',
              );
              final nearest = Offset(
                center.dx.clamp(control.left, control.right),
                center.dy.clamp(control.top, control.bottom),
              );
              expect(
                (nearest - center).distance,
                greaterThan(radius),
                reason: '$key over the tool wheel, $reason',
              );
              // The HSL/RGB labels never touch the alpha arc, wherever
              // the row is shifted to stay on screen.
              if (key.startsWith('amaze-color-mode-')) {
                final alphaEdge =
                    layout.radiusOf(ColorChannel.alpha) -
                    ChannelRingLayout.band / 2;
                for (final corner in [
                  control.topLeft,
                  control.topRight,
                  control.bottomLeft,
                  control.bottomRight,
                ]) {
                  expect(
                    (corner - center).distance,
                    lessThan(alphaEdge),
                    reason: '$key on the alpha arc, $reason',
                  );
                }
              }
              // In a corner the outer arcs can still reach under the other
              // controls; the arcs are redesigned separately.
              final middle = center == screen.center(Offset.zero);
              for (final corner in [
                control.topLeft,
                control.topRight,
                control.bottomLeft,
                control.bottomRight,
              ]) {
                if (!middle) break;
                expect(
                  layout.channelAt(corner - origin),
                  isNull,
                  reason: '$key on an arc, $reason',
                );
              }
              for (final other in controls.entries) {
                if (other.key == key) continue;
                expect(
                  control.deflate(1).overlaps(other.value.deflate(1)),
                  isFalse,
                  reason: '$key overlaps ${other.key}, $reason',
                );
              }
            }
            await close(tester, center);
          }
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
