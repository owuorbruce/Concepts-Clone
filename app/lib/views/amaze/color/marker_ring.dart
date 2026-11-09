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

/// Font size of the marker codes painted on the swatches, at zoom 1.
const kMarkerLabelSize = 11.0;

/// Zoom at which swatches are focused and their codes are painted.
const kMarkerFocusZoom = 1.0;

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

  /// Distance between ring and bar steps. A 54x38 swatch spans at most
  /// sqrt(54² + 38²) ≈ 66 px in any direction, so neighbors never overlap.
  static const _step = 68.0;

  /// Neutral and fluorescent cells per inner ring.
  static const _perRing = 15;

  static List<MarkerSwatchGeometry> _layout(
    MarkerPalette palette,
    double innerRadius,
  ) {
    final result = <MarkerSwatchGeometry>[];
    final neutral = <MarkerColor>[];
    for (final family in palette.families) {
      if (!_hueFamilies.contains(family)) {
        neutral.addAll(palette.byFamily(family));
      }
    }
    // Gray and fluorescent families fill concentric rings just outside the
    // wheel. Fifteen cells on the first ring are about 69 px apart.
    final firstRing = innerRadius + 85.0;
    for (var index = 0; index < neutral.length; index++) {
      final ring = index ~/ _perRing;
      final position = index % _perRing;
      final radius = firstRing + ring * _step;
      final angle = -math.pi / 2 + position * 2 * math.pi / _perRing;
      result.add(
        MarkerSwatchGeometry(
          neutral[index],
          Offset(radius * math.cos(angle), radius * math.sin(angle)),
        ),
      );
    }
    // Hue bars start beyond the last neutral ring and run outward from the
    // darkest to the lightest color.
    final rings = (neutral.length / _perRing).ceil();
    final barStart = firstRing + rings * _step + _step;
    for (
      var familyIndex = 0;
      familyIndex < _hueFamilies.length;
      familyIndex++
    ) {
      final family = _hueFamilies[familyIndex];
      final colors = palette.byFamily(family).toList()
        ..sort((a, b) => _luminance(a).compareTo(_luminance(b)));
      final angle =
          -math.pi / 2 + familyIndex * 2 * math.pi / _hueFamilies.length;
      for (var index = 0; index < colors.length; index++) {
        final radius = barStart + index * _step;
        result.add(
          MarkerSwatchGeometry(
            colors[index],
            Offset(radius * math.cos(angle), radius * math.sin(angle)),
          ),
        );
      }
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
  double _zoom = _overviewZoom;
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

  /// Zoom of the overview the ring opens with and double tap returns to.
  static const _overviewZoom = 0.55;

  Duration? _lastTapTime;
  Offset? _lastTapPosition;

  /// Whether a tap at [position] completes a double tap: within 300 ms and
  /// 40 px of the previous tap.
  bool _isDoubleTap(Offset position) {
    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    final lastTime = _lastTapTime;
    final lastPosition = _lastTapPosition;
    final isDouble =
        lastTime != null &&
        lastPosition != null &&
        now - lastTime <= kDoubleTapTimeout &&
        (position - lastPosition).distance <= 40;
    _lastTapTime = isDouble ? null : now;
    _lastTapPosition = isDouble ? null : position;
    return isDouble;
  }

  void _focus(MarkerSwatchGeometry swatch) {
    setState(() {
      _zoom = kMarkerFocusZoom;
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
                  // Pans from where the pointer went down, not from where the
                  // gesture was recognized.
                  dragStartBehavior: DragStartBehavior.down,
                  behavior: HitTestBehavior.opaque,
                  // A double tap is detected here rather than with
                  // onDoubleTap, which would delay every single tap.
                  onTapUp: (details) {
                    if (_isDoubleTap(details.localPosition)) {
                      setState(() {
                        _zoom = _overviewZoom;
                        _pan = Offset.zero;
                      });
                      return;
                    }
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
                    painter: MarkerRingPainter(
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

/// Paints the swatches through the ring's pan and zoom. Its fields describe
/// what is shown: search [matches] are highlighted when [dimUnmatched], and
/// the swatch with [selectedRgb] is outlined.
class MarkerRingPainter extends CustomPainter {
  const MarkerRingPainter({
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
              fontSize: kMarkerLabelSize,
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
  bool shouldRepaint(covariant MarkerRingPainter oldDelegate) =>
      oldDelegate.pan != pan ||
      oldDelegate.zoom != zoom ||
      oldDelegate.selectedRgb != selectedRgb ||
      oldDelegate.dimUnmatched != dimUnmatched ||
      oldDelegate.matches.difference(matches).isNotEmpty ||
      matches.difference(oldDelegate.matches).isNotEmpty ||
      oldDelegate.geometry != geometry;
}
