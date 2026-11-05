import 'package:material_ui/material_ui.dart';

/// Visual tokens for the aMaze editor shell.
///
/// Surfaces follow the active [ColorScheme], so the shell works with light,
/// dark and custom themes; the teal accent is aMaze's own.
class AmazeStyle {
  const AmazeStyle._({
    required this.accent,
    required this.onAccent,
    required this.surface,
    required this.onSurface,
    required this.outline,
    required this.shadow,
  });

  factory AmazeStyle.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return AmazeStyle._(
      accent: dark ? const Color(0xFF4FD6C4) : const Color(0xFF0B8F84),
      onAccent: dark ? const Color(0xFF00201D) : const Color(0xFFFFFFFF),
      surface: scheme.surfaceContainerHigh.withValues(alpha: 0.96),
      onSurface: scheme.onSurface,
      outline: scheme.outlineVariant,
      shadow: const Color(0xFF000000).withValues(alpha: dark ? 0.5 : 0.18),
    );
  }

  /// Highlight color for the selected tool and the wheel hub.
  final Color accent;

  /// Content color on top of [accent].
  final Color onAccent;

  /// Background of floating shell surfaces.
  final Color surface;

  /// Content color on top of [surface].
  final Color onSurface;

  /// Hairline border around floating surfaces.
  final Color outline;

  /// Drop shadow color for floating surfaces.
  final Color shadow;

  List<BoxShadow> get shadows {
    const offset = Offset(0, 6);
    return [BoxShadow(color: shadow, blurRadius: 18, offset: offset)];
  }
}

/// Rounded floating surface used by the dock and side panels.
class AmazeSurface extends StatelessWidget {
  const AmazeSurface({super.key, required this.child, this.radius = 28});

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
