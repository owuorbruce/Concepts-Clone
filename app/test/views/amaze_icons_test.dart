import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:butterfly/views/amaze/icons.dart';
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

Future<void> _loadFonts() async {
  final manifest = await rootBundle.loadString('FontManifest.json');
  final families = jsonDecode(manifest) as List<dynamic>;
  for (final family in families.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    final fonts = family['fonts'] as List<dynamic>;
    for (final font in fonts.cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// The icons the wheel, bar and dock used before the redesign.
const _before = <(String, IconData)>[
  ('Pen', PhosphorIconsLight.pen),
  ('Lasso', PhosphorIconsLight.lasso),
  ('Text', PhosphorIconsLight.textT),
  ('Pan', PhosphorIconsLight.hand),
  ('Size', PhosphorIconsLight.arrowsOutSimple),
  ('Opacity', PhosphorIconsLight.drop),
  ('Smoothing', PhosphorIconsLight.path),
  ('Layers', PhosphorIconsLight.stack),
  ('All tools', PhosphorIconsLight.toolbox),
  ('Undo', PhosphorIconsLight.arrowCounterClockwise),
];

/// The same places after the redesign.
final _after = <(String, AmazeIconData)>[
  ('Pen', LibraryEntry.pen.icon),
  ('Lasso', LibraryEntry.lasso.icon),
  ('Text', LibraryEntry.text.icon),
  ('Pan', LibraryEntry.pan.icon),
  ('Size', AmazeIcons.size),
  ('Opacity', AmazeIcons.opacity),
  ('Smoothing', AmazeIcons.smoothing),
  ('Layers', AmazeIcons.layers),
  ('All tools', AmazeIcons.toolCatalog),
  ('Undo', AmazeIcons.undo),
];

Widget _cell(String label, Widget icon, Color color) {
  return SizedBox(
    width: 84,
    child: Column(
      children: [
        SizedBox.square(dimension: 32, child: Center(child: icon)),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Comfortaa',
            fontSize: 11,
            color: color,
          ),
        ),
      ],
    ),
  );
}

Widget _sheet(bool dark) {
  final background = dark ? const Color(0xFF15191C) : const Color(0xFFF7F8F7);
  final foreground = dark ? const Color(0xFFE6E9E7) : const Color(0xFF1B1F22);
  Widget row(String title, List<Widget> cells) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'Comfortaa',
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...cells,
        ],
      ),
    );
  }

  return Container(
    color: background,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      children: [
        row('Before', [
          for (final (label, icon) in _before)
            _cell(label, Icon(icon, size: 24, color: foreground), foreground),
        ]),
        row('After', [
          for (final (label, icon) in _after)
            _cell(
              label,
              AmazeIcon(icon, size: 24, color: foreground),
              foreground,
            ),
        ]),
        row('Brushes', [
          for (final entry in LibraryEntry.of(LibrarySection.basics).take(10))
            _cell(
              entry.name,
              AmazeGlyphIcon(entry.glyph!, size: 32, color: foreground),
              foreground,
            ),
        ]),
        row('', [
          for (final entry in LibraryEntry.of(LibrarySection.basics).skip(10))
            _cell(
              entry.name,
              AmazeGlyphIcon(entry.glyph!, size: 32, color: foreground),
              foreground,
            ),
          for (final entry in LibraryEntry.of(LibrarySection.tools).take(8))
            _cell(
              entry.name,
              AmazeIcon(entry.icon, size: 28, color: foreground),
              foreground,
            ),
        ]),
        row('Small (16)', [
          for (final glyph in AmazeGlyph.values.take(10))
            _cell(
              '',
              AmazeGlyphIcon(glyph, size: 16, color: foreground),
              foreground,
            ),
        ]),
      ],
    ),
  );
}

/// Sum of the alpha channel of the last [_coverage] image.
var _lastAlphaSum = 0;

/// Paints [glyph] at [size] and returns how many pixels it covered.
Future<int> _coverage(AmazeGlyph glyph, double size, {bool wide = false}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final width = wide ? size * 2 : size;
  AmazeGlyphPainter(
    glyph,
    const Color(0xFF000000),
    wide: wide,
  ).paint(canvas, Size(width, size));
  final picture = recorder.endRecording();
  return picture.toImage(width.ceil(), size.ceil()).then((image) async {
    final bytes = await image.toByteData();
    image.dispose();
    var covered = 0;
    final data = bytes!.buffer.asUint8List();
    for (var i = 3; i < data.length; i += 4) {
      if (data[i] > 24) covered++;
    }
    _lastAlphaSum = 0;
    for (var i = 3; i < data.length; i += 4) {
      _lastAlphaSum += data[i];
    }
    return covered;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final dark in [false, true]) {
    testWidgets('icon sheet ${dark ? 'dark' : 'light'}', (tester) async {
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(1100, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: .ltr,
          child: Align(
            alignment: .topLeft,
            child: RepaintBoundary(key: key, child: _sheet(dark)),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final name = dark ? 'icons-before-after-dark' : 'icons-before-after';
        final file = File('build/amaze_screenshots/$name.png');
        await file.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
      });
      expect(tester.takeException(), isNull);
    });
  }

  group('LibraryEntry', () {
    test('has twelve basics, nine tools and four market packs', () {
      expect(LibraryEntry.of(LibrarySection.basics), hasLength(12));
      expect(LibraryEntry.of(LibrarySection.tools), hasLength(9));
      expect(LibraryEntry.of(LibrarySection.market), hasLength(4));
    });

    test('only offers what the canvas can do', () {
      final available = LibraryEntry.values.where((entry) => entry.available);
      expect(available.toSet(), {
        LibraryEntry.pen,
        LibraryEntry.dynamicPen,
        LibraryEntry.fixedWidth,
        LibraryEntry.wire,
        LibraryEntry.fill,
        LibraryEntry.lasso,
        LibraryEntry.slice,
        LibraryEntry.text,
        LibraryEntry.pan,
      });
      for (final entry in LibraryEntry.values) {
        if (entry.available) continue;
        expect(entry.createTool(), isNull, reason: entry.name);
      }
    });

    test('remembers the entry of a created tool', () {
      for (final entry in LibraryEntry.values) {
        final tool = entry.createTool(name: 'x');
        if (tool == null) continue;
        expect(libraryEntryOf(tool), entry, reason: entry.name);
        expect(tool.name, 'x');
      }
    });

    test('creates real tools', () {
      expect(LibraryEntry.lasso.createTool(), isA<SelectTool>());
      expect(
        (LibraryEntry.lasso.createTool()! as SelectTool).mode,
        SelectMode.lasso,
      );
      expect(LibraryEntry.slice.createTool(), isA<EraserTool>());
      expect(LibraryEntry.text.createTool(), isA<LabelTool>());
      expect(LibraryEntry.pan.createTool(), isA<HandTool>());
      final fill = LibraryEntry.fill.createTool()! as PenTool;
      expect(fill.property.fillPaint.previewColor.a, greaterThan(0));
    });

    test('matches built-in tools so the wheel shows library icons', () {
      expect(libraryEntryOf(Tool.pen()), LibraryEntry.pen);
      expect(libraryEntryOf(Tool.hand()), LibraryEntry.pan);
      expect(libraryEntryOf(Tool.label()), LibraryEntry.text);
      expect(
        libraryEntryOf(Tool.select(mode: SelectMode.lasso)),
        LibraryEntry.lasso,
      );
      expect(libraryEntryOf(Tool.select()), isNull);
      expect(libraryEntryOf(Tool.eraser()), isNull);
      expect(libraryEntryOf(Tool.pen(displayIcon: 'pencil')), isNull);
    });

    test('keeps the fill color in step with the outline', () {
      final tool = LibraryEntry.fill.createTool()! as PenTool;
      final red = tool.copyWith(
        property: tool.property.copyWith(
          paint: const ElementPaint.solid(color: SRGBColor(0xFFFF0000)),
        ),
      );
      final synced = syncLibraryFill(red) as PenTool;
      expect(
        synced.property.fillPaint.previewColor,
        const SRGBColor(0xFFFF0000),
      );
      final pen = Tool.pen();
      expect(syncLibraryFill(pen), same(pen));
    });
  });

  group('AmazeGlyph', () {
    for (final glyph in AmazeGlyph.values) {
      test('${glyph.name} draws at every size', () async {
        for (final size in [16.0, 24.0, 48.0, 96.0]) {
          final covered = await _coverage(glyph, size);
          expect(covered, greaterThan(0), reason: '${glyph.name} at $size');
          expect(covered, lessThan(size * size), reason: 'not a solid box');
        }
        if (glyph.isBrush || glyph.isPack) {
          expect(await _coverage(glyph, 48, wide: true), greaterThan(0));
        }
      });
    }

    test('brushes look different from each other', () async {
      final seen = <int, AmazeGlyph>{};
      for (final glyph in AmazeGlyph.values.where((glyph) => glyph.isBrush)) {
        await _coverage(glyph, 96);
        final twin = seen[_lastAlphaSum];
        expect(twin, isNull, reason: '${glyph.name} looks like $twin');
        seen[_lastAlphaSum] = glyph;
      }
    });
  });
}
