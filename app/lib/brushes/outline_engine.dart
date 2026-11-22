import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:butterfly_api/butterfly_api.dart';

import 'dynamics.dart';

/// Largest change of the tangent between two samples, in radians. Keeps
/// curves smooth at any zoom, not only at the zoom they were drawn at.
const _kMaxTurn = 0.06;

/// Upper bound of samples per stroke; denser strokes are sampled coarser.
const _kMaxSamples = 60000;

/// The sampled centerline of a stroke and the brush width at each sample.
/// Coordinates are relative to the origin given when it was built.
class StrokeGeometry {
  StrokeGeometry._(
    this.x,
    this.y,
    this.pressure,
    this.tilt,
    this.speed,
    this.angle,
    this.arc,
    this.width,
  );

  final Float64List x, y, pressure, tilt, speed, angle, arc, width;

  int get length => x.length;
  bool get isEmpty => x.isEmpty;

  /// Total arc length.
  double get arcLength => isEmpty ? 0 : arc[length - 1];

  double get maxWidth {
    var result = 0.0;
    for (final w in width) {
      if (w > result) result = w;
    }
    return result;
  }

  Offset operator [](int i) => Offset(x[i], y[i]);

  /// Builds the geometry of [points] (world coordinates) for [def].
  factory StrokeGeometry.build(
    List<PathPoint> points,
    BrushDefinition def,
    double strokeWidth, {
    required double zoom,
    required Offset origin,
  }) {
    final raw = _RawStroke.of(points, origin, zoom, def.width.speedSmoothing);
    final samples = raw.sample(zoom, strokeWidth * 0.6);
    final n = samples.x.length;
    final width = Float64List(n);
    final total = n == 0 ? 0.0 : samples.arc[n - 1];
    final w = def.width;
    final useSpeed = w.speed > 0 && raw.hasTime;
    final nibAspect = def.nib.aspect.clamp(0.0, 1.0);
    final nibAngle = def.nib.angleDeg * pi / 180;
    var taperStart = def.taper.start * strokeWidth;
    var taperEnd = def.taper.end * strokeWidth;
    if (taperStart + taperEnd > total && taperStart + taperEnd > 0) {
      final scale = total / (taperStart + taperEnd);
      taperStart *= scale;
      taperEnd *= scale;
    }
    final dynamics = def.dynamics;
    final hasSize = hasDynamics(dynamics, BrushOutput.size);
    for (var i = 0; i < n; i++) {
      final p = samples.pressure[i].clamp(0.0, 1.0);
      var factor = w.pressureGamma == 0
          ? 1.0
          : max(w.minRatio, pow(p, w.pressureGamma).toDouble());
      if (useSpeed) {
        final v = (samples.speed[i] / kBrushSpeedNorm).clamp(0.0, 1.0);
        factor *= max(w.minRatio, 1 - w.speed * v);
      }
      if (nibAspect < 1) {
        factor *=
            nibAspect +
            (1 - nibAspect) * sin(samples.angle[i] - nibAngle).abs();
      }
      if (taperStart > 0 || taperEnd > 0) {
        final s = samples.arc[i];
        var t = 1.0;
        if (taperStart > 0 && s < taperStart) {
          t = min(t, _easeOut(s / taperStart));
        }
        if (taperEnd > 0 && total - s < taperEnd) {
          t = min(t, _easeOut((total - s) / taperEnd));
        }
        factor *= w.minRatio + (1 - w.minRatio) * t;
      }
      if (hasSize) {
        factor = applyDynamics(
          dynamics,
          BrushOutput.size,
          factor,
          BrushInputs(
            pressure: p,
            speed: samples.speed[i],
            tilt: samples.tilt[i],
            direction: samples.angle[i],
            random: _hashRandom(i),
            progress: total == 0 ? 0 : samples.arc[i] / total,
          ),
        );
      }
      width[i] = max(strokeWidth * factor, strokeWidth * 0.01);
    }
    return StrokeGeometry._(
      samples.x,
      samples.y,
      samples.pressure,
      samples.tilt,
      samples.speed,
      samples.angle,
      samples.arc,
      width,
    );
  }
}

double _easeOut(double x) {
  final t = 1 - x.clamp(0.0, 1.0);
  return 1 - t * t;
}

double _hashRandom(int i) {
  var h = (i * 0x9E3779B1) & 0xffffffff;
  h ^= h >> 15;
  h = (h * 0x85EBCA77) & 0xffffffff;
  h ^= h >> 13;
  return (h & 0xffff) / 0xffff;
}

double _wrapAngle(double a) {
  while (a > pi) {
    a -= 2 * pi;
  }
  while (a < -pi) {
    a += 2 * pi;
  }
  return a;
}

class _Samples {
  _Samples(int capacity)
    : x = Float64List(capacity),
      y = Float64List(capacity),
      pressure = Float64List(capacity),
      tilt = Float64List(capacity),
      speed = Float64List(capacity),
      angle = Float64List(capacity),
      arc = Float64List(capacity);

  Float64List x, y, pressure, tilt, speed, angle, arc;
  int count = 0;

  void add(double px, double py, double p, double t, double v, double a) {
    if (count == x.length) _grow();
    if (count > 0) {
      final dx = px - x[count - 1];
      final dy = py - y[count - 1];
      arc[count] = arc[count - 1] + sqrt(dx * dx + dy * dy);
    }
    x[count] = px;
    y[count] = py;
    pressure[count] = p;
    tilt[count] = t;
    speed[count] = v;
    angle[count] = a;
    count++;
  }

  void _grow() {
    Float64List g(Float64List l) =>
        Float64List(l.length * 2 + 16)..setAll(0, l);
    x = g(x);
    y = g(y);
    pressure = g(pressure);
    tilt = g(tilt);
    speed = g(speed);
    angle = g(angle);
    arc = g(arc);
  }

  void trim() {
    Float64List t(Float64List l) => Float64List.sublistView(l, 0, count);
    x = t(x);
    y = t(y);
    pressure = t(pressure);
    tilt = t(tilt);
    speed = t(speed);
    angle = t(angle);
    arc = t(arc);
  }
}

/// The input points relative to the origin, without duplicates, with the
/// smoothed screen speed at each point.
class _RawStroke {
  _RawStroke(
    this.x,
    this.y,
    this.pressure,
    this.tilt,
    this.speed,
    this.hasTime,
  );

  final List<double> x, y, pressure, tilt, speed;
  final bool hasTime;

  factory _RawStroke.of(
    List<PathPoint> points,
    Offset origin,
    double zoom,
    double smoothing,
  ) {
    final x = <double>[], y = <double>[], p = <double>[], tilt = <double>[];
    final time = <int?>[];
    for (final point in points) {
      final px = point.x - origin.dx;
      final py = point.y - origin.dy;
      if (x.isNotEmpty) {
        final dx = px - x.last;
        final dy = py - y.last;
        if (dx * dx + dy * dy < 1e-18) {
          // Keep the latest pressure of a point that did not move.
          p[p.length - 1] = point.pressure;
          continue;
        }
      }
      x.add(px);
      y.add(py);
      p.add(point.pressure);
      tilt.add(point.tilt ?? 0);
      time.add(point.time);
    }
    final hasTime = time.isNotEmpty && time.every((t) => t != null);
    final speed = List<double>.filled(x.length, 0);
    if (hasTime && x.length > 1) {
      final s = smoothing.clamp(0.0, 0.99);
      double? smoothed;
      var last = 0.0;
      for (var i = 1; i < x.length; i++) {
        final dt = time[i]! - time[i - 1]!;
        if (dt > 0) {
          final dx = x[i] - x[i - 1];
          final dy = y[i] - y[i - 1];
          final v = sqrt(dx * dx + dy * dy) * zoom / dt;
          smoothed = smoothed == null ? v : s * smoothed + (1 - s) * v;
          last = smoothed;
        }
        speed[i] = last;
      }
      speed[0] = speed.length > 1 ? speed[1] : 0;
      // Points before the first timed segment take its speed.
      for (var i = 1; i < speed.length && speed[i] == 0; i++) {
        speed[i] = smoothed ?? 0;
      }
    }
    return _RawStroke(x, y, p, tilt, speed, hasTime);
  }

  /// Centripetal Catmull–Rom samples at most 1 / [zoom] apart, also on the
  /// outer side of a curve [halfWidth] away from the centerline.
  _Samples sample(double zoom, double halfWidth) {
    final n = x.length;
    if (n == 0) return _Samples(0)..trim();
    if (n == 1) {
      return _Samples(1)
        ..add(x[0], y[0], pressure[0], tilt[0], speed[0], 0)
        ..trim();
    }
    var chordTotal = 0.0;
    for (var i = 1; i < n; i++) {
      chordTotal += sqrt(_d2(i - 1, i));
    }
    var density = max(zoom, 1e-6);
    if (chordTotal * density > _kMaxSamples) {
      density = _kMaxSamples / chordTotal;
    }
    final samples = _Samples(
      min((chordTotal * density).ceil() + n * 2, _kMaxSamples * 2),
    );
    for (var i = 0; i < n - 1; i++) {
      final x1 = x[i], y1 = y[i], x2 = x[i + 1], y2 = y[i + 1];
      final x0 = i > 0 ? x[i - 1] : 2 * x1 - x2;
      final y0 = i > 0 ? y[i - 1] : 2 * y1 - y2;
      final x3 = i + 2 < n ? x[i + 2] : 2 * x2 - x1;
      final y3 = i + 2 < n ? y[i + 2] : 2 * y2 - y1;
      final d0 = sqrt(sqrt(_dist2(x0, y0, x1, y1)));
      final d1 = sqrt(sqrt(_dist2(x1, y1, x2, y2)));
      final d2 = sqrt(sqrt(_dist2(x2, y2, x3, y3)));
      // Hermite tangents of the centripetal spline, scaled to [0, 1].
      double m1x, m1y, m2x, m2y;
      if (d0 < 1e-12) {
        m1x = x2 - x1;
        m1y = y2 - y1;
      } else {
        m1x = ((x1 - x0) / d0 - (x2 - x0) / (d0 + d1) + (x2 - x1) / d1) * d1;
        m1y = ((y1 - y0) / d0 - (y2 - y0) / (d0 + d1) + (y2 - y1) / d1) * d1;
      }
      if (d2 < 1e-12) {
        m2x = x2 - x1;
        m2y = y2 - y1;
      } else {
        m2x = ((x2 - x1) / d1 - (x3 - x1) / (d1 + d2) + (x3 - x2) / d2) * d1;
        m2y = ((y2 - y1) / d1 - (y3 - y1) / (d1 + d2) + (y3 - y2) / d2) * d1;
      }
      final chord = sqrt(_dist2(x1, y1, x2, y2));
      final turn = _wrapAngle(atan2(m2y, m2x) - atan2(m1y, m1x)).abs();
      // The tangent lengths bound the curve's length.
      final curveLength = max(
        chord,
        (sqrt(m1x * m1x + m1y * m1y) + sqrt(m2x * m2x + m2y * m2y)) / 2,
      );
      final steps = max(
        1,
        max(
          ((curveLength + turn * halfWidth) * density * 1.1).ceil(),
          (turn / _kMaxTurn).ceil(),
        ),
      ).clamp(1, 4096);
      final last = i == n - 2;
      final count = last ? steps + 1 : steps;
      for (var k = 0; k < count; k++) {
        final u = k / steps;
        final u2 = u * u, u3 = u2 * u;
        final h00 = 2 * u3 - 3 * u2 + 1;
        final h10 = u3 - 2 * u2 + u;
        final h01 = -2 * u3 + 3 * u2;
        final h11 = u3 - u2;
        final px = h00 * x1 + h10 * m1x + h01 * x2 + h11 * m2x;
        final py = h00 * y1 + h10 * m1y + h01 * y2 + h11 * m2y;
        final dh00 = 6 * u2 - 6 * u;
        final dh10 = 3 * u2 - 4 * u + 1;
        final dh01 = -6 * u2 + 6 * u;
        final dh11 = 3 * u2 - 2 * u;
        var tx = dh00 * x1 + dh10 * m1x + dh01 * x2 + dh11 * m2x;
        var ty = dh00 * y1 + dh10 * m1y + dh01 * y2 + dh11 * m2y;
        if (tx * tx + ty * ty < 1e-24) {
          tx = x2 - x1;
          ty = y2 - y1;
        }
        samples.add(
          px,
          py,
          pressure[i] + (pressure[i + 1] - pressure[i]) * u,
          tilt[i] + (tilt[i + 1] - tilt[i]) * u,
          speed[i] + (speed[i + 1] - speed[i]) * u,
          atan2(ty, tx),
        );
      }
    }
    return samples..trim();
  }

  double _d2(int a, int b) => _dist2(x[a], y[a], x[b], y[b]);
}

double _dist2(double ax, double ay, double bx, double by) {
  final dx = bx - ax;
  final dy = by - ay;
  return dx * dx + dy * dy;
}

/// Receives an outline: a Flutter [Path] or SVG path data.
abstract class OutlineSink {
  void moveTo(double x, double y);
  void lineTo(double x, double y);

  /// An arc of the circle at ([cx], [cy]) with radius [r], from angle
  /// [start] over [sweep] radians, joined to the current point by a line.
  void arc(double cx, double cy, double r, double start, double sweep);
  void close();
}

class PathOutlineSink implements OutlineSink {
  final Path path = Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void arc(double cx, double cy, double r, double start, double sweep) =>
      path.arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start,
        sweep,
        false,
      );

  @override
  void close() => path.close();
}

/// SVG path data, shifted by [offset] (the stroke's origin).
class SvgOutlineSink implements OutlineSink {
  SvgOutlineSink([this.offset = Offset.zero]);

  final Offset offset;
  final StringBuffer buffer = StringBuffer();
  double _x = 0, _y = 0;

  String _n(double value) {
    final text = value.toStringAsFixed(3);
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }

  String _point(double x, double y) =>
      '${_n(x + offset.dx)} ${_n(y + offset.dy)}';

  void _sep() {
    if (buffer.isNotEmpty) buffer.write(' ');
  }

  @override
  void moveTo(double x, double y) {
    _sep();
    buffer.write('M ${_point(x, y)}');
    _x = x;
    _y = y;
  }

  @override
  void lineTo(double x, double y) {
    _sep();
    buffer.write('L ${_point(x, y)}');
    _x = x;
    _y = y;
  }

  @override
  void arc(double cx, double cy, double r, double start, double sweep) {
    final sx = cx + cos(start) * r, sy = cy + sin(start) * r;
    if ((sx - _x).abs() > 1e-9 || (sy - _y).abs() > 1e-9) lineTo(sx, sy);
    // Quarter arcs: an SVG arc of exactly 180° is ambiguous.
    final parts = max(1, (sweep.abs() / (pi / 2)).ceil());
    for (var i = 1; i <= parts; i++) {
      final angle = start + sweep * i / parts;
      final x = cx + cos(angle) * r, y = cy + sin(angle) * r;
      _sep();
      buffer.write(
        'A ${_n(r)} ${_n(r)} 0 0 ${sweep > 0 ? 1 : 0} ${_point(x, y)}',
      );
      _x = x;
      _y = y;
    }
  }

  @override
  void close() {
    _sep();
    buffer.write('Z');
  }

  @override
  String toString() => buffer.toString();
}

/// The filled outline of [points] drawn with [def], relative to [origin].
Path buildOutline(
  List<PathPoint> points,
  BrushDefinition def,
  double strokeWidth, {
  required double zoom,
  required Offset origin,
}) {
  final geometry = StrokeGeometry.build(
    points,
    def,
    strokeWidth,
    zoom: zoom,
    origin: origin,
  );
  return outlineOf(geometry, def, strokeWidth);
}

/// The filled outline of [geometry].
Path outlineOf(
  StrokeGeometry geometry,
  BrushDefinition def,
  double strokeWidth,
) {
  final sink = PathOutlineSink();
  writeOutline(sink, geometry, def, strokeWidth);
  return sink.path;
}

/// Writes the filled outline of [geometry] to [sink].
void writeOutline(
  OutlineSink sink,
  StrokeGeometry geometry,
  BrushDefinition def,
  double strokeWidth,
) {
  final n = geometry.length;
  if (n == 0) return;
  if (n == 1) {
    _addDisc(sink, geometry.x[0], geometry.y[0], geometry.width[0] / 2);
    return;
  }
  final dash = def.dash;
  if (dash.gap > 0) {
    if (dash.length <= 0) {
      _addDots(sink, geometry, (dash.gap + 1) * strokeWidth);
    } else {
      _addDashes(
        sink,
        geometry,
        dash.length * strokeWidth,
        dash.gap * strokeWidth,
      );
    }
    return;
  }
  _addRange(sink, geometry, 0, n - 1);
}

/// The centerline of a hairline stroke, relative to [origin].
Path buildCenterline(
  List<PathPoint> points, {
  required double zoom,
  required Offset origin,
}) {
  final sink = PathOutlineSink();
  writeCenterline(sink, hairlineGeometry(points, zoom: zoom, origin: origin));
  return sink.path;
}

/// The sampled centerline of a hairline stroke.
StrokeGeometry hairlineGeometry(
  List<PathPoint> points, {
  required double zoom,
  required Offset origin,
}) => StrokeGeometry.build(
  points,
  const BrushDefinition(width: BrushWidth(pressureGamma: 0)),
  0,
  zoom: zoom,
  origin: origin,
);

void writeCenterline(OutlineSink sink, StrokeGeometry geometry) {
  if (geometry.isEmpty) return;
  sink.moveTo(geometry.x[0], geometry.y[0]);
  if (geometry.length == 1) {
    sink.lineTo(geometry.x[0], geometry.y[0]);
  }
  for (var i = 1; i < geometry.length; i++) {
    sink.lineTo(geometry.x[i], geometry.y[i]);
  }
}

/// A full circle wound the same way as [_addPiece].
void _addDisc(OutlineSink sink, double cx, double cy, double r) {
  sink.moveTo(cx + r, cy);
  sink.arc(cx, cy, r, 0, -pi);
  sink.arc(cx, cy, r, pi, -pi);
  sink.close();
}

/// Whether sample [i] curls tighter than half its width, where the inner
/// offset would fold back on itself.
bool _isTight(StrokeGeometry g, int i) {
  if (i <= 0 || i >= g.length - 1) return false;
  final ds = g.arc[i + 1] - g.arc[i - 1];
  final turn = _wrapAngle(g.angle[i + 1] - g.angle[i - 1]).abs();
  final halfWidth = g.width[i] / 2;
  if (turn > 1e-9 && ds / turn < halfWidth * 1.05) return true;
  // A width that changes faster than the arc also folds the outline.
  return (g.width[i + 1] - g.width[i - 1]).abs() > ds * 2;
}

/// Adds samples [from]..[to] as capped pieces and discs at tight spots.
void _addRange(OutlineSink path, StrokeGeometry g, int from, int to) {
  var start = from;
  for (var i = from; i <= to; i++) {
    if (_isTight(g, i)) {
      if (i - 1 > start) {
        _addPiece(path, g, start, i - 1);
      } else if (i - 1 == start) {
        _addDisc(path, g.x[start], g.y[start], g.width[start] / 2);
      }
      _addDisc(path, g.x[i], g.y[i], g.width[i] / 2);
      start = i + 1;
    }
  }
  if (to > start) {
    _addPiece(path, g, start, to);
  } else if (to == start) {
    _addDisc(path, g.x[start], g.y[start], g.width[start] / 2);
  }
}

/// Left side forward, round end cap, right side back, round start cap.
void _addPiece(OutlineSink path, StrokeGeometry g, int from, int to) {
  double lx(int i) => g.x[i] - sin(g.angle[i]) * g.width[i] / 2;
  double ly(int i) => g.y[i] + cos(g.angle[i]) * g.width[i] / 2;
  double rx(int i) => g.x[i] + sin(g.angle[i]) * g.width[i] / 2;
  double ry(int i) => g.y[i] - cos(g.angle[i]) * g.width[i] / 2;

  path.moveTo(lx(from), ly(from));
  for (var i = from + 1; i <= to; i++) {
    path.lineTo(lx(i), ly(i));
  }
  _cap(path, g, to, g.angle[to] + pi / 2);
  for (var i = to - 1; i >= from; i--) {
    path.lineTo(rx(i), ry(i));
  }
  _cap(path, g, from, g.angle[from] - pi / 2);
  path.close();
}

void _cap(OutlineSink sink, StrokeGeometry g, int i, double start) =>
    sink.arc(g.x[i], g.y[i], g.width[i] / 2, start, -pi);

/// Position and width at arc length [s], from sample [hint] on.
(double, double, double, int) _at(StrokeGeometry g, double s, int hint) {
  var i = hint;
  while (i < g.length - 1 && g.arc[i + 1] < s) {
    i++;
  }
  if (i >= g.length - 1) {
    final last = g.length - 1;
    return (g.x[last], g.y[last], g.width[last], last);
  }
  final span = g.arc[i + 1] - g.arc[i];
  final t = span <= 0 ? 0.0 : ((s - g.arc[i]) / span).clamp(0.0, 1.0);
  return (
    g.x[i] + (g.x[i + 1] - g.x[i]) * t,
    g.y[i] + (g.y[i + 1] - g.y[i]) * t,
    g.width[i] + (g.width[i + 1] - g.width[i]) * t,
    i,
  );
}

void _addDots(OutlineSink path, StrokeGeometry g, double period) {
  if (period <= 0) return;
  final total = g.arcLength;
  var hint = 0;
  for (var s = 0.0; s <= total + 1e-9; s += period) {
    final (x, y, w, i) = _at(g, s, hint);
    hint = i;
    _addDisc(path, x, y, w / 2);
  }
}

void _addDashes(OutlineSink path, StrokeGeometry g, double length, double gap) {
  final period = length + gap;
  if (period <= 0) return;
  final total = g.arcLength;
  var i = 0;
  for (var s = 0.0; s <= total; s += period) {
    final end = s + length;
    while (i < g.length - 1 && g.arc[i] < s) {
      i++;
    }
    var j = i;
    while (j < g.length - 1 && g.arc[j + 1] <= end) {
      j++;
    }
    _addRange(path, g, i, j);
    i = j;
  }
}
