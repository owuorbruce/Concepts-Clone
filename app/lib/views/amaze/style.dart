import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// Opacity of the tool wheel's surfaces at rest, so the canvas shows through
/// slightly.
const kWheelSurfaceOpacity = 0.92;

/// Opacity of the whole tool wheel while a stroke passes underneath it.
const kWheelFadedOpacity = 0.3;

/// Black or white, whichever contrasts more with [background].
Color contrastingContent(Color background) {
  final luminance = background.computeLuminance();
  // Contrast ratio against white is 1.05 / (L + 0.05), against black
  // (L + 0.05) / 0.05; they are equal at L ≈ 0.179.
  return luminance > 0.179 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}

/// WCAG contrast ratio between two opaque colors.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

/// Visual tokens for the aMaze editor shell.
///
/// Surfaces come from the active [ColorScheme], so the shell, including the
/// tool wheel and tool bar, follows light, dark and custom themes; the teal
/// accent is aMaze's own.
class AmazeStyle {
  const AmazeStyle._({
    required this.accent,
    required this.onAccent,
    required this.surface,
    required this.surfaceVariant,
    required this.onSurface,
    required this.muted,
    required this.outline,
    required this.shadow,
  });

  factory AmazeStyle.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return AmazeStyle._(
      accent: dark ? const Color(0xFF53D9BD) : const Color(0xFF117C72),
      onAccent: dark ? const Color(0xFF092C28) : const Color(0xFFFFFFFF),
      surface: scheme.surfaceContainerHigh,
      surfaceVariant: scheme.surfaceContainerHighest,
      onSurface: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant,
      shadow: const Color(0xFF000000).withValues(alpha: dark ? 0.42 : 0.13),
    );
  }

  /// Theme for the tool wheel, tool bar and their panels. It follows the
  /// app's light or dark [ColorScheme], with text and icons in its
  /// on-surface color so they read on the wheel's surfaces.
  static ThemeData instrumentTheme(BuildContext context) {
    final base = Theme.of(context);
    final scheme = base.colorScheme;
    final textTheme = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    return base.copyWith(
      textTheme: textTheme,
      iconTheme: IconThemeData(color: scheme.onSurface),
    );
  }

  /// Highlight color for the selected tool and the wheel hub.
  final Color accent;

  /// Content color on top of [accent].
  final Color onAccent;

  /// Background of floating shell surfaces.
  final Color surface;

  /// Background of buttons on a [surface].
  final Color surfaceVariant;

  /// Content color on top of [surface].
  final Color onSurface;

  /// Secondary content color, for hints and empty slots.
  final Color muted;

  /// Hairline border around floating surfaces.
  final Color outline;

  /// Drop shadow color for floating surfaces.
  final Color shadow;

  List<BoxShadow> get shadows {
    const offset = Offset(0, 4);
    return [BoxShadow(color: shadow, blurRadius: 14, offset: offset)];
  }
}

/// Rounded floating surface used by the dock and side panels.
class AmazeSurface extends StatelessWidget {
  const AmazeSurface({super.key, required this.child, this.radius = 20});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final style = AmazeStyle.of(context);
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.surface,
        borderRadius: borderRadius,
        border: Border.all(color: style.outline),
        boxShadow: style.shadows,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ClipRRect(borderRadius: borderRadius, child: child),
      ),
    );
  }
}
