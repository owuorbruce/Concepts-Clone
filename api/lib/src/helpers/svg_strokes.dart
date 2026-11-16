import 'dart:math';

import 'package:dart_leap/dart_leap.dart';
import 'package:path_parsing/path_parsing.dart';
import 'package:xml/xml.dart';

import '../models/element.dart';
import '../models/point.dart';
import '../models/property.dart';

/// Largest distance, in viewBox units, between a curve and the lines that
/// replace it.
const kSvgStrokeTolerance = 0.05;

/// Largest distance, in target units, between two points of a stroke, so
/// the eraser can cut it anywhere.
const kSvgStrokeMaxSpacing = 6.0;

const _shapes = {'rect', 'circle', 'ellipse', 'line', 'polygon', 'path'};

/// The SVG [svg] drawn into [target] as pen strokes, or null if it uses
/// anything this converter doesn't support.
///
/// Supported: `rect` (with `rx`, `ry`), `circle`, `ellipse`, `line`,
/// `polygon` and `path`, filled and stroked with hex colors, `stroke-width`,
/// `stroke-dasharray` and the opacity attributes. Every outline becomes one
/// [PenElement] with constant width; a closed filled outline keeps its fill.
/// Transforms, groups, styles, references, images, text and gradients give
/// null, so the caller can keep the original SVG.
List<PenElement>? svgToPenElements(String svg, Rectangle<double> target) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(svg);
  } on XmlException {
    return null;
  }
  final root = document.rootElement;
  if (root.name.local != 'svg' || !_supportedAttributes(root)) return null;
  final viewBox = _viewBox(root);
  if (viewBox == null || viewBox.width <= 0 || viewBox.height <= 0) {
    return null;
  }
  final sx = target.width / viewBox.width;
  final sy = target.height / viewBox.height;
  final scale = (sx + sy) / 2;
  Point<double> toTarget(Point<double> p) => Point(
    target.left + (p.x - viewBox.left) * sx,
    target.top + (p.y - viewBox.top) * sy,
  );

  final result = <PenElement>[];
  for (final element in root.childElements) {
    final name = element.name.local;
    if (!_shapes.contains(name) || !_supportedAttributes(element)) {
      return null;
    }
    if (element.childElements.isNotEmpty) return null;
    final style = _Style.of(element, root);
    if (style == null) return null;
    final outlines = _outlines(element);
    if (outlines == null) return null;

    final strokeWidth = style.strokeWidth * scale;
    final hasStroke = style.stroke != null && strokeWidth > 0;
    final dashes = style.dashArray?.map((e) => e * scale).toList();
    for (final outline in outlines) {
      if (outline.points.length < 2) continue;
      final points = [
        ...outline.points.map(toTarget),
        if (outline.closed) toTarget(outline.points.first),
      ];
      final fill = outline.closed ? style.fill : null;
      PenElement pen(
        List<Point<double>> points, {
        SRGBColor? stroke,
        SRGBColor? fill,
      }) => PenElement(
        points: [for (final p in _resample(points)) PathPoint(p.x, p.y, 1)],
        property: PenProperty(
          strokeWidth: strokeWidth,
          thinning: 0,
          smoothing: 0,
          streamline: 0,
          paint: ElementPaint.solid(color: stroke ?? SRGBColor.transparent),
          fillPaint: ElementPaint.solid(color: fill ?? SRGBColor.transparent),
        ),
      );

      if (hasStroke && dashes != null) {
        if (fill != null) result.add(pen(points, fill: fill));
        for (final dash in _dash(points, dashes)) {
          result.add(pen(dash, stroke: style.stroke));
        }
      } else if (hasStroke || fill != null) {
        result.add(
          pen(points, stroke: hasStroke ? style.stroke : null, fill: fill),
        );
      }
    }
  }
  return result;
}

class _Outline {
  _Outline(this.points, {this.closed = false});

  final List<Point<double>> points;
  bool closed;
}

/// Presentation attributes this converter understands. Any other attribute
/// that could change the drawing makes the SVG unsupported.
bool _supportedAttributes(XmlElement element) {
  for (final attribute in element.attributes) {
    final name = attribute.name.local;
    if (name == 'transform' || name == 'style' || name == 'class') {
      return false;
    }
    if (name == 'href' || name == 'clip-path' || name == 'mask') return false;
    if (name == 'filter') return false;
    if (attribute.value.contains('url(')) return false;
  }
  return true;
}

class _Style {
  const _Style({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.dashArray,
  });

  final SRGBColor? fill, stroke;
  final double strokeWidth;
  final List<double>? dashArray;

  /// The style of [element]; attributes missing on it come from [root].
  /// Returns null for an unsupported value.
  static _Style? of(XmlElement element, XmlElement root) {
    String? read(String name) =>
        element.getAttribute(name) ?? root.getAttribute(name);
    double? number(String name, double fallback) {
      final value = read(name);
      if (value == null) return fallback;
      return double.tryParse(value.trim());
    }

    final opacity = number('opacity', 1);
    final fillOpacity = number('fill-opacity', 1);
    final strokeOpacity = number('stroke-opacity', 1);
    final strokeWidth = number('stroke-width', 1);
    if (opacity == null ||
        fillOpacity == null ||
        strokeOpacity == null ||
        strokeWidth == null) {
      return null;
    }
    final fill = _color(read('fill') ?? '#000000');
    final stroke = _color(read('stroke') ?? 'none');
    if (fill == null || stroke == null) return null;
    final dashValue = read('stroke-dasharray')?.trim();
    List<double>? dashArray;
    if (dashValue != null && dashValue.isNotEmpty && dashValue != 'none') {
      final parts = dashValue
          .split(RegExp(r'[\s,]+'))
          .where((e) => e.isNotEmpty)
          .map(double.tryParse)
          .toList();
      if (parts.any((e) => e == null || e < 0)) return null;
      final values = parts.cast<double>();
      if (values.fold<double>(0, (a, b) => a + b) > 0) {
        dashArray = values.length.isOdd ? [...values, ...values] : values;
      }
    }
    return _Style(
      fill: fill.$1 ? null : _withAlpha(fill.$2, opacity * fillOpacity),
      stroke: stroke.$1 ? null : _withAlpha(stroke.$2, opacity * strokeOpacity),
      strokeWidth: strokeWidth,
      dashArray: dashArray,
    );
  }
}

/// Parses `none`, `#rgb` or `#rrggbb`: (isNone, color), or null for any
/// other format.
(bool, SRGBColor)? _color(String value) {
  value = value.trim();
  if (value == 'none') return (true, SRGBColor.transparent);
  final match = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').firstMatch(value);
  if (match == null) return null;
  var hex = match.group(1)!;
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  return (false, SRGBColor(0xFF000000 | int.parse(hex, radix: 16)));
}

SRGBColor? _withAlpha(SRGBColor color, double opacity) {
  final alpha = (opacity.clamp(0.0, 1.0) * 255).round();
  if (alpha == 0) return null;
  return SRGBColor((alpha << 24) | (color.value & 0xFFFFFF));
}

Rectangle<double>? _viewBox(XmlElement svg) {
  final viewBox = svg.getAttribute('viewBox');
  if (viewBox != null) {
    final parts = viewBox
        .trim()
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    if (parts.length != 4 || parts.any((e) => e == null)) return null;
    return Rectangle(parts[0]!, parts[1]!, parts[2]!, parts[3]!);
  }
  double? size(String name) {
    final value = svg.getAttribute(name);
    return value == null ? null : double.tryParse(value.replaceAll('px', ''));
  }

  final width = size('width'), height = size('height');
  if (width == null || height == null) return null;
  return Rectangle(0, 0, width, height);
}

/// The outlines of a shape element in viewBox units, or null if one of its
/// attributes cannot be read.
List<_Outline>? _outlines(XmlElement element) {
  double? attr(String name, [double? fallback]) {
    final value = element.getAttribute(name);
    if (value == null) return fallback;
    return double.tryParse(value.trim());
  }

  switch (element.name.local) {
    case 'rect':
      final x = attr('x', 0), y = attr('y', 0);
      final width = attr('width'), height = attr('height');
      if (x == null || y == null || width == null || height == null) {
        return null;
      }
      if (width <= 0 || height <= 0) return const [];
      var rx = attr('rx'), ry = attr('ry');
      if ((element.getAttribute('rx') != null && rx == null) ||
          (element.getAttribute('ry') != null && ry == null)) {
        return null;
      }
      rx ??= ry ?? 0;
      ry ??= rx;
      rx = rx.clamp(0, width / 2).toDouble();
      ry = ry.clamp(0, height / 2).toDouble();
      return [_Outline(_rect(x, y, width, height, rx, ry), closed: true)];
    case 'circle':
      final cx = attr('cx', 0), cy = attr('cy', 0), r = attr('r');
      if (cx == null || cy == null || r == null) return null;
      if (r <= 0) return const [];
      return [_Outline(_ellipse(cx, cy, r, r), closed: true)];
    case 'ellipse':
      final cx = attr('cx', 0), cy = attr('cy', 0);
      final rx = attr('rx'), ry = attr('ry');
      if (cx == null || cy == null || rx == null || ry == null) return null;
      if (rx <= 0 || ry <= 0) return const [];
      return [_Outline(_ellipse(cx, cy, rx, ry), closed: true)];
    case 'line':
      final x1 = attr('x1', 0), y1 = attr('y1', 0);
      final x2 = attr('x2', 0), y2 = attr('y2', 0);
      if (x1 == null || y1 == null || x2 == null || y2 == null) return null;
      return [
        _Outline([Point(x1, y1), Point(x2, y2)]),
      ];
    case 'polygon':
      final values = (element.getAttribute('points') ?? '')
          .trim()
          .split(RegExp(r'[\s,]+'))
          .where((e) => e.isNotEmpty)
          .map(double.tryParse)
          .toList();
      if (values.length.isOdd || values.any((e) => e == null)) return null;
      return [
        _Outline([
          for (var i = 0; i < values.length; i += 2)
            Point(values[i]!, values[i + 1]!),
        ], closed: true),
      ];
    case 'path':
      final proxy = _FlatteningProxy();
      try {
        writeSvgPathDataToPath(element.getAttribute('d'), proxy);
      } on Object {
        return null;
      }
      return proxy.outlines;
  }
  return null;
}

/// Segments that keep a circle of [radius] within the tolerance, for an
/// arc of [sweep] radians.
int _arcSegments(double radius, double sweep) {
  if (radius <= kSvgStrokeTolerance) return 1;
  final step = 2 * acos(1 - kSvgStrokeTolerance / radius);
  return max(1, (sweep / step).ceil());
}

List<Point<double>> _ellipse(double cx, double cy, double rx, double ry) {
  final n = max(8, _arcSegments(max(rx, ry), 2 * pi));
  return [
    for (var i = 0; i < n; i++)
      Point(cx + rx * cos(2 * pi * i / n), cy + ry * sin(2 * pi * i / n)),
  ];
}

List<Point<double>> _rect(
  double x,
  double y,
  double width,
  double height,
  double rx,
  double ry,
) {
  if (rx <= 0 || ry <= 0) {
    return [
      Point(x, y),
      Point(x + width, y),
      Point(x + width, y + height),
      Point(x, y + height),
    ];
  }
  final n = _arcSegments(max(rx, ry), pi / 2);
  final points = <Point<double>>[];
  void corner(double cx, double cy, double start) {
    for (var i = 0; i <= n; i++) {
      final angle = start + (pi / 2) * i / n;
      points.add(Point(cx + rx * cos(angle), cy + ry * sin(angle)));
    }
  }

  // Clockwise from the top edge, as SVG draws a rect.
  corner(x + width - rx, y + ry, -pi / 2);
  corner(x + width - rx, y + height - ry, 0);
  corner(x + rx, y + height - ry, pi / 2);
  corner(x + rx, y + ry, pi);
  return points;
}

/// Receives path commands and flattens cubics into lines.
class _FlatteningProxy implements PathProxy {
  final outlines = <_Outline>[];
  _Outline? _current;
  Point<double> _point = const Point(0, 0);
  Point<double> _start = const Point(0, 0);

  _Outline get _active {
    final current = _current;
    if (current != null && !current.closed) return current;
    // Drawing on after a close starts a new outline at the subpath start.
    final outline = _Outline([_start]);
    outlines.add(outline);
    return _current = outline;
  }

  @override
  void moveTo(double x, double y) {
    _point = _start = Point(x, y);
    final outline = _Outline([_point]);
    outlines.add(outline);
    _current = outline;
  }

  @override
  void lineTo(double x, double y) {
    final outline = _active;
    _point = Point(x, y);
    outline.points.add(_point);
  }

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    final outline = _active;
    final p0 = _point;
    final p1 = Point(x1, y1), p2 = Point(x2, y2), p3 = Point(x3, y3);
    // Wang's formula: enough segments to stay within the tolerance.
    final d1 = p0 - p1 * 2 + p2;
    final d2 = p1 - p2 * 2 + p3;
    final m = max(d1.magnitude, d2.magnitude);
    final n = max(1, sqrt(3 * m / (4 * kSvgStrokeTolerance)).ceil());
    for (var i = 1; i <= n; i++) {
      final t = i / n, u = 1 - t;
      outline.points.add(
        p0 * (u * u * u) +
            p1 * (3 * u * u * t) +
            p2 * (3 * u * t * t) +
            p3 * (t * t * t),
      );
    }
    _point = p3;
  }

  @override
  void close() {
    final current = _current;
    if (current == null || current.closed) return;
    // A closing point on the start is the same as the close itself.
    if (current.points.length > 1 &&
        current.points.last == current.points.first) {
      current.points.removeLast();
    }
    current.closed = true;
    _point = _start;
  }
}

/// [points] with points added so no two are more than
/// [kSvgStrokeMaxSpacing] apart.
List<Point<double>> _resample(List<Point<double>> points) {
  if (points.isEmpty) return points;
  final result = [points.first];
  for (var i = 1; i < points.length; i++) {
    final from = points[i - 1], to = points[i];
    final steps = ((to - from).magnitude / kSvgStrokeMaxSpacing).ceil();
    for (var j = 1; j < steps; j++) {
      result.add(from + (to - from) * (j / steps));
    }
    result.add(to);
  }
  return result;
}

/// The dashes of the polyline [points] for [pattern] (dash, gap, dash, …).
List<List<Point<double>>> _dash(
  List<Point<double>> points,
  List<double> pattern,
) {
  final dashes = <List<Point<double>>>[];
  var index = 0;
  var remaining = pattern[0];
  var drawing = true;
  List<Point<double>>? current = [points.first];
  for (var i = 1; i < points.length; i++) {
    var from = points[i - 1];
    final to = points[i];
    var length = (to - from).magnitude;
    while (length > 0) {
      if (remaining >= length) {
        remaining -= length;
        current?.add(to);
        break;
      }
      final split = from + (to - from) * (remaining / length);
      length -= remaining;
      from = split;
      if (drawing) {
        current!.add(split);
        if (current.length > 1) dashes.add(current);
        current = null;
      } else {
        current = [split];
      }
      drawing = !drawing;
      index = (index + 1) % pattern.length;
      remaining = pattern[index];
    }
  }
  if (drawing && current != null && current.length > 1) dashes.add(current);
  return dashes;
}
