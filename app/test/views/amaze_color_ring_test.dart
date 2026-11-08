import 'package:butterfly/models/marker_palette.dart';
import 'package:butterfly/services/marker_palette_loader.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/views/amaze/color/color_wheel_picker.dart';
import 'package:butterfly/views/amaze/color/marker_ring.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MarkerPalette palette;

  setUpAll(() async {
    palette = (await loadMarkerPalette())!;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('all 358 swatches remain distinct and hittable under pan and zoom', () {
    final geometry = MarkerRingGeometry(palette);
    expect(geometry.swatches.length, 358);
    for (final viewport in [const Size(1280, 800), const Size(800, 1280)]) {
      for (final swatch in geometry.swatches) {
        // A family chip or search brings the swatch to this viewport center.
        final pan = -swatch.center;
        final point = geometry.transformedCenter(
          swatch.marker.code,
          viewport: viewport,
          pan: pan,
          zoom: 1,
        );
        expect(point, viewport.center(Offset.zero));
        expect(swatch.bounds.shortestSide, greaterThanOrEqualTo(32));
        expect(
          geometry
              .hitTestTransformed(point, viewport: viewport, pan: pan, zoom: 1)
              ?.code,
          swatch.marker.code,
          reason: 'hit test for ${swatch.marker.code} at $viewport',
        );
        final otherPoint = geometry.transformedCenter(
          swatch.marker.code,
          viewport: viewport,
          pan: const Offset(37, -25),
          zoom: 2,
        );
        expect(
          geometry
              .hitTestTransformed(
                otherPoint,
                viewport: viewport,
                pan: const Offset(37, -25),
                zoom: 2,
              )
              ?.code,
          swatch.marker.code,
        );
      }
    }
  });

  Future<(Widget, Future<AmazeColorResult?>? Function())> harness({
    required MarkerPalette? data,
    SRGBColor initial = SRGBColor.white,
    Offset center = const Offset(640, 400),
  }) async {
    Future<AmazeColorResult?>? result;
    final app = MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
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
            );
          },
        ),
      ),
    );
    return (app, () => result);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const ValueKey('amaze-color-search')),
      query,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('search previews R29, then Done commits only its color', (
    tester,
  ) async {
    final (app, result) = await harness(data: palette);
    await tester.pumpWidget(app);
    await tester.tap(find.byKey(const ValueKey('open-color')));
    await tester.pumpAndSettle();
    await search(tester, 'r29');
    expect(find.text('R29'), findsOneWidget);
    expect(find.text('Lipstick Red'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('amaze-color-done')));
    await tester.pumpAndSettle();
    final picked = await result() as AmazePickedColor;
    expect(picked.color.value, 0xFFEF0047);
  });

  testWidgets('an exact duplicate code keeps the tapped marker identity', (
    tester,
  ) async {
    final (app, _) = await harness(data: palette, initial: SRGBColor.black);
    await tester.pumpWidget(app);
    await tester.tap(find.byKey(const ValueKey('open-color')));
    await tester.pumpAndSettle();
    expect(find.text('100 / 110'), findsOneWidget);
    await search(tester, '110');
    expect(find.text('110'), findsOneWidget);
    expect(find.text('100 / 110'), findsNothing);
  });

  testWidgets('preview and Cancel return null', (tester) async {
    final (app, result) = await harness(data: palette);
    await tester.pumpWidget(app);
    await tester.tap(find.byKey(const ValueKey('open-color')));
    await tester.pumpAndSettle();
    await search(tester, 'R29');
    await tester.tap(find.byKey(const ValueKey('amaze-color-cancel')));
    await tester.pumpAndSettle();
    expect(await result(), isNull);
  });

  testWidgets('missing data hides COPIC and opens HSL', (tester) async {
    final (app, _) = await harness(data: null);
    await tester.pumpWidget(app);
    await tester.tap(find.byKey(const ValueKey('open-color')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('amaze-color-mode-copic')), findsNothing);
    final hsl = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('amaze-color-mode-hsl')),
    );
    expect(hsl.selected, isTrue);
  });

  testWidgets('information shows trademark and MIT attribution', (
    tester,
  ) async {
    final (app, _) = await harness(data: palette);
    await tester.pumpWidget(app);
    await tester.tap(find.byKey(const ValueKey('open-color')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('amaze-color-info')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Too Corporation'), findsOneWidget);
    expect(find.textContaining('meodai/copic-colors (MIT)'), findsOneWidget);
  });

  testWidgets('controls stay on screen at corners and after resize', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final center in [
      const Offset(0, 0),
      const Offset(1280, 0),
      const Offset(0, 800),
      const Offset(1280, 800),
      const Offset(640, 0),
      const Offset(640, 800),
      const Offset(0, 400),
      const Offset(1280, 400),
    ]) {
      final (app, _) = await harness(data: palette, center: center);
      await tester.pumpWidget(app);
      await tester.tap(find.byKey(const ValueKey('open-color')));
      await tester.pumpAndSettle();
      for (final key in [
        'amaze-color-done',
        'amaze-color-cancel',
        'amaze-color-mode-copic',
        'amaze-color-search',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(1280));
        expect(rect.bottom, lessThanOrEqualTo(800));
      }
      tester.view.physicalSize = const Size(800, 1280);
      await tester.pumpAndSettle();
      final done = tester.getRect(
        find.byKey(const ValueKey('amaze-color-done')),
      );
      expect(done.right, lessThanOrEqualTo(800));
      expect(done.bottom, lessThanOrEqualTo(1280));
      await tester.tap(find.byKey(const ValueKey('amaze-color-cancel')));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
    }
  });
}
