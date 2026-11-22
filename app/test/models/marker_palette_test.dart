import 'dart:convert';
import 'dart:io';

import 'package:butterfly/models/marker_palette.dart';
import 'package:butterfly/services/marker_palette_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bundle without any assets.
class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    throw Exception('Unable to load asset: "$key".');
  }
}

/// A bundle that serves [text] for every key.
class _TextBundle extends CachingAssetBundle {
  _TextBundle(this.text);

  final String text;

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    return ByteData.sublistView(bytes);
  }
}

String _palette(List<Map<String, String>> colors) {
  return jsonEncode({'source': 'test', 'license': 'MIT', 'colors': colors});
}

const _red = {'code': 'R1', 'name': 'Red', 'hex': '#ff0000', 'family': 'R'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MarkerPalette palette;

  setUpAll(() {
    final file = File('assets/palettes/copic_colors.json');
    palette = MarkerPalette.parse(file.readAsStringSync());
  });

  test('the asset has 358 colors with unique codes and valid hex', () {
    expect(palette.colors, hasLength(358));
    final codes = palette.colors.map((color) => color.code).toSet();
    expect(codes, hasLength(358));
    final hex = RegExp(r'^#[0-9a-f]{6}$');
    for (final color in palette.colors) {
      expect(color.hex, matches(hex), reason: color.code);
    }
  });

  test('spot values match the source hex field', () {
    const expected = {
      'R29': '#ef0047',
      'B29': '#0077ba',
      'YG03': '#eaeeb2',
      'E27': '#ac866d',
      '0': '#ffffff',
      '110': '#000000',
    };
    for (final MapEntry(key: code, value: hex) in expected.entries) {
      expect(palette.byCode(code)?.hex, hex, reason: code);
    }
    expect(palette.byCode('0')?.family, 'A');
    expect(palette.byCode('110')?.family, 'A');
    expect(palette.byCode('0')?.name, 'Colorless Blender');
  });

  test('codes are found ignoring case', () {
    expect(palette.byCode('r29')?.code, 'R29');
    expect(palette.byCode('R29'), palette.byCode('r29'));
    expect(palette.byCode('R2'), isNull);
    expect(palette.byCode('nope'), isNull);
  });

  test('search ranks code matches first and finds names', () {
    final numbered = palette.search('29');
    expect(numbered, isNotEmpty);
    expect(numbered.map((color) => color.code), containsAll(['R29', 'B29']));
    for (final color in numbered) {
      expect(color.code, contains('29'));
    }

    final yellow = palette.search('y');
    final kinds = [
      for (final color in yellow)
        color.code.toLowerCase().startsWith('y')
            ? 0
            : color.code.toLowerCase().contains('y')
            ? 1
            : 2,
    ];
    expect(kinds, [...kinds]..sort(), reason: 'prefix, code, then name');
    expect(kinds, containsAll([0, 1, 2]));

    expect(palette.search('blender').map((color) => color.code), ['0']);
    expect(palette.search('BLENDER').map((color) => color.code), ['0']);
    expect(palette.search(''), hasLength(358));
    expect(palette.search('   '), hasLength(358));
  });

  test('families keep their first appearance order', () {
    final families = palette.families;
    expect(families.toSet(), hasLength(families.length));
    const named = [
      'E', 'B', 'R', 'RV', 'BG', 'G', 'YG', 'YR', //
      'Y', 'V', 'BV', 'C', 'W', 'N', 'T', 'A',
    ];
    expect(families, containsAll(named));
    final fluorescent = families.where((family) => family.startsWith('F'));
    expect(fluorescent, isNotEmpty);
    expect(families, hasLength(named.length + fluorescent.length));
    final firstSeen = <String>[];
    for (final color in palette.colors) {
      if (!firstSeen.contains(color.family)) firstSeen.add(color.family);
    }
    expect(families, firstSeen);
    for (final family in families) {
      expect(
        palette.byFamily(family).every((color) => color.family == family),
        isTrue,
      );
    }
    final total = families.fold(
      0,
      (sum, family) => sum + palette.byFamily(family).length,
    );
    expect(total, 358);
  });

  test('colors are opaque sRGB values', () {
    final color = palette.byCode('R29')!.color;
    expect((color.r, color.g, color.b, color.a), (239, 0, 71, 255));
    expect(palette.byCode('110')!.color.value, 0xFF000000);
  });

  test('colors are equal by code', () {
    const a = MarkerColor(code: 'X1', name: 'A', hex: '#000000', family: 'X');
    const b = MarkerColor(code: 'X1', name: 'B', hex: '#ffffff', family: 'Y');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  group('invalid palettes throw a FormatException', () {
    void expectInvalid(String json) {
      expect(() => MarkerPalette.parse(json), throwsFormatException);
    }

    test('malformed JSON', () => expectInvalid('{"colors": ['));
    test('not an object', () => expectInvalid('[]'));
    test('missing colors', () => expectInvalid('{"source": "x"}'));
    test('an empty list', () => expectInvalid(_palette([])));
    test('a bad hex', () {
      expectInvalid(
        _palette([
          {..._red, 'hex': '#ff00'},
        ]),
      );
      expectInvalid(
        _palette([
          {..._red, 'hex': '#FF0000'},
        ]),
      );
      expectInvalid(
        _palette([
          {..._red, 'hex': 'ff0000'},
        ]),
      );
    });
    test('a duplicate code', () {
      expectInvalid(
        _palette([
          _red,
          {..._red, 'name': 'Other'},
        ]),
      );
    });
    test('a missing field', () {
      expectInvalid(
        _palette([
          {'code': 'R1', 'hex': '#ff0000', 'family': 'R'},
        ]),
      );
    });
    test('a valid palette parses', () {
      expect(MarkerPalette.parse(_palette([_red])).colors, hasLength(1));
    });
  });

  group('loader', () {
    test('loads the bundled asset', () async {
      final loaded = await loadMarkerPalette();
      expect(loaded?.colors, hasLength(358));
    });

    test('returns null for a missing asset', () async {
      expect(
        await loadMarkerPalette(key: 'assets/palettes/missing.json'),
        isNull,
      );
      expect(await loadMarkerPalette(bundle: _EmptyBundle()), isNull);
    });

    test('returns null for an invalid asset', () async {
      expect(await loadMarkerPalette(bundle: _TextBundle('{')), isNull);
      expect(
        await loadMarkerPalette(bundle: _TextBundle(_palette([]))),
        isNull,
      );
    });
  });
}
