import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Names and sizes of the brush textures, all generated in code from fixed
/// seeds so they are identical on every run. White with alpha.
const kBrushTextureSizes = <String, int>{
  'round-soft': 128,
  'round-hard': 128,
  'graphite': 128,
  'spray': 128,
  'paper': 256,
  'wash': 256,
};

/// Tileable value noise on a [period]×[period] lattice, 0–1.
class _ValueNoise {
  _ValueNoise(int seed, this.period)
    : _values = Float64List.fromList([
        for (var i = 0; i < period * period; i++) Random(seed + i).nextDouble(),
      ]);

  final int period;
  final Float64List _values;

  double _at(int x, int y) => _values[(y % period) * period + (x % period)];

  /// [x] and [y] in lattice units.
  double sample(double x, double y) {
    final x0 = x.floor();
    final y0 = y.floor();
    final fx = x - x0;
    final fy = y - y0;
    final sx = fx * fx * (3 - 2 * fx);
    final sy = fy * fy * (3 - 2 * fy);
    final a = _at(x0, y0);
    final b = _at(x0 + 1, y0);
    final c = _at(x0, y0 + 1);
    final d = _at(x0 + 1, y0 + 1);
    final top = a + (b - a) * sx;
    final bottom = c + (d - c) * sx;
    return top + (bottom - top) * sy;
  }
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// RGBA pixels of the texture [name] (white, straight alpha).
Uint8List generateTexturePixels(String name) {
  final size = kBrushTextureSizes[name]!;
  final pixels = Uint8List(size * size * 4);
  final alpha = _alphaFunction(name, size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final a = (alpha(x, y).clamp(0.0, 1.0) * 255).round();
      final i = (y * size + x) * 4;
      pixels[i] = 255;
      pixels[i + 1] = 255;
      pixels[i + 2] = 255;
      pixels[i + 3] = a;
    }
  }
  return pixels;
}

double Function(int x, int y) _alphaFunction(String name, int size) {
  final c = size / 2;
  double radius(int x, int y) {
    final dx = (x + 0.5 - c) / c;
    final dy = (y + 0.5 - c) / c;
    return sqrt(dx * dx + dy * dy);
  }

  switch (name) {
    case 'round-soft':
      return (x, y) {
        final r = radius(x, y);
        if (r >= 1) return 0;
        final t = 1 - r * r;
        return t * t;
      };
    case 'round-hard':
      // One texel of anti-aliasing at the rim.
      final aa = 1.5 / c;
      return (x, y) => 1 - _smoothstep(1 - aa, 1, radius(x, y));
    case 'graphite':
      final fine = _ValueNoise(1013, 64);
      final coarse = _ValueNoise(2027, 16);
      return (x, y) {
        final r = radius(x, y);
        if (r >= 1) return 0;
        final disc = 1 - _smoothstep(0.75, 1, r);
        final n =
            fine.sample(x / 2, y / 2) * 0.7 + coarse.sample(x / 8, y / 8) * 0.3;
        // Break the disc into specks: only the upper part of the noise shows.
        return disc * _smoothstep(0.35, 0.75, n);
      };
    case 'spray':
      final specks = Random(3041);
      final field = Float64List(size * size);
      for (var i = 0; i < 1400; i++) {
        // Gaussian-ish radial density: denser in the middle.
        final r = sqrt(-2 * log(1 - specks.nextDouble() * 0.999)) * 0.38;
        final angle = specks.nextDouble() * 2 * pi;
        final px = (c + cos(angle) * r * c).floor();
        final py = (c + sin(angle) * r * c).floor();
        if (px < 1 || py < 1 || px >= size - 1 || py >= size - 1) continue;
        final strength = 0.5 + specks.nextDouble() * 0.5;
        field[py * size + px] += strength;
        // A speck spreads a little into its neighbors.
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          field[(py + dy) * size + px + dx] += strength * 0.25;
        }
      }
      return (x, y) {
        final r = radius(x, y);
        if (r >= 1) return 0;
        return field[y * size + x] * (1 - _smoothstep(0.85, 1, r));
      };
    case 'paper':
      final fine = _ValueNoise(4051, 128);
      final mid = _ValueNoise(5059, 32);
      return (x, y) {
        final n =
            fine.sample(x / 2, y / 2) * 0.65 + mid.sample(x / 8, y / 8) * 0.35;
        // Most of the paper takes color; the pits stay light.
        return _smoothstep(0.2, 0.7, n);
      };
    case 'wash':
      final blotch = _ValueNoise(6067, 8);
      final detail = _ValueNoise(7079, 32);
      return (x, y) {
        final r = radius(x, y);
        if (r >= 1) return 0;
        final falloff = 1 - _smoothstep(0.55, 1, r);
        final n =
            blotch.sample(x / 32, y / 32) * 0.7 +
            detail.sample(x / 8, y / 8) * 0.3;
        return falloff * (0.55 + 0.45 * n);
      };
  }
  throw ArgumentError.value(name, 'name', 'Unknown brush texture');
}

/// Decodes [pixels] of a [size]×[size] texture into an image.
Future<ui.Image> textureImage(Uint8List pixels, int size) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    size,
    size,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Every brush texture as an image.
Future<Map<String, ui.Image>> buildBrushTextures() async => {
  for (final entry in kBrushTextureSizes.entries)
    entry.key: await textureImage(
      generateTexturePixels(entry.key),
      entry.value,
    ),
};
