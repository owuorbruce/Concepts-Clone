import 'dart:math' as math;

import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';

import 'color_model.dart';

/// A color channel shown by [ChannelRings], in display units.
enum ColorChannel {
  hue(360),
  saturation(100),
  lightness(100),
  red(255),
  green(255),
  blue(255),
  alpha(100);

  const ColorChannel(this.max);

  /// Largest display value; the smallest is 0.
  final double max;

  String label(AppLocalizations loc) => switch (this) {
    hue => 'H',
    saturation => 'S',
    lightness => 'L',
    red => 'R',
    green => 'G',
    blue => 'B',
    alpha => loc.alpha,
  };
}

/// The channels of [mode], from the outer arc inwards.
List<ColorChannel> channelsOf(AmazeColorMode mode) => switch (mode) {
  AmazeColorMode.rgb => const [
    ColorChannel.red,
    ColorChannel.green,
    ColorChannel.blue,
    ColorChannel.alpha,
  ],
  _ => const [
    ColorChannel.hue,
    ColorChannel.saturation,
    ColorChannel.lightness,
    ColorChannel.alpha,
  ],
};

/// Geometry of the channel arcs, shared by painting, pointer handling and
/// tests. Angles are in radians in screen coordinates (0 is right, angles
/// grow clockwise).
class ChannelRingLayout {
  ChannelRingLayout(this.channels, this.size);

  final List<ColorChannel> channels;
  final Size size;

  static const band = 18.0;
  static const _gap = 10.0;

  /// Arcs other than hue leave a 60° opening at the bottom.
  static const _start = 120 * math.pi / 180;
  static const _sweep = 300 * math.pi / 180;

  /// Side of the square whose innermost arc leaves a circle of
  /// [clearRadius] free.
  static double sideFor(double clearRadius, {int channels = 4}) {
    return 2 *
        (clearRadius +
            band / 2 +
            _gap / 2 +
            (channels - 1) * (band + _gap) +
            band / 2 +
            4);
  }

  /// Inner edge of the innermost arc (alpha) around [clearRadius].
  static double innerEdgeFor(double clearRadius) => clearRadius + _gap / 2;

  Offset get center => size.center(Offset.zero);

  double get outerRadius => math.max(0, size.shortestSide / 2 - band / 2 - 4);

  /// Radius of the middle of [channel]'s arc.
  double radiusOf(ColorChannel channel) {
    return outerRadius - channels.indexOf(channel) * (band + _gap);
  }

  (double, double) _span(ColorChannel channel) {
    if (channel == ColorChannel.hue) return (-math.pi / 2, 2 * math.pi);
    return (_start, _sweep);
  }

  double angleOf(ColorChannel channel, double value) {
    final (start, sweep) = _span(channel);
    return start + sweep * (value / channel.max).clamp(0.0, 1.0);
  }

  /// Position of [channel]'s handle for [value].
  Offset handleOf(ColorChannel channel, double value) {
    final angle = angleOf(channel, value);
    return center +
        Offset(math.cos(angle), math.sin(angle)) * radiusOf(channel);
  }

  /// The channel whose arc is under [position], or null.
  ColorChannel? channelAt(Offset position) {
    final distance = (position - center).distance;
    for (final channel in channels) {
      if ((distance - radiusOf(channel)).abs() <= band / 2 + _gap / 2) {
        return channel;
      }
    }
    return null;
  }

  /// The value of [channel] at the angle of [position].
  double valueAt(ColorChannel channel, Offset position) {
    final (start, sweep) = _span(channel);
    final delta = position - center;
    var relative = (math.atan2(delta.dy, delta.dx) - start) % (2 * math.pi);
    if (relative > sweep) {
      // In the opening: snap to the nearer end.
      relative = relative - sweep < (2 * math.pi - relative) ? sweep : 0;
    }
    return relative / sweep * channel.max;
  }
}

/// HSL or RGB arcs around [center] with draggable handles, an alpha arc and
/// a numeric field per channel. It fills its parent and only its arcs and
/// fields take pointers.
///
/// A drag shows its color through [onPreview] and applies it once through
/// [onCommit] when it is released; a cancelled drag previews the color it
/// started with. A field applies through [onCommit] on Enter.
class ChannelRings extends StatefulWidget {
  const ChannelRings({
    super.key,
    required this.mode,
    required this.color,
    required this.center,
    required this.clearRadius,
    required this.onPreview,
    required this.onCommit,
  });

  final AmazeColorMode mode;
  final SRGBColor color;

  /// Center of the arcs in the parent.
  final Offset center;

  /// Radius around [center] the arcs stay out of.
  final double clearRadius;
  final ValueChanged<SRGBColor> onPreview;
  final ValueChanged<SRGBColor> onCommit;

  @override
  State<ChannelRings> createState() => _ChannelRingsState();
}

class _ChannelRingsState extends State<ChannelRings> {
  /// HSL kept at full precision, so gray colors keep their hue and
  /// switching modes does not move the color.
  late HslChannels _hsl = rgbToHsl(widget.color);

  /// The color [_hsl] was last synchronized with.
  late SRGBColor _hslColor = widget.color;

  /// The latest color sent to the parent.
  late SRGBColor _latest = widget.color;

  int? _pointer;
  ColorChannel? _dragging;
  SRGBColor? _dragStart;
  HslChannels? _dragStartHsl;

  @override
  void didUpdateWidget(ChannelRings oldWidget) {
    super.didUpdateWidget(oldWidget);
    _latest = widget.color;
  }

  HslChannels get _currentHsl {
    if (widget.color != _hslColor) {
      _hsl = rgbToHsl(widget.color);
      _hslColor = widget.color;
    }
    return _hsl;
  }

  /// [channel] of the current color, in display units.
  double valueOf(ColorChannel channel) {
    final color = widget.color;
    final hsl = _currentHsl;
    return switch (channel) {
      ColorChannel.hue => hsl.hue,
      ColorChannel.saturation => hsl.saturation,
      ColorChannel.lightness => hsl.lightness,
      ColorChannel.red => color.r.toDouble(),
      ColorChannel.green => color.g.toDouble(),
      ColorChannel.blue => color.b.toDouble(),
      ColorChannel.alpha => color.a / 255 * 100,
    };
  }

  void _set(ColorChannel channel, double value) {
    final v = value.clamp(0.0, channel.max);
    final color = widget.color;
    final hsl = _currentHsl;
    final SRGBColor next;
    switch (channel) {
      case ColorChannel.hue ||
          ColorChannel.saturation ||
          ColorChannel.lightness:
        _hsl = HslChannels(
          channel == ColorChannel.hue ? v : hsl.hue,
          channel == ColorChannel.saturation ? v : hsl.saturation,
          channel == ColorChannel.lightness ? v : hsl.lightness,
          color.a / 255 * 100,
        );
        next = hslToRgb(_hsl);
      case ColorChannel.red:
        next = color.withValues(r: v.round());
      case ColorChannel.green:
        next = color.withValues(g: v.round());
      case ColorChannel.blue:
        next = color.withValues(b: v.round());
      case ColorChannel.alpha:
        next = color.withValues(a: (v * 255 / 100).round());
        _hsl = HslChannels(hsl.hue, hsl.saturation, hsl.lightness, v);
    }
    if (channel != ColorChannel.alpha &&
        channel != ColorChannel.hue &&
        channel != ColorChannel.saturation &&
        channel != ColorChannel.lightness) {
      _hsl = rgbToHsl(next);
    }
    _hslColor = next;
    _latest = next;
    setState(() {});
    if (next != color) widget.onPreview(next);
  }

  void _onDown(ChannelRingLayout layout, PointerDownEvent event) {
    if (_pointer != null) return;
    final channel = layout.channelAt(event.localPosition);
    if (channel == null) return;
    _pointer = event.pointer;
    _dragging = channel;
    _dragStart = widget.color;
    _dragStartHsl = _currentHsl;
    _set(channel, layout.valueAt(channel, event.localPosition));
  }

  void _onMove(ChannelRingLayout layout, PointerMoveEvent event) {
    final channel = _dragging;
    if (event.pointer != _pointer || channel == null) return;
    _set(channel, layout.valueAt(channel, event.localPosition));
  }

  void _onEnd(PointerEvent event, {required bool cancelled}) {
    if (event.pointer != _pointer) return;
    final start = _dragStart!;
    final startHsl = _dragStartHsl!;
    _pointer = null;
    _dragging = null;
    _dragStart = null;
    _dragStartHsl = null;
    if (cancelled) {
      setState(() {
        _hsl = startHsl;
        _hslColor = start;
        _latest = start;
      });
      widget.onPreview(start);
    } else if (_latest != start) {
      widget.onCommit(_latest);
    }
  }

  void _applyField(ColorChannel channel, int value) {
    final before = _latest;
    _set(channel, value.toDouble());
    if (_latest != before) widget.onCommit(_latest);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final channels = channelsOf(widget.mode);
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        final side = ChannelRingLayout.sideFor(
          widget.clearRadius,
          channels: channels.length,
        );
        final layout = ChannelRingLayout(channels, Size.square(side));
        final arcs = Rect.fromCenter(
          center: widget.center,
          width: side,
          height: side,
        );
        final fields = _fieldsRect(screen, arcs);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: arcs,
              child: _ArcHitBox(
                layout: layout,
                child: Listener(
                  key: const ValueKey('amaze-color-channels'),
                  onPointerDown: (event) => _onDown(layout, event),
                  onPointerMove: (event) => _onMove(layout, event),
                  onPointerUp: (event) => _onEnd(event, cancelled: false),
                  onPointerCancel: (event) => _onEnd(event, cancelled: true),
                  child: CustomPaint(
                    painter: ChannelRingsPainter(
                      layout: layout,
                      color: widget.color,
                      hsl: _currentHsl,
                      values: {
                        for (final channel in channels)
                          channel: valueOf(channel),
                      },
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            Positioned(
              left: fields.left,
              top: fields.top,
              width: fields.width,
              child: Material(
                key: const ValueKey('amaze-color-fields'),
                elevation: 2,
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final channel in channels)
                        SizedBox(
                          width: _fieldWidth,
                          child: _ChannelField(
                            key: ValueKey(('amaze-color-field', channel.name)),
                            label: channel.label(loc),
                            value: valueOf(channel).round(),
                            max: channel.max.round(),
                            onApply: (value) => _applyField(channel, value),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static const _fieldWidth = 92.0;

  /// Where the block of fields goes: beside, below or above the arcs,
  /// wherever it is fully on [screen]; otherwise below, moved on screen.
  Rect _fieldsRect(Size screen, Rect arcs) {
    const margin = 8.0;
    const size = Size(2 * _fieldWidth + 24, 136);
    final bounds = (Offset.zero & screen).deflate(margin);
    final center = arcs.center;
    final candidates = [
      Offset(arcs.right + margin, center.dy - size.height / 2),
      Offset(arcs.left - margin - size.width, center.dy - size.height / 2),
      Offset(center.dx - size.width / 2, arcs.bottom + margin),
      Offset(center.dx - size.width / 2, arcs.top - margin - size.height),
    ];
    for (final origin in candidates) {
      final rect = origin & size;
      if (bounds.contains(rect.topLeft) && bounds.contains(rect.bottomRight)) {
        return rect;
      }
    }
    final origin = candidates[2];
    return Offset(
          origin.dx.clamp(
            bounds.left,
            math.max(bounds.left, bounds.right - size.width),
          ),
          origin.dy.clamp(
            bounds.top,
            math.max(bounds.top, bounds.bottom - size.height),
          ),
        ) &
        size;
  }
}

/// Lets pointers through everywhere except on the arcs of [layout].
class _ArcHitBox extends SingleChildRenderObjectWidget {
  const _ArcHitBox({required this.layout, super.child});

  final ChannelRingLayout layout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderArcHitBox(layout);

  @override
  void updateRenderObject(BuildContext context, _RenderArcHitBox renderObject) {
    renderObject.arcs = layout;
  }
}

class _RenderArcHitBox extends RenderProxyBox {
  _RenderArcHitBox(this.arcs);

  ChannelRingLayout arcs;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (arcs.channelAt(position) == null) return false;
    return super.hitTest(result, position: position);
  }
}

/// Paints the arcs of a [ChannelRingLayout] with their handles.
class ChannelRingsPainter extends CustomPainter {
  const ChannelRingsPainter({
    required this.layout,
    required this.color,
    required this.hsl,
    required this.values,
  });

  final ChannelRingLayout layout;
  final SRGBColor color;
  final HslChannels hsl;

  /// The value of each channel, in display units.
  final Map<ColorChannel, double> values;

  Color _at(ColorChannel channel, double fraction) {
    final c = color;
    final v = fraction * channel.max;
    final srgb = switch (channel) {
      ColorChannel.hue => hslToRgb(HslChannels(v, 100, 50, 100)),
      ColorChannel.saturation => hslToRgb(
        HslChannels(hsl.hue, v, hsl.lightness, 100),
      ),
      ColorChannel.lightness => hslToRgb(
        HslChannels(hsl.hue, hsl.saturation, v, 100),
      ),
      ColorChannel.red => c.withValues(r: v.round(), a: 255),
      ColorChannel.green => c.withValues(g: v.round(), a: 255),
      ColorChannel.blue => c.withValues(b: v.round(), a: 255),
      ColorChannel.alpha => c.withValues(a: (fraction * 255).round()),
    };
    return Color(srgb.value);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = layout.center;
    for (final channel in layout.channels) {
      final radius = layout.radiusOf(channel);
      if (radius <= ChannelRingLayout.band) continue;
      final start = layout.angleOf(channel, 0);
      final end = layout.angleOf(channel, channel.max);
      const steps = 12;
      final colors = [for (var i = 0; i <= steps; i++) _at(channel, i / steps)];
      final rect = Rect.fromCircle(center: center, radius: radius);
      // A light backing keeps the arcs readable on any canvas.
      canvas.drawArc(
        rect,
        start,
        end - start,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ChannelRingLayout.band + 3
          ..strokeCap = channel == ColorChannel.hue
              ? StrokeCap.butt
              : StrokeCap.round
          ..color = const Color(0xE6FFFFFF),
      );
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ChannelRingLayout.band
        ..strokeCap = channel == ColorChannel.hue
            ? StrokeCap.butt
            : StrokeCap.round
        ..shader = SweepGradient(
          colors: colors,
          startAngle: 0,
          endAngle: end - start,
          transform: GradientRotation(start),
        ).createShader(rect);
      canvas.drawArc(rect, start, end - start, false, paint);
      final handle = layout.handleOf(channel, values[channel] ?? 0);
      canvas.drawCircle(
        handle,
        ChannelRingLayout.band / 2 + 3,
        Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.drawCircle(
        handle,
        ChannelRingLayout.band / 2 + 3,
        Paint()
          ..color = const Color(0xFF000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(ChannelRingsPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.layout.size != layout.size ||
      oldDelegate.layout.channels != layout.channels ||
      oldDelegate.hsl.hue != hsl.hue ||
      oldDelegate.hsl.saturation != hsl.saturation ||
      oldDelegate.hsl.lightness != hsl.lightness;
}

/// A whole-number field for one channel. It applies on Enter or when focus
/// leaves, shows an error for input outside 0 to [max], and reverts on
/// Escape.
class _ChannelField extends StatefulWidget {
  const _ChannelField({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.onApply,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onApply;

  @override
  State<_ChannelField> createState() => _ChannelFieldState();
}

class _ChannelFieldState extends State<_ChannelField> {
  late final _controller = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit();
    });
  }

  @override
  void didUpdateWidget(_ChannelField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _revert() {
    _controller.text = '${widget.value}';
    setState(() => _error = null);
  }

  void _submit() {
    if (!mounted) return;
    final text = _controller.text.trim();
    if (text == '${widget.value}') {
      if (_error != null) setState(() => _error = null);
      return;
    }
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null || parsed < 0 || parsed > widget.max) {
      setState(() {
        _error = AppLocalizations.of(context)
            .amazeValueRangeError('0', '${widget.max}');
      });
      return;
    }
    setState(() => _error = null);
    final value = parsed.round();
    if (value != widget.value) widget.onApply(value);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _revert},
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: const OutlineInputBorder(),
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
    );
  }
}
