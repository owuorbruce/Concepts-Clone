import 'dart:convert';
import 'dart:io';

import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/models/marker_palette.dart';
import 'package:butterfly/services/marker_palette_loader.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/views/amaze/color/color_wheel_picker.dart';
import 'package:butterfly/views/amaze/color/palette_strip.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _done = ValueKey('amaze-color-done');
const _cancel = ValueKey('amaze-color-cancel');

const _recent = [SRGBColor(0xFF112233), SRGBColor(0x80445566)];

class _Context extends Fake implements BuildContext {}

class _FakeSource implements AmazePaletteSource {
  _FakeSource(this.palettes);

  List<NamedItem<ColorPalette>> palettes;
  List<NamedItem<ColorPalette>> imported = const [];
  var imports = 0;

  @override
  Future<List<NamedItem<ColorPalette>>> load() async => palettes;

  @override
  Future<List<String>> import() async {
    imports++;
    palettes = [...palettes, ...imported];
    return const [];
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

  Future<Future<AmazeColorResult?>? Function()> open(
    WidgetTester tester, {
    AmazePaletteSource? source,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    settings = SettingsCubit(await SharedPreferences.getInstance());
    addTearDown(settings.close);
    Future<AmazeColorResult?>? result;
    await tester.pumpWidget(
      BlocProvider.value(
        value: settings,
        child: MaterialApp(
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
                      initial: const SRGBColor(0xFFC85028),
                      paletteLoader: () async => palette,
                      paletteSource: source,
                    );
                  },
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
    return () => result;
  }

  Future<AmazeColorResult?> tapThen(
    WidgetTester tester,
    Future<AmazeColorResult?>? Function() result,
    Key swatch,
    Key button,
  ) async {
    await tester.tap(find.byKey(swatch));
    await tester.pumpAndSettle();
    expect(find.byKey(_done), findsOneWidget, reason: 'a tap only previews');
    await tester.tap(find.byKey(button));
    await tester.pumpAndSettle();
    return result();
  }

  testWidgets('a recent color, then Done, returns it; settings unchanged', (
    tester,
  ) async {
    final result = await open(tester);
    final before = settings.state;
    expect(before.recentColors, _recent);
    final picked = await tapThen(
      tester,
      result,
      const ValueKey(('amaze-color-recent', 1)),
      _done,
    );
    expect((picked as AmazePickedColor).color, _recent[1]);
    expect(identical(settings.state, before), isTrue);
    expect(
      (await SharedPreferences.getInstance()).getStringList('recent_colors'),
      [for (final color in _recent) '${color.value}'],
    );
  });

  testWidgets('recent colors are read from settings', (tester) async {
    await open(tester);
    for (var i = 0; i < _recent.length; i++) {
      expect(find.byKey(ValueKey(('amaze-color-recent', i))), findsOneWidget);
    }
    expect(
      find.byKey(ValueKey(('amaze-color-recent', _recent.length))),
      findsNothing,
    );
  });

  testWidgets('a pack palette color, then Done, returns it', (tester) async {
    final source = _FakeSource([
      named('Warm', [0xFFFF0000, 0xFFFF8800]),
      named('Cool', [0xFF0000FF, 0xFF00FFFF, 0xFF00FF00]),
    ]);
    final result = await open(tester, source: source);
    expect(find.text('Warm'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('amaze-color-palette-chooser')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(('amaze-color-palette', 1))));
    await tester.pumpAndSettle();
    expect(find.text('Cool'), findsOneWidget);
    final swatch = find.byKey(const ValueKey(('amaze-color-palette-color', 2)));
    await tester.ensureVisible(swatch);
    final picked = await tapThen(
      tester,
      result,
      const ValueKey(('amaze-color-palette-color', 2)),
      _done,
    );
    expect((picked as AmazePickedColor).color.value, 0xFF00FF00);
  });

  testWidgets('importing refreshes the palette list', (tester) async {
    final source =
        _FakeSource([
            named('Warm', [0xFFFF0000]),
          ])
          ..imported = [
            named('Imported', [0xFF123456]),
          ];
    await open(tester, source: source);
    final import = find.byKey(const ValueKey('amaze-color-import'));
    await tester.ensureVisible(import);
    await tester.tap(import);
    await tester.pumpAndSettle();
    expect(source.imports, 1);
    await tester.tap(find.byKey(const ValueKey('amaze-color-palette-chooser')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey(('amaze-color-palette', 1))),
      findsOneWidget,
    );
    expect(find.text('Imported'), findsOneWidget);
  });

  testWidgets('white and black only preview until Done', (tester) async {
    var result = await open(tester);
    expect(
      await tapThen(
        tester,
        result,
        const ValueKey('amaze-color-white'),
        _cancel,
      ),
      isNull,
    );
    result = await open(tester);
    final white = await tapThen(
      tester,
      result,
      const ValueKey('amaze-color-white'),
      _done,
    );
    expect((white as AmazePickedColor).color, SRGBColor.white);
    result = await open(tester);
    final black = await tapThen(
      tester,
      result,
      const ValueKey('amaze-color-black'),
      _done,
    );
    expect((black as AmazePickedColor).color, SRGBColor.black);
  });

  testWidgets('a palette color clears the tapped marker code', (tester) async {
    final result = await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('amaze-color-search')),
      'R29',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final code = find.byKey(const ValueKey('amaze-color-code'));
    expect(tester.widget<Text>(code).data, 'R29');
    await tester.tap(find.byKey(const ValueKey('amaze-color-black')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(code).data, '100 / 110');
    await tester.tap(find.byKey(_cancel));
    await tester.pumpAndSettle();
    expect(await result(), isNull);
  });

  testWidgets('the eyedropper closes the picker immediately', (tester) async {
    final result = await open(tester);
    final before = settings.state;
    await tester.tap(find.byKey(const ValueKey('amaze-color-white')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('amaze-color-eyedropper')));
    await tester.pumpAndSettle();
    expect(find.byKey(_done), findsNothing);
    expect(await result(), isA<AmazeEyedropperRequested>());
    expect(identical(settings.state, before), isTrue);
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
