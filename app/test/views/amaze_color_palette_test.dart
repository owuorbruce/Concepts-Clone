import 'dart:convert';
import 'dart:io';

import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/models/marker_palette.dart';
import 'package:butterfly/services/marker_palette_loader.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/views/amaze/color/color_wheel_picker.dart';
import 'package:butterfly/views/amaze/color/marker_ring.dart';
import 'package:butterfly/views/amaze/color/palette_strip.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ring = ValueKey('amaze-color-ring');
const _sheet = ValueKey('amaze-color-more-sheet');
const _recent = [SRGBColor(0xFF112233), SRGBColor(0x80445566)];

class _Context extends Fake implements BuildContext {}

class _FakeSource implements AmazePaletteSource {
  _FakeSource(this.palettes);

  List<NamedItem<ColorPalette>> palettes;
  List<NamedItem<ColorPalette>> imported = const [];
  List<String> errors = const [];
  var imports = 0;

  @override
  Future<List<NamedItem<ColorPalette>>> load() async => palettes;

  @override
  Future<List<String>> import() async {
    imports++;
    palettes = [...palettes, ...imported];
    return errors;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MarkerPalette palette;

  setUpAll(() async {
    palette = (await loadMarkerPalette())!;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'recent_colors': [for (final color in _recent) '${color.value}'],
    });
  });

  NamedItem<ColorPalette> named(String name, List<int> colors) => NamedItem(
    name: name,
    item: ColorPalette(colors: [for (final c in colors) SRGBColor(c)]),
  );

  late SettingsCubit settings;
  late List<SRGBColor> picks;
  late List<SRGBColor?> closed;

  /// Opens the picker, then its "more" sheet.
  Future<void> openMore(
    WidgetTester tester, {
    AmazePaletteSource? source,
    SRGBColor initial = const SRGBColor(0xFFC85028),
    bool noData = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    settings = SettingsCubit(await SharedPreferences.getInstance());
    addTearDown(settings.close);
    picks = [];
    closed = [];
    await tester.pumpWidget(
      BlocProvider.value(
        value: settings,
        child: MaterialApp(
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
                    center: const Offset(640, 400),
                    innerRadius: 160,
                    initial: initial,
                    paletteLoader: () async => noData ? null : palette,
                    paletteSource: source,
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
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-color')));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsNothing);
    await tester.tap(find.byKey(const ValueKey('amaze-color-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsOneWidget);
  }

  Future<void> tapInSheet(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  MarkerWheelPainter painter(WidgetTester tester) {
    return tester.widget<CustomPaint>(find.byKey(_ring)).painter!
        as MarkerWheelPainter;
  }

  testWidgets('a recent color applies at once; settings are only read', (
    tester,
  ) async {
    await openMore(tester);
    final before = settings.state;
    expect(before.recentColors, _recent);
    for (var i = 0; i < _recent.length; i++) {
      expect(find.byKey(ValueKey(('amaze-color-recent', i))), findsOneWidget);
    }
    expect(
      find.byKey(ValueKey(('amaze-color-recent', _recent.length))),
      findsNothing,
    );
    await tapInSheet(tester, const ValueKey(('amaze-color-recent', 1)));
    expect(picks, [_recent[1]]);
    // The sheet closes; the picker stays open.
    expect(find.byKey(_sheet), findsNothing);
    expect(find.byKey(_ring), findsOneWidget);
    expect(closed, isEmpty);
    expect(identical(settings.state, before), isTrue);
    expect(
      (await SharedPreferences.getInstance()).getStringList('recent_colors'),
      [for (final color in _recent) '${color.value}'],
    );
  });

  testWidgets('a color of a chosen pack palette applies', (tester) async {
    final source = _FakeSource([
      named('Warm', [0xFFFF0000, 0xFFFF8800]),
      named('Cool', [0xFF0000FF, 0xFF00FFFF, 0xFF00FF00]),
    ]);
    await openMore(tester, source: source);
    expect(find.text('Warm'), findsOneWidget);
    await tapInSheet(tester, const ValueKey('amaze-color-palette-chooser'));
    await tester.tap(find.byKey(const ValueKey(('amaze-color-palette', 1))));
    await tester.pumpAndSettle();
    expect(find.text('Cool'), findsOneWidget);
    await tapInSheet(tester, const ValueKey(('amaze-color-palette-color', 2)));
    expect(picks.map((c) => c.value), [0xFF00FF00]);
    expect(find.byKey(_sheet), findsNothing);
    // A color that is no marker is labelled with its hex value.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('amaze-color-code'))).data,
      '#00ff00',
    );
  });

  testWidgets('importing refreshes the palette list', (tester) async {
    final source =
        _FakeSource([
            named('Warm', [0xFFFF0000]),
          ])
          ..imported = [
            named('Imported', [0xFF123456]),
          ];
    await openMore(tester, source: source);
    await tapInSheet(tester, const ValueKey('amaze-color-import'));
    expect(source.imports, 1);
    await tapInSheet(tester, const ValueKey('amaze-color-palette-chooser'));
    expect(
      find.byKey(const ValueKey(('amaze-color-palette', 1))),
      findsOneWidget,
    );
    expect(find.text('Imported'), findsOneWidget);
  });

  testWidgets('an invalid palette import shows its error in the sheet', (
    tester,
  ) async {
    final source = _FakeSource([
      named('Warm', [0xFFFF0000]),
    ])..errors = ['Broken.hex: invalid palette'];
    await openMore(tester, source: source);
    await tapInSheet(tester, const ValueKey('amaze-color-import'));
    final error = find.byKey(const ValueKey('amaze-color-import-error'));
    expect(error, findsOneWidget);
    expect(find.text('Broken.hex: invalid palette'), findsOneWidget);
    expect(
      find.ancestor(of: error, matching: find.byKey(_sheet)),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(picks, isEmpty);
  });

  testWidgets('finding "blender" spins to 0 and applies it', (tester) async {
    await openMore(tester);
    final find0 = find.byKey(const ValueKey('amaze-color-find'));
    await tester.enterText(find0, 'r29');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey(('amaze-color-find-result', 'R29'))),
      findsOneWidget,
    );
    expect(picks, isEmpty);

    await tester.enterText(find0, 'blender');
    await tester.pumpAndSettle();
    final result = find.byKey(const ValueKey(('amaze-color-find-result', '0')));
    expect(result, findsOneWidget);
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsNothing);
    final zero = palette.byCode('0')!;
    expect(picks, [zero.color]);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('amaze-color-code'))).data,
      '0',
    );
    final state = painter(tester);
    expect(state.selected, {'0'});
    expect(
      MarkerRingGeometry.isOnScreen(
        state.geometry.byCode('0')!,
        center: state.center,
        screen: const Size(1280, 800),
        rotation: state.rotation,
      ),
      isTrue,
    );
  });

  testWidgets('Enter in the find field takes the first match', (tester) async {
    // A color whose swatch is off screen until the wheel turns.
    const screen = Size(1280, 800);
    const center = Offset(640, 400);
    final code =
        MarkerRingGeometry.fit(
              palette,
              innerRadius: 160,
              center: center,
              screen: screen,
            ).swatches
            .where(
              (swatch) =>
                  palette.search(swatch.marker.code).first == swatch.marker &&
                  !MarkerRingGeometry.isOnScreen(
                    swatch,
                    center: center,
                    screen: screen,
                    rotation: 0,
                  ),
            )
            .first
            .marker
            .code;
    await openMore(tester);
    await tester.enterText(
      find.byKey(const ValueKey('amaze-color-find')),
      code,
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsNothing);
    expect(picks, [palette.byCode(code)!.color]);
    final state = painter(tester);
    // The wheel had to turn, and remembers where to.
    expect(state.rotation, isNot(0));
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        kAmazeColorAnglePreference,
      ),
      closeTo(state.rotation % (2 * 3.141592653589793), 1e-9),
    );
    expect(
      MarkerRingGeometry.isOnScreen(
        state.geometry.byCode(code)!,
        center: state.center,
        screen: screen,
        rotation: state.rotation,
      ),
      isTrue,
    );
  });

  testWidgets('finding from RGB switches back to the wheel', (tester) async {
    SharedPreferences.setMockInitialValues({'amaze.color.mode': 'rgb'});
    await openMore(tester);
    expect(find.byKey(_ring), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('amaze-color-find')),
      'R29',
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(picks.map((c) => c.value), [0xFFEF0047]);
    expect(painter(tester).selected, {'R29'});
  });

  testWidgets('the sheet keeps the trademark notice and data credit', (
    tester,
  ) async {
    await openMore(tester);
    final info = find.byKey(const ValueKey('amaze-color-info'));
    expect(info, findsOneWidget);
    final text = tester.widget<Text>(info).data!;
    expect(
      text,
      contains(
        'COPIC is a trademark of Too Corporation. aMaze is not affiliated '
        'with or endorsed by Too Corporation. Digital colors are '
        'approximations.',
      ),
    );
    expect(text, contains('Color data: meodai/copic-colors (MIT).'));
    // Escape closes the sheet first, then the picker.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsNothing);
    expect(find.byKey(_ring), findsOneWidget);
  });

  testWidgets('without marker data the sheet has no find field', (
    tester,
  ) async {
    await openMore(tester, noData: true);
    expect(find.byKey(const ValueKey('amaze-color-find')), findsNothing);
    expect(find.byKey(const ValueKey('amaze-color-info')), findsOneWidget);
    expect(
      find.byKey(const ValueKey(('amaze-color-recent', 0))),
      findsOneWidget,
    );
  });

  test('the pack source imports palette files into the core pack', () async {
    final temp = await Directory.systemTemp.createTemp('amaze_palettes_');
    addTearDown(() => temp.delete(recursive: true));
    final storage = LocalStorage(paths: {'': '${temp.path}/storage'});
    SharedPreferences.setMockInitialValues({
      'document_path': '${temp.path}/data',
      'connections': [storage.toJson()],
    });
    final settings = SettingsCubit(await SharedPreferences.getInstance());
    addTearDown(settings.close);
    final fileSystem = ButterflyFileSystem(_Context(), settings);
    addTearDown(fileSystem.dispose);
    final source = PackPaletteSource(fileSystem);
    final before = await source.load();

    final errors = await source.importFiles([
      (utf8.encode('ff0000\n00ff00\n'), 'hex', 'Lospec'),
      (utf8.encode('not a palette'), 'hex', 'Broken'),
    ]);
    expect(errors, hasLength(1));
    expect(errors.single, startsWith('Broken.hex'));
    var after = await source.load();
    expect(after, hasLength(before.length + 1));
    final imported = after.singleWhere((p) => p.name == 'Lospec');
    expect(imported.item.colors, const [
      SRGBColor(0xFFFF0000),
      SRGBColor(0xFF00FF00),
    ]);

    // A second import keeps both under unique names.
    await source.importFiles([(utf8.encode('0000ff\n'), 'hex', 'Lospec')]);
    after = await source.load();
    expect(after.map((p) => p.name), containsAll(['Lospec', 'Lospec (2)']));
  });
}
