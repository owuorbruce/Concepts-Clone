import 'dart:math';
import 'dart:ui' show Tangent;

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Custom vector glyphs of aMaze.
///
/// Tool and control glyphs are drawn on a 24-unit grid with the light,
/// round-capped 1.5-unit stroke of Phosphor Light, so they sit naturally
/// next to it. Brush glyphs are small illustrated strokes that show how
/// each brush lays down ink.
enum AmazeGlyph {
  pen,
  fountain,
  dynamicPen,
  fixedWidth,
  wire,
  softPencil,
  hardPencil,
  marker,
  watercolor,
  airbrush,
  fill,
  dotted,
  lasso,
  nudge,
  slice,
  hardMask,
  softMask,
  rotate,
  size,
  opacity,
  smoothing,
  brushLibrary,
  tilingPatterns,
  waterful,
  crosshatching,
  inkBlot;

  /// Whether the glyph is an illustrated brush stroke.
  bool get isBrush => index <= AmazeGlyph.dotted.index;

  /// Whether the glyph previews a brush pack.
  bool get isPack => index >= AmazeGlyph.tilingPatterns.index;
}

/// An icon of the aMaze interface: a Phosphor icon or an aMaze glyph.
sealed class AmazeIconData {
  const AmazeIconData();
}

/// A Phosphor icon with an optional filled variant for active states.
class PhosphorAmazeIcon extends AmazeIconData {
  const PhosphorAmazeIcon(this.light, [this.fill]);

  final PhosphorIconData light;
  final PhosphorIconData? fill;
}

/// One of the custom [AmazeGlyph]s.
class GlyphAmazeIcon extends AmazeIconData {
  const GlyphAmazeIcon(this.glyph);

  final AmazeGlyph glyph;
}

/// One place for the icons of the aMaze editor, so an action looks the same
/// everywhere. Established Phosphor icons are kept where they already work.
abstract final class AmazeIcons {
  static const layers = PhosphorAmazeIcon(
    PhosphorIconsLight.stack,
    PhosphorIconsFill.stack,
  );
  static const brushLibrary = GlyphAmazeIcon(AmazeGlyph.brushLibrary);
  static const toolCatalog = PhosphorAmazeIcon(
    PhosphorIconsLight.squaresFour,
    PhosphorIconsFill.squaresFour,
  );
  static const color = PhosphorAmazeIcon(
    PhosphorIconsLight.palette,
    PhosphorIconsFill.palette,
  );
  static const size = GlyphAmazeIcon(AmazeGlyph.size);
  static const opacity = GlyphAmazeIcon(AmazeGlyph.opacity);
  static const smoothing = GlyphAmazeIcon(AmazeGlyph.smoothing);
  static const undo = PhosphorAmazeIcon(
    PhosphorIconsLight.arrowCounterClockwise,
  );
  static const redo = PhosphorAmazeIcon(PhosphorIconsLight.arrowClockwise);
  static const settings = PhosphorAmazeIcon(
    PhosphorIconsLight.gearSix,
    PhosphorIconsFill.gearSix,
  );
  static const import = PhosphorAmazeIcon(
    PhosphorIconsLight.arrowSquareIn,
    PhosphorIconsFill.arrowSquareIn,
  );
  static const export = PhosphorAmazeIcon(
    PhosphorIconsLight.export,
    PhosphorIconsFill.export,
  );
  static const documents = PhosphorAmazeIcon(
    PhosphorIconsLight.folder,
    PhosphorIconsFill.folder,
  );
  static const grid = PhosphorAmazeIcon(
    PhosphorIconsLight.gridFour,
    PhosphorIconsFill.gridFour,
  );
  static const ruler = PhosphorAmazeIcon(
    PhosphorIconsLight.ruler,
    PhosphorIconsFill.ruler,
  );
  static const selection = GlyphAmazeIcon(AmazeGlyph.lasso);
  static const toolOptions = PhosphorAmazeIcon(
    PhosphorIconsLight.slidersHorizontal,
    PhosphorIconsFill.slidersHorizontal,
  );
  static const zoom = PhosphorAmazeIcon(
    PhosphorIconsLight.magnifyingGlass,
    PhosphorIconsFill.magnifyingGlass,
  );
  static const slotOptions = PhosphorAmazeIcon(
    PhosphorIconsLight.gearSix,
    PhosphorIconsFill.gearSix,
  );
  static const unavailable = PhosphorAmazeIcon(PhosphorIconsLight.lockSimple);
}

/// Shows an [AmazeIconData] in the current icon color.
class AmazeIcon extends StatelessWidget {
  const AmazeIcon(
    this.icon, {
    super.key,
    this.size = 24,
    this.color,
    this.filled = false,
  });

  final AmazeIconData icon;
  final double size;
  final Color? color;

  /// Use the filled variant, for active states, if the icon has one.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? IconTheme.of(context).color;
    final data = icon;
    return switch (data) {
      PhosphorAmazeIcon() => PhosphorIcon(
        filled ? (data.fill ?? data.light) : data.light,
        size: size,
        color: color,
      ),
      GlyphAmazeIcon() => AmazeGlyphIcon(
        data.glyph,
        size: size,
        color: color,
      ),
    };
  }
}

/// A square [AmazeGlyph], sharp at any size because it is painted as vectors.
class AmazeGlyphIcon extends StatelessWidget {
  const AmazeGlyphIcon(this.glyph, {super.key, this.size = 24, this.color});

  final AmazeGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color =
        this.color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: AmazeGlyphPainter(glyph, color)),
    );
  }
}

/// A wide preview of a brush or brush pack, for the brush library.
class AmazeBrushPreview extends StatelessWidget {
  const AmazeBrushPreview(this.glyph, {super.key, this.color});

  final AmazeGlyph glyph;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color =
        this.color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    return CustomPaint(
      painter: AmazeGlyphPainter(glyph, color, wide: true),
      size: Size.infinite,
    );
  }
}

/// Paints an [AmazeGlyph]. In [wide] mode brushes are drawn as a long
/// stroke across the whole box instead of inside a square.
class AmazeGlyphPainter extends CustomPainter {
  const AmazeGlyphPainter(this.glyph, this.color, {this.wide = false});

  final AmazeGlyph glyph;
  final Color color;
  final bool wide;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (glyph.isBrush || glyph.isPack) {
      final Rect box;
      if (wide) {
        box = Offset.zero & size;
      } else {
        final side = min(size.width, size.height);
        box = Alignment.center.inscribe(Size.square(side), Offset.zero & size);
      }
      _BrushArtist(canvas, box, color, wide: wide).paint(glyph);
      return;
    }
    final side = min(size.width, size.height);
    final origin = Alignment.center.inscribe(
      Size.square(side),
      Offset.zero & size,
    );
    canvas.save();
    canvas.translate(origin.left, origin.top);
    canvas.scale(side / 24);
    _LineArtist(canvas, color).paint(glyph);
    canvas.restore();
  }

  @override
  bool shouldRepaint(AmazeGlyphPainter oldDelegate) {
    return oldDelegate.glyph != glyph ||
        oldDelegate.color != color ||
        oldDelegate.wide != wide;
  }
}

/// Draws the line glyphs on the 24-unit grid.
class _LineArtist {
  _LineArtist(this.canvas, this.color);

  final Canvas canvas;
  final Color color;

  Paint get _stroke => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()..color = color;

  Path get _wave => Path()
    ..moveTo(3, 15)
    ..cubicTo(7, 5, 17, 21, 21, 9);

  void paint(AmazeGlyph glyph) {
    switch (glyph) {
      case AmazeGlyph.lasso:
        _lasso();
      case AmazeGlyph.nudge:
        _nudge();
      case AmazeGlyph.slice:
        _slice();
      case AmazeGlyph.hardMask:
        _hardMask();
      case AmazeGlyph.softMask:
        _softMask();
      case AmazeGlyph.rotate:
        _rotate();
      case AmazeGlyph.size:
        _size();
      case AmazeGlyph.opacity:
        _opacity();
      case AmazeGlyph.smoothing:
        _smoothing();
      case AmazeGlyph.brushLibrary:
        _brushLibrary();
      default:
        break;
    }
  }

  void _arrowHead(Offset tip, Offset direction) {
    final unit = direction / direction.distance;
    final normal = Offset(-unit.dy, unit.dx);
    final back = tip - unit * 3;
    final path = Path()
      ..moveTo(back.dx + normal.dx * 2.4, back.dy + normal.dy * 2.4)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(back.dx - normal.dx * 2.4, back.dy - normal.dy * 2.4);
    canvas.drawPath(path, _stroke);
  }

  void _lasso() {
    final loop = Rect.fromCenter(
      center: const Offset(12.5, 9.5),
      width: 17,
      height: 11,
    );
    final path = Path()
      ..addArc(loop, 140 * pi / 180, 330 * pi / 180)
      ..cubicTo(9.5, 17.5, 6, 18, 7, 21);
    canvas.drawPath(path, _stroke);
    canvas.drawCircle(const Offset(7, 21), 1.3, _fill);
  }

  void _nudge() {
    final arch = Path()
      ..moveTo(3, 15)
      ..quadraticBezierTo(12, 5, 21, 15);
    canvas.drawPath(arch, _stroke);
    canvas.drawLine(const Offset(12, 22), const Offset(12, 13), _stroke);
    _arrowHead(const Offset(12, 13), const Offset(0, -1));
  }

  void _slice() {
    canvas.drawLine(const Offset(3, 14), const Offset(9.5, 14), _stroke);
    canvas.drawLine(const Offset(14.5, 12), const Offset(21, 12), _stroke);
    canvas.drawLine(const Offset(14.5, 4), const Offset(9.5, 21), _stroke);
    final handle = _stroke..strokeWidth = 3;
    canvas.drawLine(const Offset(15.4, 1.5), const Offset(14.5, 4), handle);
  }

  void _hardMask() {
    final mask = RRect.fromRectAndRadius(
      const Rect.fromLTWH(9, 4, 6, 16),
      const Radius.circular(1.5),
    );
    canvas.save();
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(const Rect.fromLTWH(0, 0, 24, 24))
      ..addRRect(mask);
    canvas.clipPath(outside);
    canvas.drawPath(_wave, _stroke);
    canvas.restore();
    canvas.drawRRect(mask, _stroke);
    canvas.save();
    canvas.clipRRect(mask);
    final hatch = _stroke..strokeWidth = 1;
    for (var y = 2.0; y < 28; y += 4) {
      canvas.drawLine(Offset(8, y), Offset(16, y - 8), hatch);
    }
    canvas.restore();
  }

  void _softMask() {
    final paint = _stroke
      ..strokeWidth = 2.2
      ..shader = LinearGradient(
        colors: [color, color.withValues(alpha: 0)],
        stops: const [0.25, 0.95],
      ).createShader(const Rect.fromLTWH(3, 0, 18, 24));
    canvas.drawPath(_wave, paint);
  }

  void _rotate() {
    canvas.save();
    canvas.translate(12, 14.5);
    canvas.rotate(-0.35);
    final page = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 10, height: 7.5),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(page, _stroke);
    canvas.restore();
    final circle = Rect.fromCircle(center: const Offset(12, 13), radius: 9.5);
    const start = 200 * pi / 180;
    const sweep = 125 * pi / 180;
    canvas.drawArc(circle, start, sweep, false, _stroke);
    const end = start + sweep;
    final tip = Offset(12 + 9.5 * cos(end), 13 + 9.5 * sin(end));
    _arrowHead(tip, Offset(-sin(end), cos(end)));
  }

  void _size() {
    canvas.drawCircle(const Offset(4.5, 15.5), 1.5, _fill);
    canvas.drawCircle(const Offset(10, 14.5), 2.5, _stroke);
    canvas.drawCircle(const Offset(17.5, 12.5), 4.5, _stroke);
  }

  void _opacity() {
    const center = Offset(12, 12);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: 8)));
    canvas.drawRect(const Rect.fromLTWH(4, 4, 8, 16), _fill);
    final faint = _fill..color = color.withValues(alpha: 0.25);
    canvas.drawRect(const Rect.fromLTWH(12, 4, 8, 16), faint);
    canvas.restore();
    canvas.drawCircle(center, 8, _stroke);
  }

  void _smoothing() {
    final path = Path()
      ..moveTo(3, 15)
      ..lineTo(5, 10.5)
      ..lineTo(7, 15)
      ..lineTo(9, 10.5)
      ..lineTo(11, 13)
      ..quadraticBezierTo(15, 19, 21, 9);
    canvas.drawPath(path, _stroke);
  }

  void _brushLibrary() {
    final lines = [(7.0, 1.5), (12.0, 2.5), (17.5, 3.5)];
    for (final (y, width) in lines) {
      final paint = _stroke..strokeWidth = width;
      final path = Path()
        ..moveTo(5, y + 1)
        ..quadraticBezierTo(12, y - 2, 19, y + 0.5);
      canvas.drawPath(path, paint);
    }
  }
}

/// Draws illustrated brush strokes and brush pack previews inside [box].
class _BrushArtist {
  _BrushArtist(this.canvas, this.box, this.color, {required this.wide});

  final Canvas canvas;
  final Rect box;
  final Color color;
  final bool wide;

  /// Stroke unit: 1/24 of the box height, like the icon grid.
  double get unit => box.height / 24;

  Offset _at(double x, double y) {
    return Offset(box.left + box.width * x, box.top + box.height * y);
  }

  /// The center line every brush follows.
  Path get _path {
    final start = wide ? _at(0.08, 0.62) : _at(0.13, 0.75);
    final first = wide ? _at(0.32, 0.05) : _at(0.33, 0.17);
    final second = wide ? _at(0.6, 1.0) : _at(0.63, 0.92);
    final end = wide ? _at(0.92, 0.35) : _at(0.88, 0.25);
    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(first.dx, first.dy, second.dx, second.dy, end.dx, end.dy);
  }

  Paint _paint([double opacity = 1]) {
    return Paint()..color = color.withValues(alpha: color.a * opacity);
  }

  Paint _line(double width, [double opacity = 1]) {
    return _paint(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }

  /// Deterministic noise, so textured brushes look the same every frame.
  Random get _random => Random(7);

  List<Tangent> _samples(int count) {
    final metric = _path.computeMetrics().first;
    return [
      for (var i = 0; i <= count; i++)
        metric.getTangentForOffset(metric.length * i / count)!,
    ];
  }

  Offset _normal(Tangent tangent) {
    return Offset(-tangent.vector.dy, tangent.vector.dx);
  }

  void _ribbon(double Function(double t, Tangent tangent) width, Paint paint) {
    final samples = _samples(48);
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i < samples.length; i++) {
      final tangent = samples[i];
      final half = width(i / (samples.length - 1), tangent) / 2;
      final normal = _normal(tangent) * half;
      left.add(tangent.position + normal);
      right.add(tangent.position - normal);
    }
    final outline = Path()..addPolygon([...left, ...right.reversed], true);
    canvas.drawPath(outline, paint);
  }

  void paint(AmazeGlyph glyph) {
    final u = unit;
    switch (glyph) {
      case AmazeGlyph.pen:
        _ribbon((t, _) => u * (1.1 + 1.3 * sin(pi * t)), _paint());
      case AmazeGlyph.fountain:
        _ribbon((t, tangent) {
          final angle = tangent.angle;
          return u * (0.5 + 3.4 * sin(angle - pi / 4).abs());
        }, _paint());
      case AmazeGlyph.dynamicPen:
        _ribbon((t, _) => u * (0.4 + 4.2 * pow(1 - t, 1.3)), _paint());
      case AmazeGlyph.fixedWidth:
        canvas.drawPath(_path, _line(u * 2.2));
      case AmazeGlyph.wire:
        _wire(u);
      case AmazeGlyph.softPencil:
        _graphite(u, spread: 1.4, count: 220, opacity: 0.45);
      case AmazeGlyph.hardPencil:
        canvas.drawPath(_path, _line(u * 0.9, 0.85));
        _graphite(u, spread: 0.5, count: 60, opacity: 0.35);
      case AmazeGlyph.marker:
        _ribbon((t, _) => u * 4.4, _paint(0.72));
      case AmazeGlyph.watercolor:
        _watercolor(u);
      case AmazeGlyph.airbrush:
        _airbrush(u);
      case AmazeGlyph.fill:
        _fill(u);
      case AmazeGlyph.dotted:
        _dotted(u);
      case AmazeGlyph.tilingPatterns:
        _tiling(u);
      case AmazeGlyph.waterful:
        _watercolor(u);
        _dotted(u);
      case AmazeGlyph.crosshatching:
        _crosshatching(u);
      case AmazeGlyph.inkBlot:
        _inkBlot(u);
      default:
        break;
    }
  }

  void _wire(double u) {
    canvas.drawPath(_path, _line(u * 0.75));
    final samples = _samples(1);
    for (final tangent in samples) {
      canvas.drawCircle(tangent.position, u * 1.1, _paint());
    }
  }

  void _graphite(
    double u, {
    required double spread,
    required int count,
    required double opacity,
  }) {
    final random = _random;
    final metric = _path.computeMetrics().first;
    final paint = _line(u * 0.55, opacity)..strokeCap = StrokeCap.butt;
    for (var i = 0; i < count; i++) {
      final tangent = metric.getTangentForOffset(
        metric.length * random.nextDouble(),
      )!;
      final offset = (random.nextDouble() * 2 - 1) * spread * u;
      final start = tangent.position + _normal(tangent) * offset;
      final end = start + tangent.vector * (u * 1.2);
      canvas.drawLine(start, end, paint);
    }
  }

  void _watercolor(double u) {
    final random = _random;
    final samples = _samples(10);
    final wash = _paint(0.16);
    final edge = _line(u * 0.4, 0.22);
    for (final tangent in samples) {
      final radius = u * (2.6 + random.nextDouble() * 1.6);
      final jitter = _normal(tangent) * ((random.nextDouble() - 0.5) * u);
      canvas.drawCircle(tangent.position + jitter, radius, wash);
      canvas.drawCircle(tangent.position + jitter, radius, edge);
    }
  }

  void _airbrush(double u) {
    final core = _line(u * 3, 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 1.6);
    canvas.drawPath(_path, core);
    final random = _random;
    final metric = _path.computeMetrics().first;
    final speck = _paint(0.3);
    for (var i = 0; i < 160; i++) {
      final tangent = metric.getTangentForOffset(
        metric.length * random.nextDouble(),
      )!;
      final spread = (random.nextDouble() + random.nextDouble() - 1) * u * 4;
      final position = tangent.position + _normal(tangent) * spread;
      canvas.drawCircle(position, u * 0.3, speck);
    }
  }

  void _fill(double u) {
    final blob = Path()
      ..moveTo(_at(0.2, 0.6).dx, _at(0.2, 0.6).dy)
      ..cubicTo(
        _at(0.18, 0.25).dx,
        _at(0.18, 0.25).dy,
        _at(0.55, 0.08).dx,
        _at(0.55, 0.08).dy,
        _at(0.75, 0.2).dx,
        _at(0.75, 0.2).dy,
      )
      ..cubicTo(
        _at(0.95, 0.32).dx,
        _at(0.95, 0.32).dy,
        _at(0.88, 0.72).dx,
        _at(0.88, 0.72).dy,
        _at(0.65, 0.82).dx,
        _at(0.65, 0.82).dy,
      )
      ..cubicTo(
        _at(0.45, 0.92).dx,
        _at(0.45, 0.92).dy,
        _at(0.22, 0.88).dx,
        _at(0.22, 0.88).dy,
        _at(0.2, 0.6).dx,
        _at(0.2, 0.6).dy,
      )
      ..close();
    canvas.drawPath(blob, _paint(0.85));
    canvas.drawPath(blob, _line(u * 1.2));
  }

  void _dotted(double u) {
    final metric = _path.computeMetrics().first;
    final step = u * 3.4;
    for (var distance = 0.0; distance <= metric.length; distance += step) {
      final tangent = metric.getTangentForOffset(distance)!;
      canvas.drawCircle(tangent.position, u * 1.05, _paint());
    }
  }

  void _tiling(double u) {
    final paint = _line(u * 0.9);
    final cell = box.height / 3;
    for (var x = box.left + cell / 2; x < box.right; x += cell) {
      for (var y = box.top + cell / 2; y < box.bottom; y += cell) {
        final diamond = Path()
          ..moveTo(x, y - cell * 0.32)
          ..lineTo(x + cell * 0.32, y)
          ..lineTo(x, y + cell * 0.32)
          ..lineTo(x - cell * 0.32, y)
          ..close();
        canvas.drawPath(diamond, paint);
      }
    }
  }

  void _crosshatching(double u) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(box, Radius.circular(u * 3)));
    final paint = _line(u * 0.7, 0.8);
    final step = u * 3.2;
    final reach = box.height;
    for (var x = box.left - reach; x < box.right; x += step) {
      canvas.drawLine(
        Offset(x, box.bottom),
        Offset(x + reach, box.top),
        paint,
      );
    }
    for (var x = box.left; x < box.right + reach; x += step * 1.6) {
      canvas.drawLine(Offset(x, box.bottom), Offset(x - reach, box.top), paint);
    }
    canvas.restore();
  }

  void _inkBlot(double u) {
    final random = _random;
    final center = box.center;
    canvas.drawCircle(center, u * 5.5, _paint(0.9));
    for (var i = 0; i < 26; i++) {
      final angle = random.nextDouble() * 2 * pi;
      final distance = u * (6 + random.nextDouble() * 9);
      final direction = Offset(cos(angle) * 1.8, sin(angle));
      final position = center + direction * distance;
      canvas.drawCircle(position, u * (0.4 + random.nextDouble()), _paint());
    }
  }
}
