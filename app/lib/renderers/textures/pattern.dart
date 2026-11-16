part of 'texture.dart';

/// Most lines a pattern draws per direction, at any zoom.
const kMaxPatternLinesPerDirection = 400;

/// Screen spacing below which a pattern switches to a coarser level.
const kMinPatternSpacing = 8.0;

/// Screen spacing at which the finer level is fully faded in.
const kPatternFadeEndSpacing = 24.0;

/// Factor between two pattern levels.
const kPatternLevelFactor = 5.0;

// The finer level is drawn together with the next coarser one while it fades
// in. Split the budget so both together stay within the limit.
const _kMaxFineLines = 320;

/// The adaptive level the canvas draws a pattern at.
///
/// [multiplier] scales the whole pattern (spacing and stroke) and is a power
/// of [kPatternLevelFactor]. [fade] is the opacity of that level; below 1 the
/// next coarser level is drawn under it.
typedef PatternLevel = ({double multiplier, double fade});

double _patternLineCount(
  double extent,
  double box,
  int count,
  double space,
  double multiplier,
) {
  if (box <= 0 || count <= 0) return 0;
  final part = (box * count + space) * multiplier;
  return (extent / part + 2) * count;
}

/// Picks the pattern level for [pixelsPerUnit] screen pixels per pattern
/// unit. [size] is the area to fill in pattern units. Returns `null` when the
/// pattern has no lines or the scale is unusable.
@visibleForTesting
PatternLevel? patternLevel(
  PatternTexture texture,
  double pixelsPerUnit,
  Size size,
) {
  final hasX = texture.boxWidth > 0 && texture.boxXCount > 0;
  final hasY = texture.boxHeight > 0 && texture.boxYCount > 0;
  if (!hasX && !hasY) return null;
  if (!pixelsPerUnit.isFinite || pixelsPerUnit <= 0) return null;
  final box = hasX && hasY
      ? min(texture.boxWidth, texture.boxHeight)
      : hasX
      ? texture.boxWidth
      : texture.boxHeight;
  final width = size.width.isFinite ? size.width.abs() : 0.0;
  final height = size.height.isFinite ? size.height.abs() : 0.0;
  double lines(double multiplier) => max(
    _patternLineCount(
      width,
      texture.boxWidth,
      texture.boxXCount,
      texture.boxXSpace,
      multiplier,
    ),
    _patternLineCount(
      height,
      texture.boxHeight,
      texture.boxYCount,
      texture.boxYSpace,
      multiplier,
    ),
  );
  var multiplier = 1.0;
  // Bounded: each pass multiplies by 5, and the zoom range spans ~10^9.
  for (var i = 0; i < 64; i++) {
    if (box * multiplier * pixelsPerUnit >= kMinPatternSpacing &&
        lines(multiplier) <= _kMaxFineLines) {
      break;
    }
    multiplier *= kPatternLevelFactor;
  }
  final spacing = box * multiplier * pixelsPerUnit;
  final fade =
      ((spacing - kMinPatternSpacing) /
              (kPatternFadeEndSpacing - kMinPatternSpacing))
          .clamp(0.0, 1.0)
          .toDouble();
  return (multiplier: multiplier, fade: fade);
}

double _canvasScale(Canvas canvas) {
  final matrix = canvas.getTransform();
  return sqrt(matrix[0] * matrix[0] + matrix[1] * matrix[1]);
}

/// Draws a pattern texture.
///
/// [zoom] is the number of screen pixels per canvas unit. The pattern adapts
/// to it like a dot grid: when boxes get closer than [kMinPatternSpacing] on
/// screen it draws every fifth line instead (scaled up five times), fading
/// between levels, and never draws more than [kMaxPatternLinesPerDirection]
/// lines per direction. Without [zoom], the canvas transform is used.
void drawPatternTextureOnCanvas(
  PatternTexture texture,
  Canvas canvas,
  double scale,
  Offset offset,
  Size size, [
  Offset translation = .zero,
  bool extraLines = false,
  double? zoom,
]) {
  canvas.drawRect(
    Rect.fromLTWH(translation.dx, translation.dy, size.width, size.height),
    Paint()
      ..color = texture.boxColor.toColor()
      ..style = PaintingStyle.fill,
  );
  if (scale <= 0) return;
  final pixelsPerUnit = scale * (zoom ?? _canvasScale(canvas));
  final level = patternLevel(texture, pixelsPerUnit, size / scale);
  if (level == null) return;
  void draw(double multiplier) => _drawPatternLines(
    texture,
    canvas,
    scale,
    offset,
    size,
    translation,
    extraLines,
    multiplier,
    pixelsPerUnit,
  );
  if (level.fade >= 1) {
    draw(level.multiplier);
    return;
  }
  // Crossfade: the coarser level underneath, the finer one fading in on top.
  // A layer keeps patterns built from overlapping lines (dot paper) intact.
  draw(level.multiplier * kPatternLevelFactor);
  if (level.fade <= 0) return;
  canvas.saveLayer(
    Rect.fromLTWH(translation.dx, translation.dy, size.width, size.height),
    Paint()..color = Color.fromRGBO(0, 0, 0, level.fade),
  );
  draw(level.multiplier);
  canvas.restore();
}

void _drawPatternLines(
  PatternTexture texture,
  Canvas canvas,
  double scale,
  Offset offset,
  Size size,
  Offset translation,
  bool extraLines,
  double multiplier,
  double pixelsPerUnit,
) {
  // Coarser levels keep their lines at least half a pixel wide on screen.
  double stroke(double width) {
    final scaled = width * multiplier * scale;
    if (multiplier <= 1 || width <= 0) return scaled;
    return max(scaled, 0.5 / pixelsPerUnit * scale);
  }

  if (texture.boxWidth > 0 && texture.boxXCount > 0) {
    final boxWidth = texture.boxWidth * multiplier;
    final boxSpace = texture.boxXSpace * multiplier;
    final relativeWidth = boxWidth * scale;
    final relativeSpace = boxSpace * scale;
    final part = boxWidth * texture.boxXCount + boxSpace;
    final relativePart = relativeWidth * texture.boxXCount + relativeSpace;
    var xCount = (offset.dx / part).floor();
    if (extraLines) xCount--;
    double x = xCount * part - offset.dx;
    x *= scale;
    final xLimit = size.width + (extraLines ? relativePart : 0);
    final paint = Paint()
      ..strokeWidth = stroke(texture.boxXStroke)
      ..color = texture.boxXColor.toColor();

    int count = 0;
    var drawn = 0;
    while (x < xLimit && drawn < kMaxPatternLinesPerDirection) {
      canvas.drawLine(
        Offset(x + translation.dx, 0 + translation.dy),
        Offset(x + translation.dx, size.height + translation.dy),
        paint,
      );
      drawn++;
      count++;
      if (count >= texture.boxXCount) {
        count = 0;
        x += relativeSpace;
      }
      x += relativeWidth;
    }
  }
  if (texture.boxHeight > 0 && texture.boxYCount > 0) {
    final boxHeight = texture.boxHeight * multiplier;
    final boxSpace = texture.boxYSpace * multiplier;
    final relativeHeight = boxHeight * scale;
    final relativeSpace = boxSpace * scale;
    final part = boxHeight * texture.boxYCount + boxSpace;
    final relativePart = relativeHeight * texture.boxYCount + relativeSpace;
    var yCount = (offset.dy / part).floor();
    if (extraLines) yCount--;
    double y = yCount * part + -offset.dy;
    y *= scale;
    final yLimit = size.height + (extraLines ? relativePart : 0);
    final paint = Paint()
      ..strokeWidth = stroke(texture.boxYStroke)
      ..color = texture.boxYColor.toColor();
    int count = 0;
    var drawn = 0;
    while (y < yLimit && drawn < kMaxPatternLinesPerDirection) {
      canvas.drawLine(
        Offset(0 + translation.dx, y + translation.dy),
        Offset(size.width + translation.dx, y + translation.dy),
        paint,
      );
      drawn++;
      count++;
      if (count >= texture.boxYCount) {
        count = 0;
        y += relativeSpace;
      }
      y += relativeHeight;
    }
  }
}

void drawPatternTextureOnSvg(
  PatternTexture texture,
  XmlDocument xml,
  Offset offset,
  Size size, [
  Offset translation = .zero,
  bool extraLines = false,
]) {
  final id = createUniqueId();
  var g = xml
      .getOrCreateElement('svg')
      .createElement('g', id: 'pattern-texture-$id');

  g.createElement(
    'rect',
    attributes: {
      'x': '${translation.dx}px',
      'y': '${translation.dy}px',
      'width': '${size.width}px',
      'height': '${size.height}px',
      'fill': texture.boxColor.toHexString(alpha: false),
      'fill-opacity': '${texture.boxColor.a / 255}',
    },
  );
  if (texture.boxWidth > 0 && texture.boxXCount > 0) {
    final part = texture.boxWidth * texture.boxXCount + texture.boxXSpace;
    final xLimit = size.width + (extraLines ? part : 0);
    int xCount = (offset.dx / part).floor();
    if (extraLines) xCount--;
    double x = xCount * part - offset.dx;

    int count = 0;
    while (x < xLimit) {
      final currentX = translation.dx + x;
      g.createElement(
        'line',
        attributes: {
          'x1': '${currentX}px',
          'y1': '${translation.dy}px',
          'x2': '${currentX}px',
          'y2': '${translation.dy + size.height}px',
          'stroke': texture.boxXColor.toHexString(alpha: false),
          'stroke-opacity': '${texture.boxXColor.a / 255}',
          'stroke-width': '${texture.boxXStroke}',
        },
      );
      count++;
      if (count >= texture.boxXCount) {
        count = 0;
        x += texture.boxXSpace;
      }
      x += texture.boxWidth;
    }
  }
  if (texture.boxHeight > 0 && texture.boxYCount > 0) {
    final part = texture.boxHeight * texture.boxYCount + texture.boxYSpace;
    final yLimit = size.height + (extraLines ? part : 0);
    int yCount = (offset.dy / part).floor();
    if (extraLines) yCount--;
    double y = yCount * part - offset.dy;

    int count = 0;
    while (y < yLimit) {
      final currentY = translation.dy + y;
      g.createElement(
        'line',
        attributes: {
          'x1': '${translation.dx}px',
          'y1': '${currentY}px',
          'x2': '${translation.dx + size.width}px',
          'y2': '${currentY}px',
          'stroke': texture.boxYColor.toHexString(alpha: false),
          'stroke-opacity': '${texture.boxYColor.a / 255}',
          'stroke-width': '${texture.boxYStroke}',
        },
      );
      count++;
      if (count >= texture.boxYCount) {
        count = 0;
        y += texture.boxYSpace;
      }
      y += texture.boxHeight;
    }
  }
}
