import 'dart:math' as math;

import 'package:butterfly/models/marker_palette.dart';
import 'package:material_leap/material_leap.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Display HSL values: hue in degrees and saturation/lightness in percent.
class HslChannels {
  const HslChannels(this.hue, this.saturation, this.lightness, this.alpha);

  final double hue;
  final double saturation;
  final double lightness;
  final double alpha;
}

/// Converts the stored 8-bit sRGB channels to display HSL without changing
/// the stored alpha channel.
HslChannels rgbToHsl(SRGBColor color) {
  final r = color.r / 255.0;
  final g = color.g / 255.0;
  final b = color.b / 255.0;
  final high = math.max(r, math.max(g, b));
  final low = math.min(r, math.min(g, b));
  final delta = high - low;
  final lightness = (high + low) / 2;
  var hue = 0.0;
  var saturation = 0.0;
  if (delta > 0) {
    saturation = delta / (1 - (2 * lightness - 1).abs());
    if (high == r) {
      hue = ((g - b) / delta) % 6;
    } else if (high == g) {
      hue = (b - r) / delta + 2;
    } else {
      hue = (r - g) / delta + 4;
    }
    hue = (hue * 60 + 360) % 360;
  }
  return HslChannels(
    hue,
    saturation * 100,
    lightness * 100,
    color.a / 255 * 100,
  );
}

/// Converts display HSL values to sRGB. Values are clamped to the displayed
/// channel ranges; alpha is supplied in percent.
SRGBColor hslToRgb(HslChannels channels) {
  final h = channels.hue.clamp(0.0, 360.0) % 360;
  final s = channels.saturation.clamp(0.0, 100.0) / 100;
  final l = channels.lightness.clamp(0.0, 100.0) / 100;
  final chroma = (1 - (2 * l - 1).abs()) * s;
  final x = chroma * (1 - ((h / 60) % 2 - 1).abs());
  final m = l - chroma / 2;
  final (r, g, b) = switch (h) {
    < 60 => (chroma, x, 0.0),
    < 120 => (x, chroma, 0.0),
    < 180 => (0.0, chroma, x),
    < 240 => (0.0, x, chroma),
    < 300 => (x, 0.0, chroma),
    _ => (chroma, 0.0, x),
  };
  int byte(double value) => ((value + m) * 255).round().clamp(0, 255);
  return SRGBColor.from(
    r: byte(r),
    g: byte(g),
    b: byte(b),
    a: (channels.alpha.clamp(0.0, 100.0) * 255 / 100).round(),
  );
}

/// Every marker with the same six-digit RGB value, in source order.
/// Marker identities are picker-only; documents continue to store SRGBColor.
List<MarkerColor> markersFor(SRGBColor color, MarkerPalette? palette) {
  if (palette == null) return const [];
  final rgb = color.value & 0xFFFFFF;
  return palette.colors.where((marker) {
    return int.parse(marker.hex.substring(1), radix: 16) == rgb;
  }).toList();
}

enum AmazeColorMode { copic, hsl, rgb }

const kAmazeColorModePreference = 'amaze.color.mode';

/// The unavailable marker mode is never presented, even if it was saved on
/// another device or before the bundled palette went missing.
Future<AmazeColorMode> loadAmazeColorMode({
  required MarkerPalette? palette,
  SharedPreferences? preferences,
}) async {
  final prefs = preferences ?? await SharedPreferences.getInstance();
  final name = prefs.getString(kAmazeColorModePreference);
  final mode = AmazeColorMode.values
      .where((mode) => mode.name == name)
      .firstOrNull;
  if (palette == null && (mode == null || mode == AmazeColorMode.copic)) {
    return AmazeColorMode.hsl;
  }
  return mode ?? AmazeColorMode.copic;
}

Future<void> saveAmazeColorMode(
  AmazeColorMode mode, {
  SharedPreferences? preferences,
}) async {
  final prefs = preferences ?? await SharedPreferences.getInstance();
  await prefs.setString(kAmazeColorModePreference, mode.name);
}
