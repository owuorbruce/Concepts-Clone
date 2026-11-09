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
const _done = ValueKey('amaze-color-done');
const _cancel = ValueKey('amaze-color-cancel');
const _code = ValueKey('amaze-color-code');

Matcher _near(Offset expected) => predicate<Offset>(
  (offset) => (offset - expected).distance < 1e-6,
  'within 1e-6 of $expected',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MarkerPalette palette;

  setUpAll(() async {
    palette = (await loadMarkerPalette())!;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ring geometry', () {
    test('358 swatches of at least 32 px with readable codes, no overlap', () {
      final geometry = MarkerRingGeometry(palette, innerRadius: 80);
      expect(geometry.swatches, hasLength(358));
      final codes = geometry.swatches.map((s) => s.marker.code).toSet();
      expect(codes, hasLength(358));
      expect(kMarkerLabelSize * kMarkerFocusZoom, greaterThanOrEqualTo(10));
      for (var i = 0; i < geometry.swatches.length; i++) {
        final a = geometry.swatches[i];
        expect(
          a.bounds.shortestSide * kMarkerFocusZoom,
          greaterThanOrEqualTo(32),
        );
        // Every swatch lies outside the wheel.
        expect(a.center.distance - 27, greaterThan(geometry.innerRadius));
        for (var j = i + 1; j < geometry.swatches.length; j++) {
          final b = geometry.swatches[j];
          expect(
            a.bounds.overlaps(b.bounds),
            isFalse,
            reason: '${a.marker.code} and ${b.marker.code} overlap',
          );
        }
      }
    });

    test('bars run from dark inside to light outside, ordered by family', () {
      final geometry = MarkerRingGeometry(palette, innerRadius: 80);
      for (final family in ['B', 'R', 'YG', 'E']) {
        final bar =
            geometry.swatches.where((s) => s.marker.family == family).toList()
              ..sort((a, b) => a.center.distance.compareTo(b.center.distance));
        double luminance(MarkerColor m) =>
            0.2126 * m.color.r + 0.7152 * m.color.g + 0.0722 * m.color.b;
        for (var i = 1; i < bar.length; i++) {
          expect(
            luminance(bar[i].marker),
            greaterThanOrEqualTo(luminance(bar[i - 1].marker)),
          );
        }
      }
      // Gray and fluorescent families sit inside the hue bars.
      final inner = geometry.swatches
          .where((s) => s.marker.family.startsWith(RegExp('[CNTWAF]')))
          .map((s) => s.center.distance)
          .reduce(math.max);
      final bars = geometry.swatches
          .where((s) => !s.marker.family.startsWith(RegExp('[CNTWAF]')))
          .map((s) => s.center.distance)
          .reduce(math.min);
      expect(inner, lessThan(bars));
    });

    test('every swatch hit-tests to itself under pan and zoom', () {
      final geometry = MarkerRingGeometry(palette, innerRadius: 80);
      for (final viewport in [const Size(1280, 800), const Size(800, 1280)]) {
        for (final swatch in geometry.swatches) {
          final code = swatch.marker.code;
          // A family chip or search brings the swatch to the viewport center.
          final pan = -swatch.center;
          final point = geometry.transformedCenter(
            code,
            viewport: viewport,
            pan: pan,
            zoom: kMarkerFocusZoom,
          );
          expect(point, _near(viewport.center(Offset.zero)));
          expect(
            geometry
                .hitTestTransformed(
                  point,
                  viewport: viewport,
                  pan: pan,
                  zoom: kMarkerFocusZoom,
                )
                ?.code,
            code,
          );
          for (final (otherPan, zoom) in [
            (const Offset(37, -25), 2.0),
            (const Offset(-410, 260), 0.5),
          ]) {
            final other = geometry.transformedCenter(
              code,
              viewport: viewport,
              pan: otherPan,
              zoom: zoom,
            );
            expect(
              geometry
                  .hitTestTransformed(
                    other,
                    viewport: viewport,
                    pan: otherPan,
                    zoom: zoom,
                  )
                  ?.code,
              code,
              reason: '$code at $viewport, zoom $zoom',
            );
          }
        }
      }
    });
  });

  /// An app with a button that opens the picker.
  (Widget, Future<AmazeColorResult?>? Function()) harness({
    required MarkerPalette? data,
    SRGBColor initial = SRGBColor.white,
    Offset center = const Offset(640, 400),
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
                  center: center,
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

  void setScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<Future<AmazeColorResult?>? Function()> open(
    WidgetTester tester, {
    MarkerPalette? data,
    bool noData = false,
    SRGBColor initial = SRGBColor.white,
    Offset center = const Offset(640, 400),
  }) async {
    final (app, result) = harness(
      data: noData ? null : (data ?? palette),
      initial: initial,
      center: center,
    );
    await tester.pumpWidget(app);
    await tester.tap(find.byKey(const ValueKey('open-color')));
    await tester.pumpAndSettle();
    return result;
  }

  MarkerRingPainter painter(WidgetTester tester) {
    final paint = find.descendant(
      of: find.byKey(_ring),
      matching: find.byType(CustomPaint),
    );
    return tester.widget<CustomPaint>(paint.first).painter!
        as MarkerRingPainter;
  }

  /// The global position of [code] with the ring's current pan and zoom.
  Offset swatchOnScreen(WidgetTester tester, String code) {
    final ring = tester.getRect(find.byKey(_ring));
    final state = painter(tester);
    return ring.topLeft +
        state.geometry.transformedCenter(
          code,
          viewport: ring.size,
          pan: state.pan,
          zoom: state.zoom,
        );
  }

  String previewCode(WidgetTester tester) {
    return tester.widget<Text>(find.byKey(_code)).data!;
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const ValueKey('amaze-color-search')),
      query,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  for (final screen in [const Size(1280, 800), const Size(800, 1280)]) {
    testWidgets('family chip, zoom, pan and tap pick R29 on $screen', (
      tester,
    ) async {
      setScreen(tester, screen);
      final result = await open(tester, center: screen.center(Offset.zero));
      final ring = tester.getRect(find.byKey(_ring));

      // The chip brings the R bar into view at a tappable zoom.
      final chip = find.byKey(const ValueKey('amaze-color-family-R'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(painter(tester).zoom, kMarkerFocusZoom);

      // Ctrl + scroll zooms around the pointer.
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(ring.center));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final zoom = painter(tester).zoom;
      expect(zoom, greaterThan(kMarkerFocusZoom));

      // Dragging pans R29 to the middle of the ring.
      final target = swatchOnScreen(tester, 'R29');
      final gesture = await tester.startGesture(ring.center);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(ring.center + (ring.center - target) * (i / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final onScreen = swatchOnScreen(tester, 'R29');
      expect((onScreen - ring.center).distance, lessThan(1));
      final swatch = painter(tester).geometry.byCode('R29')!.bounds;
      expect(swatch.shortestSide * painter(tester).zoom, greaterThan(32));
      expect(painter(tester).zoom, greaterThanOrEqualTo(0.8));

      await tester.tapAt(onScreen);
      await tester.pumpAndSettle();
      expect(previewCode(tester), 'R29');
      expect(find.text('Lipstick Red'), findsOneWidget);
      expect(painter(tester).selectedRgb, 0xEF0047);
      await tester.tap(find.byKey(_done));
      await tester.pumpAndSettle();
      final picked = await result() as AmazePickedColor;
      expect(picked.color.value, 0xFFEF0047);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a double tap resets the view, a single tap does not', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await open(tester);
    final chip = find.byKey(const ValueKey('amaze-color-family-B'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(painter(tester).zoom, kMarkerFocusZoom);
    final corner =
        tester.getRect(find.byKey(_ring)).topLeft + const Offset(4, 4);
    await tester.tapAt(corner);
    await tester.pumpAndSettle();
    expect(painter(tester).zoom, kMarkerFocusZoom);
    await tester.tapAt(corner);
    await tester.pumpAndSettle();
    expect(painter(tester).zoom, lessThan(kMarkerFocusZoom));
    expect(painter(tester).pan, Offset.zero);
  });

  testWidgets('a tapped duplicate keeps its own code', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await open(tester, initial: SRGBColor.black);
    expect(previewCode(tester), '100 / 110');

    final chip = find.byKey(const ValueKey('amaze-color-family-A'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final position = swatchOnScreen(tester, '110');
    expect(tester.getRect(find.byKey(_ring)).contains(position), isTrue);
    await tester.tapAt(position);
    await tester.pumpAndSettle();
    expect(previewCode(tester), '110');
    expect(find.text('Special Black'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search highlights matches and Enter previews the first', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('amaze-color-search')),
      'r29',
    );
    await tester.pumpAndSettle();
    expect(painter(tester).dimUnmatched, isTrue);
    expect(painter(tester).matches, contains('R29'));
    expect(painter(tester).matches, isNot(contains('B29')));

    await search(tester, 'blender');
    expect(painter(tester).matches, {'0'});
    expect(previewCode(tester), '0');
    final ring = tester.getRect(find.byKey(_ring));
    expect(ring.contains(swatchOnScreen(tester, '0')), isTrue);

    await search(tester, 'R29');
    expect(previewCode(tester), 'R29');
    expect((swatchOnScreen(tester, 'R29') - ring.center).distance, lessThan(1));
    expect(tester.takeException(), isNull);
  });

  group('commit rule', () {
    testWidgets('Done returns the previewed color', (tester) async {
      setScreen(tester, const Size(1280, 800));
      final result = await open(tester);
      await search(tester, 'R29');
      await tester.tap(find.byKey(_done));
      await tester.pumpAndSettle();
      expect((await result() as AmazePickedColor).color.value, 0xFFEF0047);
    });

    testWidgets('Cancel returns null', (tester) async {
      setScreen(tester, const Size(1280, 800));
      final result = await open(tester);
      await search(tester, 'R29');
      await tester.tap(find.byKey(_cancel));
      await tester.pumpAndSettle();
      expect(await result(), isNull);
    });

    testWidgets('Escape returns null', (tester) async {
      setScreen(tester, const Size(1280, 800));
      final result = await open(tester);
      await search(tester, 'R29');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(_done), findsNothing);
      expect(await result(), isNull);
    });

    testWidgets('tapping outside returns null', (tester) async {
      setScreen(tester, const Size(1280, 800));
      final result = await open(tester);
      await search(tester, 'R29');
      final panel = tester.getRect(
        find.byKey(const ValueKey('amaze-color-panel')),
      );
      final outside = panel.left > 4
          ? Offset(panel.left / 2, 400)
          : Offset((panel.right + 1280) / 2, 400);
      expect(panel.contains(outside), isFalse);
      await tester.tapAt(outside);
      await tester.pumpAndSettle();
      expect(find.byKey(_done), findsNothing);
      expect(await result(), isNull);
    });
  });

  testWidgets('missing data hides COPIC and opens HSL', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await open(tester, noData: true);
    expect(find.byKey(const ValueKey('amaze-color-mode-copic')), findsNothing);
    final hsl = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('amaze-color-mode-hsl')),
    );
    expect(hsl.selected, isTrue);
    expect(find.byKey(_ring), findsNothing);
  });

  testWidgets('information shows trademark and MIT attribution', (
    tester,
  ) async {
    setScreen(tester, const Size(1280, 800));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('amaze-color-info')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'COPIC is a trademark of Too Corporation. aMaze is not affiliated '
        'with or endorsed by Too Corporation. Digital colors are '
        'approximations.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Color data: meodai/copic-colors (MIT).'),
      findsOneWidget,
    );
  });

  group('placement', () {
    const controls = [
      'amaze-color-done',
      'amaze-color-cancel',
      'amaze-color-mode-copic',
      'amaze-color-mode-hsl',
      'amaze-color-mode-rgb',
      'amaze-color-search',
    ];

    void expectOnScreen(WidgetTester tester, Size screen, String reason) {
      for (final key in controls) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(
          rect.left >= 0 &&
              rect.top >= 0 &&
              rect.right <= screen.width &&
              rect.bottom <= screen.height,
          isTrue,
          reason: '$key at $reason: $rect',
        );
      }
    }

    for (final screen in [const Size(1280, 800), const Size(800, 1280)]) {
      testWidgets('controls stay on screen at every edge of $screen', (
        tester,
      ) async {
        setScreen(tester, screen);
        final w = screen.width;
        final h = screen.height;
        for (final center in [
          Offset.zero,
          Offset(w, 0),
          Offset(0, h),
          Offset(w, h),
          Offset(w / 2, 0),
          Offset(w / 2, h),
          Offset(0, h / 2),
          Offset(w, h / 2),
        ]) {
          await open(tester, center: center);
          expectOnScreen(tester, screen, '$center');
          await tester.tap(find.byKey(_cancel));
          await tester.pumpAndSettle();
        }
      });
    }

    testWidgets('rotating and resizing while open keeps controls on screen', (
      tester,
    ) async {
      setScreen(tester, const Size(1280, 800));
      await open(tester, center: const Offset(1280, 800));
      for (final screen in [
        const Size(800, 1280),
        const Size(1024, 700),
        const Size(1280, 800),
      ]) {
        tester.view.physicalSize = screen;
        await tester.pumpAndSettle();
        expectOnScreen(tester, screen, 'resized to $screen');
      }
      expect(tester.takeException(), isNull);
    });
  });
}
