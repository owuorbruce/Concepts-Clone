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
    required this.surfaceVariant,
    required this.onSurface,
    required this.muted,
    required this.outline,
    required this.shadow,
  });

  factory AmazeStyle.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A drawing instrument needs clear separation between its controls.
    // Use an opaque, high-contrast local palette instead of translucent
    // Material surfaces that blend into the page and competing toolbars.
    return AmazeStyle._(
      accent: dark ? const Color(0xFF53D9BD) : const Color(0xFF117C72),
      onAccent: dark ? const Color(0xFF092C28) : const Color(0xFFFFFFFF),
      surface: dark ? const Color(0xFF202C33) : const Color(0xFFFDFEFC),
      surfaceVariant: dark ? const Color(0xFF34434A) : const Color(0xFFE9F1EE),
      onSurface: dark ? const Color(0xFFF1F7F5) : const Color(0xFF1C3035),
      muted: dark ? const Color(0xFFA8C2BF) : const Color(0xFF647B7A),
      outline: dark ? const Color(0xFF52656D) : const Color(0xFFCDDDDA),
      shadow: const Color(0xFF000000).withValues(alpha: dark ? 0.42 : 0.13),
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
