import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Offset;

/// Names and sizes of the brush textures, all generated in code from fixed
/// seeds so they are identical on every run. White with alpha.
const kBrushTextureSizes = <String, int>{
  'round-soft': 128,
  'round-hard': 128,
  'graphite': 128,
  'spray': 128,
  'paper': 256,
  'wash': 256,
  // Tileable patterns, for outline brushes with a pattern fill.
  'bricks': 128,
  'hexagons': 128,
  'scales': 128,
  'dots-grid': 128,
  'hatch': 128,
  'crosshatch': 128,
  'stipple': 128,
  'wood-grain': 128,
  // Stamps.
  'splatter': 128,
  'blot': 128,
  'ink-drop': 128,
  'bleed': 128,
};

/// Textures that tile seamlessly, so they can fill an outline.
const kPatternTextures = {
  'bricks',
  'hexagons',
  'scales',
  'dots-grid',
  'hatch',
  'crosshatch',
  'stipple',
  'wood-grain',
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
    case 'bricks':
      return _bricks(size);
    case 'hexagons':
      return _hexagons(size);
    case 'scales':
      return _scales(size);
    case 'dots-grid':
      // A dot every 16 px; 128 is a whole number of periods.
      return (x, y) {
        final dx = (x + 0.5) % 16 - 8;
        final dy = (y + 0.5) % 16 - 8;
        return 1 - _smoothstep(2.6, 3.6, sqrt(dx * dx + dy * dy));
      };
    case 'hatch':
      return (x, y) => _diagonal(x + y, 16, 1.4);
    case 'crosshatch':
      return (x, y) =>
          max(_diagonal(x + y, 16, 1.2), _diagonal(x - y + size, 16, 1.2));
    case 'stipple':
      return _stipple(size);
    case 'wood-grain':
      final warp = _ValueNoise(8089, 8);
      final fine = _ValueNoise(9091, 32);
      return (x, y) {
        // Six rings over the tile, bent by tileable noise.
        final n = warp.sample(x / 16, y / 16);
        final phase = (y / size * 6 + n * 1.6) * 2 * pi;
        final ring = 1 - _smoothstep(0.0, 0.35, sin(phase).abs());
        final streak = _smoothstep(0.55, 0.9, fine.sample(x / 4, y / 4));
        return (ring * 0.9 + streak * 0.25).clamp(0.0, 1.0);
      };
    case 'splatter':
      return _splatter(size);
    case 'blot':
      final edge = _ValueNoise(10093, 16);
      return (x, y) {
        final dx = (x + 0.5 - c) / c;
        final dy = (y + 0.5 - c) / c;
        final r = sqrt(dx * dx + dy * dy);
        final angle = atan2(dy, dx);
        // Sample the noise on a circle so the edge closes on itself.
        final n = edge.sample(8 + cos(angle) * 5, 8 + sin(angle) * 5);
        final limit = 0.62 + 0.3 * n;
        return 1 - _smoothstep(limit - 0.04, limit, r);
      };
    case 'ink-drop':
      return (x, y) {
        final r = radius(x, y);
        // A solid drop with a slightly heavier rim, as ink dries.
        final body = 1 - _smoothstep(0.7, 0.76, r);
        final rim = 1 - _smoothstep(0.0, 0.08, (r - 0.68).abs());
        return max(body * 0.85, rim);
      };
    case 'bleed':
      final edge = _ValueNoise(11113, 16);
      final body = _ValueNoise(12119, 8);
      return (x, y) {
        final dx = (x + 0.5 - c) / c;
        final dy = (y + 0.5 - c) / c;
        final r = sqrt(dx * dx + dy * dy);
        final angle = atan2(dy, dx);
        final n = edge.sample(8 + cos(angle) * 6, 8 + sin(angle) * 6);
        final limit = 0.55 + 0.4 * n;
        final soft = 1 - _smoothstep(limit * 0.45, limit, r);
        return soft * (0.6 + 0.4 * body.sample(x / 16, y / 16));
      };
  }
  throw ArgumentError.value(name, 'name', 'Unknown brush texture');
}

/// A line [width] px wide every [period] px along the value [v].
double _diagonal(int v, double period, double width) {
  final d = ((v + 0.5) % period - period / 2).abs() * 0.7072;
  return 1 - _smoothstep(width - 0.8, width + 0.8, d);
}

/// Signed distance on a torus of [size], so features wrap around the tile.
double _wrap(double d, int size) {
  final m = d % size;
  return m > size / 2 ? m - size : m;
}

double Function(int x, int y) _bricks(int size) {
  const rows = 4;
  final height = size / rows;
  final width = size / 2;
  return (x, y) {
    final py = y + 0.5;
    final row = (py / height).floor();
    final px = x + 0.5 + (row.isOdd ? width / 2 : 0);
    final fy = py % height;
    final fx = px % width;
    final edge = min(min(fy, height - fy), min(fx, width - fx));
    final mortar = 1 - _smoothstep(1.0, 2.2, edge);
    // A faint face keeps the bricks readable on any background.
    return max(mortar, 0.12);
  };
}

double Function(int x, int y) _hexagons(int size) {
  // Four columns of hexagons and four rows per tile, slightly squashed so
  // the lattice tiles the square exactly.
  final columnStep = size / 4;
  final rowStep = size / 4;
  final centers = <Offset>[
    for (var i = 0; i < 4; i++)
      for (var j = 0; j < 4; j++)
        Offset(i * columnStep, j * rowStep + (i.isOdd ? rowStep / 2 : 0)),
  ];
  return (x, y) {
    var first = double.infinity, second = double.infinity;
    for (final center in centers) {
      final dx = _wrap(x + 0.5 - center.dx, size);
      final dy = _wrap(y + 0.5 - center.dy, size) * 1.15;
      final d = sqrt(dx * dx + dy * dy);
      if (d < first) {
        second = first;
        first = d;
      } else if (d < second) {
        second = d;
      }
    }
    // Equally close to two centers means on the edge between their cells.
    return 1 - _smoothstep(1.0, 2.6, second - first);
  };
}

double Function(int x, int y) _scales(int size) {
  const columns = 4;
  const rows = 8;
  final step = size / columns;
  final rowStep = size / rows;
  final radius = step * 0.62;
  return (x, y) {
    final px = x + 0.5, py = y + 0.5;
    double? best;
    var bestRow = -1000000;
    for (var j = -2; j <= rows + 2; j++) {
      final cy = j * rowStep;
      final shift = j.isOdd ? step / 2 : 0.0;
      for (var i = -1; i <= columns + 1; i++) {
        final dx = _wrap(px - (i * step + shift), size);
        final dy = py - cy;
        final d = sqrt(dx * dx + dy * dy);
        // Lower rows overlap the ones above, like roof tiles.
        if (d < radius && dy >= 0 && j > bestRow) {
          bestRow = j;
          best = d;
        }
      }
    }
    final d = best;
    if (d == null) return 0.12;
    return max(1 - _smoothstep(1.2, 2.6, radius - d), 0.12);
  };
}

double Function(int x, int y) _stipple(int size) {
  final random = Random(13127);
  final field = Float64List(size * size);
  for (var n = 0; n < 220; n++) {
    final cx = random.nextDouble() * size;
    final cy = random.nextDouble() * size;
    final r = 0.9 + random.nextDouble() * 1.1;
    for (var y = (cy - r - 2).floor(); y <= (cy + r + 2).ceil(); y++) {
      for (var x = (cx - r - 2).floor(); x <= (cx + r + 2).ceil(); x++) {
        final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        final a = 1 - _smoothstep(r - 0.6, r + 0.6, sqrt(dx * dx + dy * dy));
        final i = (y % size) * size + (x % size);
        field[i] = max(field[i], a);
      }
    }
  }
  return (x, y) => field[y * size + x];
}

double Function(int x, int y) _splatter(int size) {
  final random = Random(14143);
  final c = size / 2;
  final drops = <(double, double, double)>[(c, c, size * 0.2)];
  for (var i = 0; i < 26; i++) {
    final angle = random.nextDouble() * 2 * pi;
    final distance = (0.25 + random.nextDouble() * 0.68) * c;
    final r = (1 - distance / c) * size * 0.07 + 1.2;
    drops.add((c + cos(angle) * distance, c + sin(angle) * distance, r));
  }
  return (x, y) {
    var a = 0.0;
    for (final (cx, cy, r) in drops) {
      final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      a = max(a, 1 - _smoothstep(r - 0.8, r + 0.8, sqrt(dx * dx + dy * dy)));
    }
    return a;
  };
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
