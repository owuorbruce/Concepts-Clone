import 'dart:math' as math;

import 'package:butterfly/models/marker_palette.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const _hueFamilies = [
  'B',
  'BV',
  'V',
  'RV',
  'R',
  'YR',
  'Y',
  'YG',
  'G',
  'BG',
  'E',
];

/// A swatch in untransformed ring coordinates. At zoom 1 its short side is
/// 38 logical pixels and its code is painted at 11 logical pixels.
class MarkerSwatchGeometry {
  const MarkerSwatchGeometry(this.marker, this.center);

  final MarkerColor marker;
  final Offset center;

  Rect get bounds => Rect.fromCenter(center: center, width: 54, height: 38);
}

/// Stable geometry shared by painting and hit testing. Neutral and fluorescent
/// colors occupy concentric inner rings; hue families form radial bars.
class MarkerRingGeometry {
  MarkerRingGeometry(MarkerPalette palette, {this.innerRadius = 80})
    : swatches = _layout(palette, innerRadius),
      families = [
        ..._hueFamilies.where(palette.families.contains),
        ...palette.families.where((name) => !_hueFamilies.contains(name)),
      ];

  final List<MarkerSwatchGeometry> swatches;
  final List<String> families;
  final double innerRadius;

  static List<MarkerSwatchGeometry> _layout(
    MarkerPalette palette,
    double innerRadius,
  ) {
    final result = <MarkerSwatchGeometry>[];
    final neutral = <MarkerColor>[];
    for (
      var familyIndex = 0;
      familyIndex < _hueFamilies.length;
      familyIndex++
    ) {
      final family = _hueFamilies[familyIndex];
      final colors = palette.byFamily(family).toList()
        ..sort((a, b) => _luminance(a).compareTo(_luminance(b)));
      final angle = -math.pi / 2 + familyIndex * 2 * math.pi / 11;
      for (var index = 0; index < colors.length; index++) {
        final radius = innerRadius + 370.0 + index * 58.0;
        result.add(
          MarkerSwatchGeometry(
            colors[index],
            Offset(radius * math.cos(angle), radius * math.sin(angle)),
          ),
        );
      }
    }
    for (final family in palette.families) {
      if (!_hueFamilies.contains(family))
        neutral.addAll(palette.byFamily(family));
    }
    // Fifteen cells per ring leave more than 32 px between neighboring cells.
    for (var index = 0; index < neutral.length; index++) {
      final ring = index ~/ 15;
      final position = index % 15;
      final radius = innerRadius + 85.0 + ring * 68.0;
      final angle = -math.pi / 2 + position * 2 * math.pi / 15;
      result.add(
        MarkerSwatchGeometry(
          neutral[index],
          Offset(radius * math.cos(angle), radius * math.sin(angle)),
        ),
      );
    }
    return result;
  }

  static double _luminance(MarkerColor marker) {
    final color = marker.color;
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
  }

  MarkerSwatchGeometry? byCode(String code) {
    for (final swatch in swatches) {
      if (swatch.marker.code.toLowerCase() == code.toLowerCase()) return swatch;
    }
    return null;
  }

  MarkerColor? hitTest(Offset worldPosition) {
    for (final swatch in swatches.reversed) {
      if (swatch.bounds.contains(worldPosition)) return swatch.marker;
    }
    return null;
  }

  /// Converts a viewport point through the same pan/zoom transform as paint.
  MarkerColor? hitTestTransformed(
    Offset point, {
    required Size viewport,
    required Offset pan,
    required double zoom,
  }) {
    final world = (point - viewport.center(Offset.zero) - pan) / zoom;
    return hitTest(world);
  }

  Offset transformedCenter(
    String code, {
    required Size viewport,
    required Offset pan,
    required double zoom,
  }) {
    final center = byCode(code)!.center;
    return viewport.center(Offset.zero) + pan + center * zoom;
  }
}

class MarkerRing extends StatefulWidget {
  const MarkerRing({
    super.key,
    required this.palette,
    required this.innerRadius,
    required this.color,
    required this.onPreview,
  });

  final MarkerPalette palette;
  final double innerRadius;
  final int color;
  final ValueChanged<MarkerColor> onPreview;

  @override
  State<MarkerRing> createState() => _MarkerRingState();
}

class _MarkerRingState extends State<MarkerRing> {
  late MarkerRingGeometry _geometry = MarkerRingGeometry(
    widget.palette,
    innerRadius: widget.innerRadius,
  );
  final _search = TextEditingController();
  Size _viewport = Size.zero;
  Offset _pan = Offset.zero;
  double _zoom = 0.55;
  Offset _gestureStartPan = Offset.zero;
  double _gestureStartZoom = 1;
  Offset _gestureStartFocal = Offset.zero;
  String _query = '';

  @override
  void didUpdateWidget(covariant MarkerRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.palette, widget.palette) ||
        oldWidget.innerRadius != widget.innerRadius) {
      _geometry = MarkerRingGeometry(
        widget.palette,
        innerRadius: widget.innerRadius,
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _focus(MarkerSwatchGeometry swatch) {
    setState(() {
      _zoom = 1;
      _pan = -swatch.center;
    });
  }

  void _focusFamily(String family) {
    final members = _geometry.swatches.where((s) => s.marker.family == family);
    if (members.isNotEmpty) _focus(members.first);
  }

  void _searchFirst() {
    final match = widget.palette.search(_query).firstOrNull;
    if (match == null) return;
    final swatch = _geometry.byCode(match.code);
    if (swatch != null) _focus(swatch);
    widget.onPreview(match);
  }

  void _setZoom(double zoom, Offset focal) {
    final next = zoom.clamp(0.25, 4.0);
    final center = _viewport.center(Offset.zero);
    setState(() {
      _pan = focal - center - (focal - center - _pan) * (next / _zoom);
      _zoom = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Column(
      children: [
        SizedBox(
          height: 45,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final family in _geometry.families)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ActionChip(
                    key: ValueKey('amaze-color-family-$family'),
                    label: Text(family),
                    onPressed: () => _focusFamily(family),
                  ),
                ),
            ],
          ),
        ),
        TextField(
          key: const ValueKey('amaze-color-search'),
          controller: _search,
          decoration: InputDecoration(
            labelText: loc.search,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (value) => setState(() => _query = value),
          onSubmitted: (_) => _searchFirst(),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewport = constraints.biggest;
              return Listener(
                onPointerSignal: (signal) {
                  if (signal is PointerScrollEvent &&
                      HardwareKeyboard.instance.isControlPressed) {
                    _setZoom(
                      _zoom * math.exp(-signal.scrollDelta.dy / 450),
                      signal.localPosition,
                    );
                  }
                },
                child: GestureDetector(
                  key: const ValueKey('amaze-color-ring'),
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => setState(() {
                    _zoom = 0.55;
                    _pan = Offset.zero;
                  }),
                  onTapUp: (details) {
                    final marker = _geometry.hitTestTransformed(
                      details.localPosition,
                      viewport: _viewport,
                      pan: _pan,
                      zoom: _zoom,
                    );
                    if (marker != null) widget.onPreview(marker);
                  },
                  onScaleStart: (details) {
                    _gestureStartPan = _pan;
                    _gestureStartZoom = _zoom;
                    _gestureStartFocal = details.localFocalPoint;
                  },
                  onScaleUpdate: (details) {
                    final next = (_gestureStartZoom * details.scale).clamp(
                      0.25,
                      4.0,
                    );
                    final center = _viewport.center(Offset.zero);
                    final world =
                        (_gestureStartFocal - center - _gestureStartPan) /
                        _gestureStartZoom;
                    setState(() {
                      _zoom = next;
                      _pan = details.localFocalPoint - center - world * next;
                    });
                  },
                  child: CustomPaint(
                    painter: _MarkerRingPainter(
                      geometry: _geometry,
                      pan: _pan,
                      zoom: _zoom,
                      selectedRgb: widget.color & 0xFFFFFF,
                      matches: widget.palette
                          .search(_query)
                          .map((m) => m.code)
                          .toSet(),
                      dimUnmatched: _query.trim().isNotEmpty,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MarkerRingPainter extends CustomPainter {
  const _MarkerRingPainter({
    required this.geometry,
    required this.pan,
    required this.zoom,
    required this.selectedRgb,
    required this.matches,
    required this.dimUnmatched,
  });

  final MarkerRingGeometry geometry;
  final Offset pan;
  final double zoom;
  final int selectedRgb;
  final Set<String> matches;
  final bool dimUnmatched;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2 + pan.dx, size.height / 2 + pan.dy);
    canvas.scale(zoom);
    final visible = Rect.fromCenter(
      center: -pan / zoom,
      width: size.width / zoom + 120,
      height: size.height / zoom + 120,
    );
    for (final swatch in geometry.swatches) {
      if (!visible.overlaps(swatch.bounds)) continue;
      final marker = swatch.marker;
      final matched = matches.contains(marker.code);
      final color = Color(marker.color.value);
      final isSelected = marker.color.value & 0xFFFFFF == selectedRgb;
      final rect = RRect.fromRectAndRadius(
        swatch.bounds.deflate(1),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = dimUnmatched && !matched
              ? color.withValues(alpha: 0.2)
              : color,
      );
      if (isSelected || (dimUnmatched && matched)) {
        canvas.drawRRect(
          rect,
          Paint()
            ..color = isSelected ? Colors.white : Colors.yellow
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      if (zoom >= 0.8) {
        final darkText =
            (marker.color.r * 299 +
                marker.color.g * 587 +
                marker.color.b * 114) >
            145000;
        final painter = TextPainter(
          text: TextSpan(
            text: marker.code,
            style: TextStyle(
              color: darkText ? Colors.black : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: 50);
        painter.paint(
          canvas,
          swatch.center - Offset(painter.width / 2, painter.height / 2),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarkerRingPainter oldDelegate) =>
      oldDelegate.pan != pan ||
      oldDelegate.zoom != zoom ||
      oldDelegate.selectedRgb != selectedRgb ||
      oldDelegate.dimUnmatched != dimUnmatched ||
      oldDelegate.matches.difference(matches).isNotEmpty ||
      matches.difference(oldDelegate.matches).isNotEmpty ||
      oldDelegate.geometry != geometry;
}
