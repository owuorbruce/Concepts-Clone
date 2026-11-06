import 'package:material_ui/material_ui.dart';

/// Visual tokens for the aMaze editor shell.
///
/// Surfaces are opaque and come from the active [ColorScheme], so the shell
/// follows light, dark and custom themes; the teal accent is aMaze's own.
/// The tool wheel and tool bar sit inside [instrumentTheme], which gives
/// them one dark, high-contrast look over any canvas.
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

  /// Theme for the tool wheel, tool bar and their panels: a dark housing
  /// that keeps its contrast over a bright canvas in every app theme.
  static ThemeData instrumentTheme(BuildContext context) {
    final base = Theme.of(context);
    final seeded = ColorScheme.fromSeed(
      seedColor: const Color(0xFF117C72),
      brightness: Brightness.dark,
    );
    final scheme = seeded.copyWith(
      primary: const Color(0xFF53D9BD),
      onPrimary: const Color(0xFF092C28),
      surface: const Color(0xFF1C2A31),
      surfaceContainerHigh: const Color(0xFF23353B),
      surfaceContainerHighest: const Color(0xFF344951),
      onSurface: const Color(0xFFF4F8F6),
      onSurfaceVariant: const Color(0xFFB0C6C5),
      outlineVariant: const Color(0xFF586F72),
    );
    final textTheme = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    return base.copyWith(
      colorScheme: scheme,
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
