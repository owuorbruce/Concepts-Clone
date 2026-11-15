import 'dart:math' as math;

import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/models/marker_palette.dart';
import 'package:butterfly/services/marker_palette_loader.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'channel_rings.dart';
import 'color_model.dart';
import 'marker_ring.dart';
import 'palette_strip.dart';

/// A pointer that moves further than this from where it went down spins
/// the wheel instead of tapping.
const kAmazeColorTapSlop = 8.0;

/// Opens the color wheel around the tool wheel and completes when it
/// closes.
///
/// The wheel is drawn around [center], or the middle of the screen if it is
/// null, outside a circle of [innerRadius]. [anchor], if given, is asked for
/// the tool wheel's rectangle again whenever the window changes size.
///
/// [onPick] is called every time a color is applied; the picker stays open.
/// When it closes, [onClosed] gets the last applied color, or null if none
/// was applied. [onEyedropper] is called after closing through the
/// eyedropper button.
///
/// Recent colors default to the settings' recent colors, which are only
/// read, and saved palettes to the packs of the [ButterflyFileSystem].
Future<void> showAmazeColorWheel(
  BuildContext context, {
  required Offset? center,
  required double innerRadius,
  required SRGBColor initial,
  required ValueChanged<SRGBColor> onPick,
  required VoidCallback onEyedropper,
  required ValueChanged<SRGBColor?> onClosed,
  Rect? Function()? anchor,
  Future<MarkerPalette?> Function()? paletteLoader,
  List<SRGBColor>? recentColors,
  AmazePaletteSource? paletteSource,
}) async {
  final settings = context.read<SettingsCubit?>();
  final fileSystem = context.read<ButterflyFileSystem?>();
  final source =
      paletteSource ??
      (fileSystem == null ? null : PackPaletteSource(fileSystem));
  final palette = await (paletteLoader ?? loadMarkerPalette)();
  final preferences = await SharedPreferences.getInstance();
  final mode = await loadAmazeColorMode(
    palette: palette,
    preferences: preferences,
  );
  final angle = await loadAmazeColorAngle(preferences: preferences);
  if (!context.mounted) return;
  SRGBColor? last;
  final eyedropper = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => _AmazeColorOverlay(
      center: center,
      innerRadius: innerRadius,
      anchor: anchor,
      initial: initial,
      palette: palette,
      initialMode: mode,
      initialAngle: angle,
      preferences: preferences,
      recentColors: () =>
          recentColors ?? settings?.state.recentColors ?? const <SRGBColor>[],
      paletteSource: source,
      onPick: (color) {
        last = color;
        onPick(color);
      },
    ),
  );
  onClosed(last);
  if (eyedropper ?? false) onEyedropper();
}

class _AmazeColorOverlay extends StatefulWidget {
  const _AmazeColorOverlay({
    required this.center,
    required this.innerRadius,
    required this.anchor,
    required this.initial,
    required this.palette,
    required this.initialMode,
    required this.initialAngle,
    required this.preferences,
    required this.recentColors,
    required this.paletteSource,
    required this.onPick,
  });

  final Offset? center;
  final double innerRadius;
  final Rect? Function()? anchor;
  final SRGBColor initial;
  final MarkerPalette? palette;
  final AmazeColorMode initialMode;
  final double initialAngle;
  final SharedPreferences preferences;
  final List<SRGBColor> Function() recentColors;
  final AmazePaletteSource? paletteSource;
  final ValueChanged<SRGBColor> onPick;

  @override
  State<_AmazeColorOverlay> createState() => _AmazeColorOverlayState();
}

class _AmazeColorOverlayState extends State<_AmazeColorOverlay>
    with SingleTickerProviderStateMixin {
  /// The color shown: the applied color, or a channel drag's preview.
  late SRGBColor _color = widget.initial;

  /// The color the tool has.
  late SRGBColor _applied = widget.initial;
  late List<MarkerColor> _matches = markersFor(_color, widget.palette);
  late AmazeColorMode _mode = widget.initialMode;
  MarkerColor? _pickedMarker;

  late double _rotation = widget.initialAngle;
  late final AnimationController _spin = AnimationController.unbounded(
    vsync: this,
  )..addListener(_onSpin);

  Size _screen = Size.zero;
  Offset _center = Offset.zero;
  late double _innerRadius = widget.innerRadius;
  Offset? _anchored;
  MarkerRingGeometry? _geometry;
  bool _closing = false;

  // The pointer spinning or tapping the wheel.
  int? _pointer;
  Offset _down = Offset.zero;
  double _downRotation = 0;
  double _lastAngle = 0;
  double _dragAngle = 0;
  bool _moved = false;
  VelocityTracker? _velocity;

  bool get _showsWheel => _mode == AmazeColorMode.copic && _geometry != null;

  /// Whether there is no tool wheel in the middle, as in bar mode.
  bool get _ownCenter => widget.center == null && widget.anchor == null;

  @override
  void dispose() {
    _spin.dispose();
    _geometry?.dispose();
    super.dispose();
  }

  void _onSpin() => setState(() => _rotation = _spin.value);

  void _saveAngle() {
    saveAmazeColorAngle(_rotation, preferences: widget.preferences);
  }

  void _setColor(SRGBColor color, MarkerColor? marker) {
    _color = color;
    _matches = markersFor(color, widget.palette);
    _pickedMarker = marker;
  }

  /// Shows [color] without changing the tool.
  void _preview(SRGBColor color) => setState(() => _setColor(color, null));

  /// Changes the tool to [color]. Applying the color it already has only
  /// updates the label.
  void _apply(SRGBColor color, {MarkerColor? marker}) {
    setState(() => _setColor(color, marker));
    if (color == _applied) return;
    _applied = color;
    widget.onPick(color);
  }

  void _applyMarker(MarkerColor marker) {
    _apply(marker.color.withValues(a: _color.a), marker: marker);
  }

  void _setMode(AmazeColorMode mode) {
    _spin.stop();
    setState(() {
      _mode = mode;
      _setColor(_applied, _pickedMarker);
    });
    saveAmazeColorMode(mode, preferences: widget.preferences);
  }

  void _close({bool eyedropper = false}) {
    if (_closing) return;
    _closing = true;
    _spin.stop();
    _saveAngle();
    Navigator.of(context).pop(eyedropper);
  }

  /// Recomputes the layout if the screen or the tool wheel changed.
  void _relayout(Size screen) {
    final resized = screen != _screen;
    final center = _anchored ?? widget.center ?? screen.center(Offset.zero);
    if (resized && widget.anchor != null) {
      // The tool wheel moves with the window; follow it after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final rect = widget.anchor!();
        if (rect == null) return;
        if (rect.center == _center && rect.width / 2 == _innerRadius) return;
        setState(() {
          _anchored = rect.center;
          _innerRadius = rect.width / 2;
          _screen = Size.zero;
        });
      });
    }
    if (!resized && center == _center) return;
    _screen = screen;
    _center = center;
    final palette = widget.palette;
    if (palette == null || screen.isEmpty) return;
    _geometry?.dispose();
    _geometry = MarkerRingGeometry.fit(
      palette,
      innerRadius: _innerRadius,
      center: center,
      screen: screen,
    );
  }

  /// [position] relative to the wheel's center.
  Offset _local(Offset position) => position - _center;

  /// Radius of the arc the controls run along without a wheel. Around a
  /// small tool wheel it is kept at that of a 160 px one, so that the row
  /// does not curl round onto the eyedropper.
  double get _plainArcRadius => math.max(_innerRadius, 160) + 32;

  /// Radius around the tool wheel that the controls need without a wheel.
  double get _plainControlsRadius => _plainArcRadius + 32;

  void _onPointerDown(PointerDownEvent event) {
    if (_pointer != null || _closing) return;
    final position = event.localPosition;
    final distance = (position - _center).distance;
    final geometry = _geometry;
    if (!_showsWheel || geometry == null) {
      // The gap holding the controls is neutral; everything else closes.
      if (distance < _innerRadius || distance > _plainControlsRadius) {
        _close();
      }
      return;
    }
    if (distance < _innerRadius ||
        !geometry.containsWheel(_local(position), rotation: _rotation)) {
      _close();
      return;
    }
    _spin.stop();
    _pointer = event.pointer;
    _down = position;
    _downRotation = _rotation;
    _lastAngle = (position - _center).direction;
    _dragAngle = 0;
    _moved = false;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, position);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final position = event.localPosition;
    _velocity?.addPosition(event.timeStamp, position);
    final angle = (position - _center).direction;
    _dragAngle += wrapAngle(angle - _lastAngle);
    _lastAngle = angle;
    if (!_moved && (position - _down).distance > kAmazeColorTapSlop) {
      _moved = true;
    }
    if (_moved) setState(() => _rotation = _downRotation + _dragAngle);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final geometry = _geometry;
    if (!_moved) {
      final swatch = geometry?.hitTest(_local(_down), rotation: _rotation);
      if (swatch != null) _applyMarker(swatch.marker);
      return;
    }
    final arm = event.localPosition - _center;
    final velocity = _velocity?.getVelocity().pixelsPerSecond ?? Offset.zero;
    var speed = arm.distanceSquared < 1
        ? 0.0
        : (arm.dx * velocity.dy - arm.dy * velocity.dx) / arm.distanceSquared;
    speed = speed.clamp(-12.0, 12.0);
    if (speed.abs() < 0.3) {
      _saveAngle();
      return;
    }
    _spin.value = _rotation;
    _spin
        .animateWith(
          FrictionSimulation(
            0.08,
            _rotation,
            speed,
            tolerance: const Tolerance(velocity: 0.02, distance: 0.001),
          ),
        )
        .whenCompleteOrCancel(_saveAngle);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_moved) _saveAngle();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    final geometry = _geometry;
    if (event is! PointerScrollEvent || !_showsWheel || geometry == null) {
      return;
    }
    if (!geometry.containsWheel(
      _local(event.localPosition),
      rotation: _rotation,
    )) {
      return;
    }
    _spin.stop();
    setState(() => _rotation += event.scrollDelta.dy / 500);
    _saveAngle();
  }

  /// The direction, seen from the wheel, with the most room on screen.
  double get _focusDirection {
    final toMiddle = _screen.center(Offset.zero) - _center;
    return toMiddle.distance < 1 ? -math.pi / 2 : toMiddle.direction;
  }

  void _spinTo(double rotation) {
    _spin.value = _rotation;
    _spin
        .animateTo(
          _rotation + wrapAngle(rotation - _rotation),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .whenCompleteOrCancel(_saveAngle);
  }

  /// Brings the family after ([step] 1) or before (-1) the one at the focus
  /// direction there.
  void _spinFamily(int step) {
    final geometry = _geometry;
    if (!_showsWheel || geometry == null || geometry.families.isEmpty) return;
    final focus = _focusDirection;
    final local = focus - _rotation;
    double middle(String family) {
      final (start, sweep) = geometry.familySpans[family]!;
      return start + sweep / 2;
    }

    var current = 0;
    var nearest = double.infinity;
    for (final (index, family) in geometry.families.indexed) {
      final distance = wrapAngle(middle(family) - local).abs();
      if (distance < nearest) {
        nearest = distance;
        current = index;
      }
    }
    final next = geometry.families[(current + step) % geometry.families.length];
    _spinTo(focus - middle(next));
  }

  /// Spins to [marker]'s swatch and applies it.
  void _showMarker(MarkerColor marker) {
    if (_mode != AmazeColorMode.copic) _setMode(AmazeColorMode.copic);
    _applyMarker(marker);
    final geometry = _geometry;
    final swatch = geometry?.byCode(marker.code);
    if (geometry == null || swatch == null) return;
    final rotation = MarkerRingGeometry.rotationToShow(
      swatch,
      center: _center,
      screen: _screen,
      from: _rotation,
    );
    if (rotation != null && rotation != _rotation) _spinTo(rotation);
  }

  Future<void> _openMore() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 440),
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: AmazeColorMoreSheet(
          color: _applied,
          markers: widget.palette,
          recentColors: widget.recentColors(),
          source: widget.paletteSource,
          onColor: (color) {
            Navigator.of(sheet).pop();
            _apply(color);
          },
          onMarker: (marker) {
            Navigator.of(sheet).pop();
            _showMarker(marker);
          },
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (_showsWheel && key == LogicalKeyboardKey.arrowRight) {
      _spinFamily(1);
      return KeyEventResult.handled;
    }
    if (_showsWheel && key == LogicalKeyboardKey.arrowLeft) {
      _spinFamily(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screen = constraints.biggest;
            _relayout(screen);
            final geometry = _geometry;
            final picked = _pickedMarker;
            final selected = picked != null && _matches.contains(picked)
                ? {picked.code}
                : {for (final marker in _matches) marker.code};
            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    onPointerCancel: _onPointerCancel,
                    onPointerSignal: _onPointerSignal,
                    child: _showsWheel && geometry != null
                        ? RepaintBoundary(
                            child: CustomPaint(
                              key: const ValueKey('amaze-color-ring'),
                              size: Size.infinite,
                              painter: MarkerWheelPainter(
                                geometry: geometry,
                                center: _center,
                                rotation: _rotation,
                                selected: selected,
                                discColor: Theme.of(context).colorScheme.surface
                                    .withValues(alpha: 0.86),
                                holeRadius: _ownCenter ? 0 : _innerRadius,
                                labelStyle: Theme.of(context)
                                    .textTheme
                                    .labelSmall,
                              ),
                            ),
                          )
                        : const SizedBox.expand(),
                  ),
                ),
                if (!_showsWheel)
                  Positioned.fill(
                    child: ChannelRings(
                      // One key for both modes keeps the precise HSL values
                      // when switching.
                      key: const ValueKey('amaze-color-rings'),
                      mode: _mode == AmazeColorMode.rgb
                          ? AmazeColorMode.rgb
                          : AmazeColorMode.hsl,
                      color: _color,
                      center: _center,
                      clearRadius: _plainControlsRadius,
                      onPreview: _preview,
                      onCommit: _apply,
                    ),
                  ),
                if (_ownCenter)
                  Positioned.fromRect(
                    rect: Rect.fromCircle(center: _center, radius: 28),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: const ValueKey('amaze-color-center'),
                        decoration: BoxDecoration(
                          color: Color(_color.value),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black54, width: 2),
                        ),
                      ),
                    ),
                  ),
                ..._buildControls(context, screen),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Rectangles of [sizes] laid out left to right along an arc of [radius]
  /// around the wheel, centered on [direction].
  List<Rect> _arc(
    List<Size> sizes,
    double radius,
    double direction, {
    double spacing = 8,
  }) {
    final total =
        sizes.fold(0.0, (sum, size) => sum + size.width) +
        spacing * (sizes.length - 1);
    // Seen from below the wheel, right on screen is a smaller angle.
    final sign = math.sin(direction) >= 0 ? -1 : 1;
    var cursor = -total / 2;
    final rects = <Rect>[];
    for (final size in sizes) {
      final offset = cursor + size.width / 2;
      rects.add(
        Rect.fromCenter(
          center:
              _center +
              Offset.fromDirection(direction + sign * offset / radius, radius),
          width: size.width,
          height: size.height,
        ),
      );
      cursor += size.width + spacing;
    }
    return rects;
  }

  List<Widget> _buildControls(BuildContext context, Size screen) {
    final loc = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final code = switch (_pickedMarker) {
      final picked? when _matches.contains(picked) => picked.code,
      _ when _matches.isNotEmpty => _matches.map((m) => m.code).join(' / '),
      _ => _color.toHexString(alpha: false),
    };
    final name = switch (_pickedMarker) {
      final picked? when _matches.contains(picked) => picked.name,
      _ when _matches.length == 1 => _matches.first.name,
      _ => '',
    };

    Widget round(Key key, String tooltip, VoidCallback onTap, Widget icon) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: scheme.surface,
          shape: const CircleBorder(),
          elevation: 1,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: key,
            onTap: onTap,
            child: Center(child: icon),
          ),
        ),
      );
    }

    Widget chip(Key key, SRGBColor base) {
      final color = base.withValues(a: _color.a);
      final selected = _color.value & 0xFFFFFF == base.value & 0xFFFFFF;
      return Tooltip(
        message: base.toHexString(alpha: false),
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: () => _apply(color),
          child: Center(
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Color(base.value),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.primary : Colors.black45,
                  width: selected ? 3 : 1.5,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final plain = !_showsWheel;
    final modes = <(Size, Widget)>[
      for (final mode in AmazeColorMode.values)
        if (mode != AmazeColorMode.copic || widget.palette != null)
          (
            Size(mode == AmazeColorMode.copic ? 62 : 48, 36),
            Semantics(
              selected: _mode == mode,
              button: true,
              child: Material(
                // The active mode sits on a soft chip.
                color: _mode == mode
                    ? Color.alphaBlend(
                        scheme.onSurface.withValues(alpha: 0.16),
                        scheme.surface,
                      )
                    : plain
                    ? scheme.surface.withValues(alpha: 0.86)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('amaze-color-mode-${mode.name}'),
                  onTap: () => _setMode(mode),
                  child: Center(
                    child: Text(
                      mode.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _mode == mode
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      (
        const Size(40, 40),
        round(
          const ValueKey('amaze-color-more'),
          loc.more,
          _openMore,
          const PhosphorIcon(PhosphorIconsLight.dotsThree, size: 22),
        ),
      ),
    ];
    final chips = <(Size, Widget)>[
      (
        const Size(36, 36),
        chip(const ValueKey('amaze-color-black'), SRGBColor.black),
      ),
      (
        const Size(36, 36),
        chip(const ValueKey('amaze-color-white'), SRGBColor.white),
      ),
    ];
    final eyedropper = round(
      const ValueKey('amaze-color-eyedropper'),
      loc.eyeDropper,
      () => _close(eyedropper: true),
      const PhosphorIcon(PhosphorIconsLight.eyedropper, size: 20),
    );
    final label = IgnorePointer(
      child: Material(
        key: const ValueKey('amaze-color-label'),
        color: scheme.surface,
        shape: const StadiumBorder(),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                code,
                key: const ValueKey('amaze-color-code'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              if (name.isNotEmpty)
                Text(
                  name,
                  key: const ValueKey('amaze-color-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.1,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // With the wheel shown, the controls sit on the light disc between the
    // tool wheel and the inner arc; otherwise close around the tool wheel.
    final geometry = _geometry;
    // Around a small tool wheel the arc keeps a radius of at least 200, so
    // that the row does not curl round onto the tool wheel.
    final radius = !plain && geometry != null
        ? math.min(
            math.max(
              _innerRadius + 0.45 * (geometry.discInner - 6 - _innerRadius),
              200.0,
            ),
            geometry.discInner - 30,
          )
        : _plainArcRadius;
    double width(List<(Size, Widget)> row, [double spacing = 8]) =>
        row.fold(0.0, (sum, item) => sum + item.$1.width) +
        spacing * (row.length - 1);

    // The mode labels run along the disc above the tool wheel, or below it
    // if there is no room above. The black and white chips follow them to
    // the right and the code label is tucked between them and the tool
    // wheel.
    List<(Rect, Widget)> group({required bool up}) {
      final direction = up ? -math.pi / 2 : math.pi / 2;
      // Further round the arc in this direction is further right.
      final rightward = up ? 1 : -1;
      const chipSpacing = 16.0;
      final modeRects = _arc(
        [for (final (size, _) in modes) size],
        radius,
        direction,
      );
      final chipRects = _arc(
        [for (final (size, _) in chips) size],
        radius,
        direction +
            rightward *
                (width(modes) / 2 + 20 + width(chips, chipSpacing) / 2) /
                radius,
        spacing: chipSpacing,
      );
      Rect labelAt(double distance) => Rect.fromCenter(
        center: _center + Offset.fromDirection(direction, distance),
        width: 116,
        height: 32,
      );
      var labelRect = labelAt(radius - 48);
      if (modeRects.any(labelRect.overlaps)) {
        // Around a small tool wheel the arc of modes bends further in; the
        // label then sits halfway between the tool wheel and the modes.
        final modesInner = modeRects
            .map(
              (rect) => up ? _center.dy - rect.bottom : rect.top - _center.dy,
            )
            .reduce(math.min);
        labelRect = labelAt((_innerRadius + modesInner) / 2);
      }
      return [
        for (final (index, (_, widget)) in modes.indexed)
          (modeRects[index], widget),
        for (final (index, (_, widget)) in chips.indexed)
          (chipRects[index], widget),
        if (!plain) (labelRect, label),
      ];
    }

    Rect hull(List<(Rect, Widget)> placed) =>
        placed.map((item) => item.$1).reduce((a, b) => a.expandToInclude(b));

    /// How far [rect] reaches past the top or bottom of the screen.
    double overflow(Rect rect) =>
        math.max(0.0, -rect.top) + math.max(0.0, rect.bottom - screen.height);

    /// The shift that brings [rect] on screen, if it fits.
    Offset shiftOnScreen(Rect rect) => Offset(
      rect.left < 0 ? -rect.left : math.min(0.0, screen.width - rect.right),
      rect.top < 0 ? -rect.top : math.min(0.0, screen.height - rect.bottom),
    );

    final above = group(up: true);
    final below = group(up: false);
    final chosen = overflow(hull(above)) <= overflow(hull(below))
        ? above
        : below;
    // The row moves sideways as a whole to stay on screen.
    final shift = shiftOnScreen(hull(chosen));

    // The eyedropper sits right of the tool wheel, or left of it at the
    // right edge of the screen.
    final eyeRadius = (plain ? _plainArcRadius - 32 : _innerRadius) + 30;
    var eye = Rect.fromCenter(
      center: _center + Offset(eyeRadius, 0),
      width: 40,
      height: 40,
    );
    if (eye.right > screen.width) {
      eye = eye.shift(Offset(-2 * eyeRadius, 0));
    }
    return [
      for (final (rect, widget) in chosen)
        Positioned.fromRect(rect: rect.shift(shift), child: widget),
      Positioned.fromRect(
        rect: eye.shift(shiftOnScreen(eye)),
        child: eyedropper,
      ),
    ];
  }
}
