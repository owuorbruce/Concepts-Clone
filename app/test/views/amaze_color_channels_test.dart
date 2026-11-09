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

const _done = ValueKey('amaze-color-done');
const _channels = ValueKey('amaze-color-channels');

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
  });

  /// An app with a button that opens the picker.
  (Widget, Future<AmazeColorResult?>? Function()) harness({
    required MarkerPalette? data,
    required SRGBColor initial,
  }) {
    Future<AmazeColorResult?>? result;
    final app = MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              key: const ValueKey('open-color'),
              onPressed: () {
                result = showAmazeColorWheel(
                  context,
                  center: const Offset(640, 400),
                  innerRadius: 80,
                  initial: initial,
                  paletteLoader: () async => data,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    return (app, () => result);
  }

  Future<Future<AmazeColorResult?>? Function()> open(
    WidgetTester tester, {
    bool noData = false,
    SRGBColor initial = const SRGBColor(0xFFC85028),
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (app, result) = harness(
      data: noData ? null : palette,
      initial: initial,
    );
    await tester.pumpWidget(app);
    await tester.tap(find.byKey(const ValueKey('open-color')));
    await tester.pumpAndSettle();
    return result;
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

  Future<SRGBColor> done(
    WidgetTester tester,
    Future<AmazeColorResult?>? Function() result,
  ) async {
    await tester.tap(find.byKey(_done));
    await tester.pumpAndSettle();
    return (await result() as AmazePickedColor).color;
  }

  testWidgets('dragging the hue handle changes hue and keeps S and L', (
    tester,
  ) async {
    final result = await open(tester, noData: true);
    final before = rgbToHsl(const SRGBColor(0xFFC85028));
    final state = painter(tester);
    final layout = state.layout;
    final origin = tester.getTopLeft(find.byKey(_channels));
    final start = origin + layout.handleOf(ColorChannel.hue, before.hue);
    final target = before.hue + 120;
    final gesture = await tester.startGesture(start);
    for (var i = 1; i <= 12; i++) {
      final angle = layout.angleOf(ColorChannel.hue, before.hue + 10.0 * i);
      await gesture.moveTo(
        origin +
            layout.center +
            Offset(math.cos(angle), math.sin(angle)) *
                layout.radiusOf(ColorChannel.hue),
      );
      await tester.pump();
      // The preview follows the drag live.
      expect(painter(tester).values[ColorChannel.hue], isNot(before.hue));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final values = painter(tester).values;
    expect(values[ColorChannel.hue], closeTo(target, 1));
    expect(values[ColorChannel.saturation], closeTo(before.saturation, 1e-9));
    expect(values[ColorChannel.lightness], closeTo(before.lightness, 1e-9));
    expect(fieldText(tester, ColorChannel.hue), '${target.round()}');

    // Picking works without marker data.
    final picked = rgbToHsl(await done(tester, result));
    expect(picked.hue, closeTo(target, 1));
    expect(picked.saturation, closeTo(before.saturation, 1));
    expect(picked.lightness, closeTo(before.lightness, 1));
  });

  testWidgets('a typed R of 255 applies on Enter', (tester) async {
    final result = await open(tester);
    await selectMode(tester, AmazeColorMode.rgb);
    await tester.enterText(find.byKey(_field(ColorChannel.red)), '255');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(painter(tester).color.value, 0xFFFF5028);
    expect((await done(tester, result)).value, 0xFFFF5028);
  });

  testWidgets('a typed value applies when the field loses focus', (
    tester,
  ) async {
    await open(tester);
    await selectMode(tester, AmazeColorMode.rgb);
    await tester.enterText(find.byKey(_field(ColorChannel.green)), '10');
    await tester.tap(find.byKey(_field(ColorChannel.blue)));
    await tester.pumpAndSettle();
    expect(painter(tester).color.value, 0xFFC80A28);
  });

  testWidgets('R of 300 shows an error and does not apply', (tester) async {
    final result = await open(tester);
    await selectMode(tester, AmazeColorMode.rgb);
    await tester.enterText(find.byKey(_field(ColorChannel.red)), '300');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.text('Enter a value from 0 to 255'), findsOneWidget);
    expect(painter(tester).color.value, 0xFFC85028);
    expect((await done(tester, result)).value, 0xFFC85028);
  });

  testWidgets('Escape in a field reverts it and keeps the picker open', (
    tester,
  ) async {
    final result = await open(tester);
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
    expect(find.byKey(_done), findsOneWidget);
    // Leaving the reverted field applies nothing.
    await tester.tap(find.byKey(_field(ColorChannel.green)));
    await tester.pumpAndSettle();
    expect((await done(tester, result)).value, 0xFFC85028);
  });

  testWidgets('the alpha field changes only alpha', (tester) async {
    final result = await open(tester, noData: true);
    await tester.enterText(find.byKey(_field(ColorChannel.alpha)), '50');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect((await done(tester, result)).value, 0x80C85028);
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
      final result = await open(tester, noData: true, initial: initial);
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
      final picked = await done(tester, result);
      for (final (a, b) in [
        (picked.r, initial.r),
        (picked.g, initial.g),
        (picked.b, initial.b),
        (picked.a, initial.a),
      ]) {
        expect((a - b).abs(), lessThanOrEqualTo(1), reason: '$initial');
      }
    }
  });

  testWidgets('the last mode is remembered', (tester) async {
    var result = await open(tester);
    await selectMode(tester, AmazeColorMode.rgb);
    await done(tester, result);
    expect(
      (await SharedPreferences.getInstance()).getString(
        kAmazeColorModePreference,
      ),
      'rgb',
    );

    result = await open(tester);
    final rgb = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('amaze-color-mode-rgb')),
    );
    expect(rgb.selected, isTrue);
    expect(find.byKey(_field(ColorChannel.red)), findsOneWidget);
    await done(tester, result);
  });
}
