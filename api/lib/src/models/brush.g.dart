// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'brush.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BrushWidth _$BrushWidthFromJson(Map json) => _BrushWidth(
  pressureGamma: (json['pressureGamma'] as num?)?.toDouble() ?? 1.0,
  minRatio: (json['minRatio'] as num?)?.toDouble() ?? 0.15,
  speed: (json['speed'] as num?)?.toDouble() ?? 0,
  speedSmoothing: (json['speedSmoothing'] as num?)?.toDouble() ?? 0.6,
);

Map<String, dynamic> _$BrushWidthToJson(_BrushWidth instance) =>
    <String, dynamic>{
      'pressureGamma': instance.pressureGamma,
      'minRatio': instance.minRatio,
      'speed': instance.speed,
      'speedSmoothing': instance.speedSmoothing,
    };

_BrushNib _$BrushNibFromJson(Map json) => _BrushNib(
  angleDeg: (json['angleDeg'] as num?)?.toDouble() ?? 45,
  aspect: (json['aspect'] as num?)?.toDouble() ?? 1.0,
);

Map<String, dynamic> _$BrushNibToJson(_BrushNib instance) => <String, dynamic>{
  'angleDeg': instance.angleDeg,
  'aspect': instance.aspect,
};

_BrushTaper _$BrushTaperFromJson(Map json) => _BrushTaper(
  start: (json['start'] as num?)?.toDouble() ?? 0,
  end: (json['end'] as num?)?.toDouble() ?? 0,
);

Map<String, dynamic> _$BrushTaperToJson(_BrushTaper instance) =>
    <String, dynamic>{'start': instance.start, 'end': instance.end};

_BrushDash _$BrushDashFromJson(Map json) => _BrushDash(
  length: (json['length'] as num?)?.toDouble() ?? 0,
  gap: (json['gap'] as num?)?.toDouble() ?? 0,
);

Map<String, dynamic> _$BrushDashToJson(_BrushDash instance) =>
    <String, dynamic>{'length': instance.length, 'gap': instance.gap};

_BrushOpacity _$BrushOpacityFromJson(Map json) => _BrushOpacity(
  pressureGamma: (json['pressureGamma'] as num?)?.toDouble() ?? 0,
  min: (json['min'] as num?)?.toDouble() ?? 1.0,
);

Map<String, dynamic> _$BrushOpacityToJson(_BrushOpacity instance) =>
    <String, dynamic>{
      'pressureGamma': instance.pressureGamma,
      'min': instance.min,
    };

_BrushGrain _$BrushGrainFromJson(Map json) => _BrushGrain(
  texture: json['texture'] as String? ?? '',
  scale: (json['scale'] as num?)?.toDouble() ?? 1,
  strength: (json['strength'] as num?)?.toDouble() ?? 0,
);

Map<String, dynamic> _$BrushGrainToJson(_BrushGrain instance) =>
    <String, dynamic>{
      'texture': instance.texture,
      'scale': instance.scale,
      'strength': instance.strength,
    };

_BrushPattern _$BrushPatternFromJson(Map json) => _BrushPattern(
  texture: json['texture'] as String? ?? '',
  scale: (json['scale'] as num?)?.toDouble() ?? 1,
  angleDeg: (json['angleDeg'] as num?)?.toDouble() ?? 0,
);

Map<String, dynamic> _$BrushPatternToJson(_BrushPattern instance) =>
    <String, dynamic>{
      'texture': instance.texture,
      'scale': instance.scale,
      'angleDeg': instance.angleDeg,
    };

_BrushEndStamp _$BrushEndStampFromJson(Map json) => _BrushEndStamp(
  texture: json['texture'] as String? ?? '',
  size: (json['size'] as num?)?.toDouble() ?? 1,
);

Map<String, dynamic> _$BrushEndStampToJson(_BrushEndStamp instance) =>
    <String, dynamic>{'texture': instance.texture, 'size': instance.size};

_BrushDynamic _$BrushDynamicFromJson(Map json) => _BrushDynamic(
  input:
      $enumDecodeNullable(_$BrushInputEnumMap, json['input']) ??
      BrushInput.pressure,
  output:
      $enumDecodeNullable(_$BrushOutputEnumMap, json['output']) ??
      BrushOutput.size,
  curve:
      (json['curve'] as List<dynamic>?)
          ?.map(
            (e) =>
                (e as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
          )
          .toList() ??
      const <List<double>>[],
);

Map<String, dynamic> _$BrushDynamicToJson(_BrushDynamic instance) =>
    <String, dynamic>{
      'input': _$BrushInputEnumMap[instance.input]!,
      'output': _$BrushOutputEnumMap[instance.output]!,
      'curve': instance.curve,
    };

const _$BrushInputEnumMap = {
  BrushInput.pressure: 'pressure',
  BrushInput.speed: 'speed',
  BrushInput.tilt: 'tilt',
  BrushInput.direction: 'direction',
  BrushInput.random: 'random',
  BrushInput.strokeProgress: 'strokeProgress',
};

const _$BrushOutputEnumMap = {
  BrushOutput.size: 'size',
  BrushOutput.opacity: 'opacity',
  BrushOutput.angle: 'angle',
  BrushOutput.scatter: 'scatter',
};

_BrushDefinition _$BrushDefinitionFromJson(Map json) => _BrushDefinition(
  id: json['id'] as String? ?? '',
  version: (json['version'] as num?)?.toInt() ?? 1,
  name: json['name'] as String? ?? '',
  engine:
      $enumDecodeNullable(_$BrushEngineEnumMap, json['engine']) ??
      BrushEngine.outline,
  width: json['width'] == null
      ? const BrushWidth()
      : BrushWidth.fromJson(Map<String, dynamic>.from(json['width'] as Map)),
  nib: json['nib'] == null
      ? const BrushNib()
      : BrushNib.fromJson(Map<String, dynamic>.from(json['nib'] as Map)),
  taper: json['taper'] == null
      ? const BrushTaper()
      : BrushTaper.fromJson(Map<String, dynamic>.from(json['taper'] as Map)),
  dash: json['dash'] == null
      ? const BrushDash()
      : BrushDash.fromJson(Map<String, dynamic>.from(json['dash'] as Map)),
  hairline: json['hairline'] as bool? ?? false,
  opacity: json['opacity'] == null
      ? const BrushOpacity()
      : BrushOpacity.fromJson(
          Map<String, dynamic>.from(json['opacity'] as Map),
        ),
  texture: json['texture'] as String? ?? '',
  spacing: (json['spacing'] as num?)?.toDouble() ?? 0.1,
  scatter: (json['scatter'] as num?)?.toDouble() ?? 0,
  sizeJitter: (json['sizeJitter'] as num?)?.toDouble() ?? 0,
  angleJitter: (json['angleJitter'] as num?)?.toDouble() ?? 0,
  angleMode:
      $enumDecodeNullable(_$BrushAngleModeEnumMap, json['angleMode']) ??
      BrushAngleMode.direction,
  flow: (json['flow'] as num?)?.toDouble() ?? 1,
  buildUp: json['buildUp'] as bool? ?? true,
  grain: json['grain'] == null
      ? const BrushGrain()
      : BrushGrain.fromJson(Map<String, dynamic>.from(json['grain'] as Map)),
  tiltShading: json['tiltShading'] as bool? ?? false,
  wetEdges: (json['wetEdges'] as num?)?.toDouble() ?? 0,
  blend:
      $enumDecodeNullable(_$BrushBlendEnumMap, json['blend']) ??
      BrushBlend.normal,
  pattern: json['pattern'] == null
      ? const BrushPattern()
      : BrushPattern.fromJson(
          Map<String, dynamic>.from(json['pattern'] as Map),
        ),
  endStamp: json['endStamp'] == null
      ? null
      : BrushEndStamp.fromJson(
          Map<String, dynamic>.from(json['endStamp'] as Map),
        ),
  mask: json['mask'] as bool? ?? false,
  defaultSize: (json['defaultSize'] as num?)?.toDouble(),
  defaultOpacity: (json['defaultOpacity'] as num?)?.toDouble(),
  dynamics:
      (json['dynamics'] as List<dynamic>?)
          ?.map(
            (e) => BrushDynamic.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList() ??
      const <BrushDynamic>[],
);

Map<String, dynamic> _$BrushDefinitionToJson(_BrushDefinition instance) =>
    <String, dynamic>{
      'id': instance.id,
      'version': instance.version,
      'name': instance.name,
      'engine': _$BrushEngineEnumMap[instance.engine]!,
      'width': instance.width.toJson(),
      'nib': instance.nib.toJson(),
      'taper': instance.taper.toJson(),
      'dash': instance.dash.toJson(),
      'hairline': instance.hairline,
      'opacity': instance.opacity.toJson(),
      'texture': instance.texture,
      'spacing': instance.spacing,
      'scatter': instance.scatter,
      'sizeJitter': instance.sizeJitter,
      'angleJitter': instance.angleJitter,
      'angleMode': _$BrushAngleModeEnumMap[instance.angleMode]!,
      'flow': instance.flow,
      'buildUp': instance.buildUp,
      'grain': instance.grain.toJson(),
      'tiltShading': instance.tiltShading,
      'wetEdges': instance.wetEdges,
      'blend': _$BrushBlendEnumMap[instance.blend]!,
      'pattern': instance.pattern.toJson(),
      'endStamp': instance.endStamp?.toJson(),
      'mask': instance.mask,
      'defaultSize': instance.defaultSize,
      'defaultOpacity': instance.defaultOpacity,
      'dynamics': instance.dynamics.map((e) => e.toJson()).toList(),
    };

const _$BrushEngineEnumMap = {
  BrushEngine.outline: 'outline',
  BrushEngine.stamp: 'stamp',
};

const _$BrushAngleModeEnumMap = {
  BrushAngleMode.fixed: 'fixed',
  BrushAngleMode.direction: 'direction',
  BrushAngleMode.random: 'random',
};

const _$BrushBlendEnumMap = {
  BrushBlend.normal: 'normal',
  BrushBlend.multiply: 'multiply',
};
