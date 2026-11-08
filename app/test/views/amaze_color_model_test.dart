import 'dart:math';

import 'package:butterfly/models/marker_palette.dart';
import 'package:butterfly/services/marker_palette_loader.dart';
import 'package:butterfly/views/amaze/color/color_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_leap/material_leap.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HSL and RGB round-trip 1,000 random colors within one channel', () {
    final random = Random(42);
    for (var i = 0; i < 1000; i++) {
      final color = SRGBColor.from(
        r: random.nextInt(256),
        g: random.nextInt(256),
        b: random.nextInt(256),
        a: random.nextInt(256),
      );
      final restored = hslToRgb(rgbToHsl(color));
      expect((restored.r - color.r).abs(), lessThanOrEqualTo(1));
      expect((restored.g - color.g).abs(), lessThanOrEqualTo(1));
      expect((restored.b - color.b).abs(), lessThanOrEqualTo(1));
      expect(restored.a, color.a);
    }
  });

  test('known HSL values and alpha', () {
    final red = rgbToHsl(SRGBColor.red);
    expect(red.hue, 0);
    expect(red.saturation, 100);
    expect(red.lightness, 50);
    final gray = rgbToHsl(const SRGBColor(0x80808080));
    expect(gray.saturation, 0);
    expect(gray.lightness, closeTo(50, 0.2));
    expect(hslToRgb(gray).a, 0x80);
  });

  test('marker lookup returns all exact RGB matches, ignoring alpha', () async {
    final palette = await loadMarkerPalette();
    expect(palette, isNotNull);
    expect(palette!.colors.length, 358);
    expect(
      markersFor(const SRGBColor(0x00EF0047), palette).map((m) => m.code),
      ['R29'],
    );
    expect(markersFor(SRGBColor.black, palette).map((m) => m.code), [
      '100',
      '110',
    ]);
    expect(markersFor(const SRGBColor(0xFF123456), palette), isEmpty);
    expect(markersFor(SRGBColor.black, null), isEmpty);
  });

  test('mode preference defaults and handles missing marker data', () async {
    SharedPreferences.setMockInitialValues({});
    final palette = MarkerPalette(const [
      MarkerColor(
        code: 'R29',
        name: 'Lipstick Red',
        hex: '#ef0047',
        family: 'R',
      ),
    ]);
    expect(await loadAmazeColorMode(palette: palette), AmazeColorMode.copic);
    expect(await loadAmazeColorMode(palette: null), AmazeColorMode.hsl);
    await saveAmazeColorMode(AmazeColorMode.rgb);
    expect(await loadAmazeColorMode(palette: palette), AmazeColorMode.rgb);
    expect(await loadAmazeColorMode(palette: null), AmazeColorMode.rgb);
  });
}
