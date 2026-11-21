import 'package:freezed_annotation/freezed_annotation.dart';

part 'brush.g.dart';
part 'brush.freezed.dart';

/// Which renderer draws a brush.
enum BrushEngine { outline, stamp }

/// How a stamp is rotated.
enum BrushAngleMode { fixed, direction, random }

/// How a finished stroke is composited onto the canvas.
enum BrushBlend { normal, multiply }

/// Input of a [BrushDynamic] mapping. Inputs are normalized to 0–1:
/// speed by 3 px/ms, tilt by π/2, direction by 2π.
enum BrushInput { pressure, speed, tilt, direction, random, strokeProgress }

/// Output of a [BrushDynamic] mapping. Size and opacity multiply,
/// angle (in radians) and scatter (in widths) add.
enum BrushOutput { size, opacity, angle, scatter }

/// Width response of a brush.
@freezed
sealed class BrushWidth with _$BrushWidth {
  const factory BrushWidth({
    /// Exponent applied to pressure. 0 ignores pressure.
    @Default(1.0) double pressureGamma,

    /// Smallest width, as a ratio of the stroke width.
    @Default(0.15) double minRatio,

    /// How much speed thins the stroke (0–1).
    @Default(0) double speed,

    /// EMA factor for the speed (0 = no smoothing).
    @Default(0.6) double speedSmoothing,
  }) = _BrushWidth;

  factory BrushWidth.fromJson(Map<String, dynamic> json) =>
      _$BrushWidthFromJson(json);
}

/// Calligraphy nib.
@freezed
sealed class BrushNib with _$BrushNib {
  const factory BrushNib({
    @Default(45) double angleDeg,

    /// Width across the nib relative to along it. 1 = round.
    @Default(1.0) double aspect,
  }) = _BrushNib;

  factory BrushNib.fromJson(Map<String, dynamic> json) =>
      _$BrushNibFromJson(json);
}

/// Tapered ends, in stroke widths.
@freezed
sealed class BrushTaper with _$BrushTaper {
  const factory BrushTaper({@Default(0) double start, @Default(0) double end}) =
      _BrushTaper;

  factory BrushTaper.fromJson(Map<String, dynamic> json) =>
      _$BrushTaperFromJson(json);
}

/// Dashes, in stroke widths. Both 0 = solid; length 0 with a gap = dots.
@freezed
sealed class BrushDash with _$BrushDash {
  const factory BrushDash({@Default(0) double length, @Default(0) double gap}) =
      _BrushDash;

  factory BrushDash.fromJson(Map<String, dynamic> json) =>
      _$BrushDashFromJson(json);
}

/// Opacity response of a brush.
@freezed
sealed class BrushOpacity with _$BrushOpacity {
  const factory BrushOpacity({
    /// Exponent applied to pressure. 0 ignores pressure.
    @Default(0) double pressureGamma,

    /// Smallest opacity factor.
    @Default(1.0) double min,
  }) = _BrushOpacity;

  factory BrushOpacity.fromJson(Map<String, dynamic> json) =>
      _$BrushOpacityFromJson(json);
}

/// Paper grain, anchored to the canvas.
@freezed
sealed class BrushGrain with _$BrushGrain {
  const factory BrushGrain({
    @Default('') String texture,
    @Default(1) double scale,
    @Default(0) double strength,
  }) = _BrushGrain;

  factory BrushGrain.fromJson(Map<String, dynamic> json) =>
      _$BrushGrainFromJson(json);
}

/// One input → output response curve (MyPaint/Ink style).
@freezed
sealed class BrushDynamic with _$BrushDynamic {
  const factory BrushDynamic({
    @Default(BrushInput.pressure) BrushInput input,
    @Default(BrushOutput.size) BrushOutput output,

    /// Piecewise-linear points `[x, y]`, x in 0–1, sorted by x.
    @Default(<List<double>>[]) List<List<double>> curve,
  }) = _BrushDynamic;

  factory BrushDynamic.fromJson(Map<String, dynamic> json) =>
      _$BrushDynamicFromJson(json);
}

/// A versioned brush. A stroke keeps the version it was drawn with.
@freezed
sealed class BrushDefinition with _$BrushDefinition {
  const factory BrushDefinition({
    @Default('') String id,
    @Default(1) int version,
    @Default('') String name,
    @Default(BrushEngine.outline) BrushEngine engine,
    @Default(BrushWidth()) BrushWidth width,
    @Default(BrushNib()) BrushNib nib,
    @Default(BrushTaper()) BrushTaper taper,
    @Default(BrushDash()) BrushDash dash,
    @Default(false) bool hairline,
    @Default(BrushOpacity()) BrushOpacity opacity,
    // Stamp engine
    @Default('') String texture,
    @Default(0.1) double spacing,
    @Default(0) double scatter,
    @Default(0) double sizeJitter,
    @Default(0) double angleJitter,
    @Default(BrushAngleMode.direction) BrushAngleMode angleMode,
    @Default(1) double flow,
    @Default(true) bool buildUp,
    @Default(BrushGrain()) BrushGrain grain,
    @Default(false) bool tiltShading,
    @Default(0) double wetEdges,
    @Default(BrushBlend.normal) BrushBlend blend,
    // Defaults for a new tool
    double? defaultSize,
    double? defaultOpacity,
    @Default(<BrushDynamic>[]) List<BrushDynamic> dynamics,
  }) = _BrushDefinition;

  factory BrushDefinition.fromJson(Map<String, dynamic> json) =>
      _$BrushDefinitionFromJson(json);
}

/// Versioned lookup of [BrushDefinition]s.
class BrushCatalog {
  final Map<String, Map<int, BrushDefinition>> _byId = {};

  void register(BrushDefinition definition) =>
      (_byId[definition.id] ??= {})[definition.version] = definition;

  void clear() => _byId.clear();

  Iterable<String> get ids => _byId.keys;

  /// Returns [version] if registered, else the newest version below it,
  /// else the newest. Without a version, the newest.
  BrushDefinition? byId(String id, [int? version]) {
    final versions = _byId[id];
    if (versions == null || versions.isEmpty) return null;
    if (version != null) {
      final exact = versions[version];
      if (exact != null) return exact;
      final below = versions.keys.where((v) => v < version);
      if (below.isNotEmpty) {
        return versions[below.reduce((a, b) => a > b ? a : b)];
      }
    }
    return versions[versions.keys.reduce((a, b) => a > b ? a : b)];
  }
}
