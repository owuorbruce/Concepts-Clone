// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'brush.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BrushWidth {

/// Exponent applied to pressure. 0 ignores pressure.
 double get pressureGamma;/// Smallest width, as a ratio of the stroke width.
 double get minRatio;/// How much speed thins the stroke (0–1).
 double get speed;/// EMA factor for the speed (0 = no smoothing).
 double get speedSmoothing;
/// Create a copy of BrushWidth
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrushWidthCopyWith<BrushWidth> get copyWith => _$BrushWidthCopyWithImpl<BrushWidth>(this as BrushWidth, _$identity);

  /// Serializes this BrushWidth to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BrushWidth;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrushWidth&&(identical(other.pressureGamma, _this.pressureGamma) || other.pressureGamma == _this.pressureGamma)&&(identical(other.minRatio, _this.minRatio) || other.minRatio == _this.minRatio)&&(identical(other.speed, _this.speed) || other.speed == _this.speed)&&(identical(other.speedSmoothing, _this.speedSmoothing) || other.speedSmoothing == _this.speedSmoothing));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BrushWidth;
  return Object.hash(runtimeType,_this.pressureGamma,_this.minRatio,_this.speed,_this.speedSmoothing);
}

@override
String toString() {
  final _this = this as BrushWidth;
  return 'BrushWidth(pressureGamma: ${_this.pressureGamma}, minRatio: ${_this.minRatio}, speed: ${_this.speed}, speedSmoothing: ${_this.speedSmoothing})';
}


}

/// @nodoc
abstract mixin class $BrushWidthCopyWith<$Res>  {
  factory $BrushWidthCopyWith(BrushWidth value, $Res Function(BrushWidth) _then) = _$BrushWidthCopyWithImpl;
@useResult
$Res call({
 double pressureGamma, double minRatio, double speed, double speedSmoothing
});




}
/// @nodoc
class _$BrushWidthCopyWithImpl<$Res>
    implements $BrushWidthCopyWith<$Res> {
  _$BrushWidthCopyWithImpl(this._self, this._then);

  final BrushWidth _self;
  final $Res Function(BrushWidth) _then;

/// Create a copy of BrushWidth
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pressureGamma = null,Object? minRatio = null,Object? speed = null,Object? speedSmoothing = null,}) {
  return _then(BrushWidth(
pressureGamma: null == pressureGamma ? _self.pressureGamma : pressureGamma // ignore: cast_nullable_to_non_nullable
as double,minRatio: null == minRatio ? _self.minRatio : minRatio // ignore: cast_nullable_to_non_nullable
as double,speed: null == speed ? _self.speed : speed // ignore: cast_nullable_to_non_nullable
as double,speedSmoothing: null == speedSmoothing ? _self.speedSmoothing : speedSmoothing // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _BrushWidth implements BrushWidth {
  const _BrushWidth({this.pressureGamma = 1.0, this.minRatio = 0.15, this.speed = 0, this.speedSmoothing = 0.6});
  factory _BrushWidth.fromJson(Map<String, dynamic> json) => _$BrushWidthFromJson(json);

/// Exponent applied to pressure. 0 ignores pressure.
@override@JsonKey() final  double pressureGamma;
/// Smallest width, as a ratio of the stroke width.
@override@JsonKey() final  double minRatio;
/// How much speed thins the stroke (0–1).
@override@JsonKey() final  double speed;
/// EMA factor for the speed (0 = no smoothing).
@override@JsonKey() final  double speedSmoothing;

/// Create a copy of BrushWidth
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrushWidthCopyWith<_BrushWidth> get copyWith => __$BrushWidthCopyWithImpl<_BrushWidth>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BrushWidthToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrushWidth&&(identical(other.pressureGamma, pressureGamma) || other.pressureGamma == pressureGamma)&&(identical(other.minRatio, minRatio) || other.minRatio == minRatio)&&(identical(other.speed, speed) || other.speed == speed)&&(identical(other.speedSmoothing, speedSmoothing) || other.speedSmoothing == speedSmoothing));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,pressureGamma,minRatio,speed,speedSmoothing);
}

@override
String toString() {
    return 'BrushWidth(pressureGamma: $pressureGamma, minRatio: $minRatio, speed: $speed, speedSmoothing: $speedSmoothing)';
}


}

/// @nodoc
abstract mixin class _$BrushWidthCopyWith<$Res> implements $BrushWidthCopyWith<$Res> {
  factory _$BrushWidthCopyWith(_BrushWidth value, $Res Function(_BrushWidth) _then) = __$BrushWidthCopyWithImpl;
@override @useResult
$Res call({
 double pressureGamma, double minRatio, double speed, double speedSmoothing
});




}
/// @nodoc
class __$BrushWidthCopyWithImpl<$Res>
    implements _$BrushWidthCopyWith<$Res> {
  __$BrushWidthCopyWithImpl(this._self, this._then);

  final _BrushWidth _self;
  final $Res Function(_BrushWidth) _then;

/// Create a copy of BrushWidth
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pressureGamma = null,Object? minRatio = null,Object? speed = null,Object? speedSmoothing = null,}) {
  return _then(_BrushWidth(
pressureGamma: null == pressureGamma ? _self.pressureGamma : pressureGamma // ignore: cast_nullable_to_non_nullable
as double,minRatio: null == minRatio ? _self.minRatio : minRatio // ignore: cast_nullable_to_non_nullable
as double,speed: null == speed ? _self.speed : speed // ignore: cast_nullable_to_non_nullable
as double,speedSmoothing: null == speedSmoothing ? _self.speedSmoothing : speedSmoothing // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$BrushNib {

 double get angleDeg;/// Width across the nib relative to along it. 1 = round.
 double get aspect;
/// Create a copy of BrushNib
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrushNibCopyWith<BrushNib> get copyWith => _$BrushNibCopyWithImpl<BrushNib>(this as BrushNib, _$identity);

  /// Serializes this BrushNib to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BrushNib;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrushNib&&(identical(other.angleDeg, _this.angleDeg) || other.angleDeg == _this.angleDeg)&&(identical(other.aspect, _this.aspect) || other.aspect == _this.aspect));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BrushNib;
  return Object.hash(runtimeType,_this.angleDeg,_this.aspect);
}

@override
String toString() {
  final _this = this as BrushNib;
  return 'BrushNib(angleDeg: ${_this.angleDeg}, aspect: ${_this.aspect})';
}


}

/// @nodoc
abstract mixin class $BrushNibCopyWith<$Res>  {
  factory $BrushNibCopyWith(BrushNib value, $Res Function(BrushNib) _then) = _$BrushNibCopyWithImpl;
@useResult
$Res call({
 double angleDeg, double aspect
});




}
/// @nodoc
class _$BrushNibCopyWithImpl<$Res>
    implements $BrushNibCopyWith<$Res> {
  _$BrushNibCopyWithImpl(this._self, this._then);

  final BrushNib _self;
  final $Res Function(BrushNib) _then;

/// Create a copy of BrushNib
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? angleDeg = null,Object? aspect = null,}) {
  return _then(BrushNib(
angleDeg: null == angleDeg ? _self.angleDeg : angleDeg // ignore: cast_nullable_to_non_nullable
as double,aspect: null == aspect ? _self.aspect : aspect // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _BrushNib implements BrushNib {
  const _BrushNib({this.angleDeg = 45, this.aspect = 1.0});
  factory _BrushNib.fromJson(Map<String, dynamic> json) => _$BrushNibFromJson(json);

@override@JsonKey() final  double angleDeg;
/// Width across the nib relative to along it. 1 = round.
@override@JsonKey() final  double aspect;

/// Create a copy of BrushNib
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrushNibCopyWith<_BrushNib> get copyWith => __$BrushNibCopyWithImpl<_BrushNib>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BrushNibToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrushNib&&(identical(other.angleDeg, angleDeg) || other.angleDeg == angleDeg)&&(identical(other.aspect, aspect) || other.aspect == aspect));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,angleDeg,aspect);
}

@override
String toString() {
    return 'BrushNib(angleDeg: $angleDeg, aspect: $aspect)';
}


}

/// @nodoc
abstract mixin class _$BrushNibCopyWith<$Res> implements $BrushNibCopyWith<$Res> {
  factory _$BrushNibCopyWith(_BrushNib value, $Res Function(_BrushNib) _then) = __$BrushNibCopyWithImpl;
@override @useResult
$Res call({
 double angleDeg, double aspect
});




}
/// @nodoc
class __$BrushNibCopyWithImpl<$Res>
    implements _$BrushNibCopyWith<$Res> {
  __$BrushNibCopyWithImpl(this._self, this._then);

  final _BrushNib _self;
  final $Res Function(_BrushNib) _then;

/// Create a copy of BrushNib
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? angleDeg = null,Object? aspect = null,}) {
  return _then(_BrushNib(
angleDeg: null == angleDeg ? _self.angleDeg : angleDeg // ignore: cast_nullable_to_non_nullable
as double,aspect: null == aspect ? _self.aspect : aspect // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$BrushTaper {

 double get start; double get end;
/// Create a copy of BrushTaper
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrushTaperCopyWith<BrushTaper> get copyWith => _$BrushTaperCopyWithImpl<BrushTaper>(this as BrushTaper, _$identity);

  /// Serializes this BrushTaper to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BrushTaper;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrushTaper&&(identical(other.start, _this.start) || other.start == _this.start)&&(identical(other.end, _this.end) || other.end == _this.end));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BrushTaper;
  return Object.hash(runtimeType,_this.start,_this.end);
}

@override
String toString() {
  final _this = this as BrushTaper;
  return 'BrushTaper(start: ${_this.start}, end: ${_this.end})';
}


}

/// @nodoc
abstract mixin class $BrushTaperCopyWith<$Res>  {
  factory $BrushTaperCopyWith(BrushTaper value, $Res Function(BrushTaper) _then) = _$BrushTaperCopyWithImpl;
@useResult
$Res call({
 double start, double end
});




}
/// @nodoc
class _$BrushTaperCopyWithImpl<$Res>
    implements $BrushTaperCopyWith<$Res> {
  _$BrushTaperCopyWithImpl(this._self, this._then);

  final BrushTaper _self;
  final $Res Function(BrushTaper) _then;

/// Create a copy of BrushTaper
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? start = null,Object? end = null,}) {
  return _then(BrushTaper(
start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as double,end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _BrushTaper implements BrushTaper {
  const _BrushTaper({this.start = 0, this.end = 0});
  factory _BrushTaper.fromJson(Map<String, dynamic> json) => _$BrushTaperFromJson(json);

@override@JsonKey() final  double start;
@override@JsonKey() final  double end;

/// Create a copy of BrushTaper
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrushTaperCopyWith<_BrushTaper> get copyWith => __$BrushTaperCopyWithImpl<_BrushTaper>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BrushTaperToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrushTaper&&(identical(other.start, start) || other.start == start)&&(identical(other.end, end) || other.end == end));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,start,end);
}

@override
String toString() {
    return 'BrushTaper(start: $start, end: $end)';
}


}

/// @nodoc
abstract mixin class _$BrushTaperCopyWith<$Res> implements $BrushTaperCopyWith<$Res> {
  factory _$BrushTaperCopyWith(_BrushTaper value, $Res Function(_BrushTaper) _then) = __$BrushTaperCopyWithImpl;
@override @useResult
$Res call({
 double start, double end
});




}
/// @nodoc
class __$BrushTaperCopyWithImpl<$Res>
    implements _$BrushTaperCopyWith<$Res> {
  __$BrushTaperCopyWithImpl(this._self, this._then);

  final _BrushTaper _self;
  final $Res Function(_BrushTaper) _then;

/// Create a copy of BrushTaper
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? start = null,Object? end = null,}) {
  return _then(_BrushTaper(
start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as double,end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$BrushDash {

 double get length; double get gap;
/// Create a copy of BrushDash
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrushDashCopyWith<BrushDash> get copyWith => _$BrushDashCopyWithImpl<BrushDash>(this as BrushDash, _$identity);

  /// Serializes this BrushDash to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BrushDash;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrushDash&&(identical(other.length, _this.length) || other.length == _this.length)&&(identical(other.gap, _this.gap) || other.gap == _this.gap));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BrushDash;
  return Object.hash(runtimeType,_this.length,_this.gap);
}

@override
String toString() {
  final _this = this as BrushDash;
  return 'BrushDash(length: ${_this.length}, gap: ${_this.gap})';
}


}

/// @nodoc
abstract mixin class $BrushDashCopyWith<$Res>  {
  factory $BrushDashCopyWith(BrushDash value, $Res Function(BrushDash) _then) = _$BrushDashCopyWithImpl;
@useResult
$Res call({
 double length, double gap
});




}
/// @nodoc
class _$BrushDashCopyWithImpl<$Res>
    implements $BrushDashCopyWith<$Res> {
  _$BrushDashCopyWithImpl(this._self, this._then);

  final BrushDash _self;
  final $Res Function(BrushDash) _then;

/// Create a copy of BrushDash
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? length = null,Object? gap = null,}) {
  return _then(BrushDash(
length: null == length ? _self.length : length // ignore: cast_nullable_to_non_nullable
as double,gap: null == gap ? _self.gap : gap // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _BrushDash implements BrushDash {
  const _BrushDash({this.length = 0, this.gap = 0});
  factory _BrushDash.fromJson(Map<String, dynamic> json) => _$BrushDashFromJson(json);

@override@JsonKey() final  double length;
@override@JsonKey() final  double gap;

/// Create a copy of BrushDash
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrushDashCopyWith<_BrushDash> get copyWith => __$BrushDashCopyWithImpl<_BrushDash>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BrushDashToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrushDash&&(identical(other.length, length) || other.length == length)&&(identical(other.gap, gap) || other.gap == gap));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,length,gap);
}

@override
String toString() {
    return 'BrushDash(length: $length, gap: $gap)';
}


}

/// @nodoc
abstract mixin class _$BrushDashCopyWith<$Res> implements $BrushDashCopyWith<$Res> {
  factory _$BrushDashCopyWith(_BrushDash value, $Res Function(_BrushDash) _then) = __$BrushDashCopyWithImpl;
@override @useResult
$Res call({
 double length, double gap
});




}
/// @nodoc
class __$BrushDashCopyWithImpl<$Res>
    implements _$BrushDashCopyWith<$Res> {
  __$BrushDashCopyWithImpl(this._self, this._then);

  final _BrushDash _self;
  final $Res Function(_BrushDash) _then;

/// Create a copy of BrushDash
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? length = null,Object? gap = null,}) {
  return _then(_BrushDash(
length: null == length ? _self.length : length // ignore: cast_nullable_to_non_nullable
as double,gap: null == gap ? _self.gap : gap // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$BrushOpacity {

/// Exponent applied to pressure. 0 ignores pressure.
 double get pressureGamma;/// Smallest opacity factor.
 double get min;
/// Create a copy of BrushOpacity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrushOpacityCopyWith<BrushOpacity> get copyWith => _$BrushOpacityCopyWithImpl<BrushOpacity>(this as BrushOpacity, _$identity);

  /// Serializes this BrushOpacity to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BrushOpacity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrushOpacity&&(identical(other.pressureGamma, _this.pressureGamma) || other.pressureGamma == _this.pressureGamma)&&(identical(other.min, _this.min) || other.min == _this.min));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BrushOpacity;
  return Object.hash(runtimeType,_this.pressureGamma,_this.min);
}

@override
String toString() {
  final _this = this as BrushOpacity;
  return 'BrushOpacity(pressureGamma: ${_this.pressureGamma}, min: ${_this.min})';
}


}

/// @nodoc
abstract mixin class $BrushOpacityCopyWith<$Res>  {
  factory $BrushOpacityCopyWith(BrushOpacity value, $Res Function(BrushOpacity) _then) = _$BrushOpacityCopyWithImpl;
@useResult
$Res call({
 double pressureGamma, double min
});




}
/// @nodoc
class _$BrushOpacityCopyWithImpl<$Res>
    implements $BrushOpacityCopyWith<$Res> {
  _$BrushOpacityCopyWithImpl(this._self, this._then);

  final BrushOpacity _self;
  final $Res Function(BrushOpacity) _then;

/// Create a copy of BrushOpacity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pressureGamma = null,Object? min = null,}) {
  return _then(BrushOpacity(
pressureGamma: null == pressureGamma ? _self.pressureGamma : pressureGamma // ignore: cast_nullable_to_non_nullable
as double,min: null == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _BrushOpacity implements BrushOpacity {
  const _BrushOpacity({this.pressureGamma = 0, this.min = 1.0});
  factory _BrushOpacity.fromJson(Map<String, dynamic> json) => _$BrushOpacityFromJson(json);

/// Exponent applied to pressure. 0 ignores pressure.
@override@JsonKey() final  double pressureGamma;
/// Smallest opacity factor.
@override@JsonKey() final  double min;

/// Create a copy of BrushOpacity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrushOpacityCopyWith<_BrushOpacity> get copyWith => __$BrushOpacityCopyWithImpl<_BrushOpacity>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BrushOpacityToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrushOpacity&&(identical(other.pressureGamma, pressureGamma) || other.pressureGamma == pressureGamma)&&(identical(other.min, min) || other.min == min));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,pressureGamma,min);
}

@override
String toString() {
    return 'BrushOpacity(pressureGamma: $pressureGamma, min: $min)';
}


}

/// @nodoc
abstract mixin class _$BrushOpacityCopyWith<$Res> implements $BrushOpacityCopyWith<$Res> {
  factory _$BrushOpacityCopyWith(_BrushOpacity value, $Res Function(_BrushOpacity) _then) = __$BrushOpacityCopyWithImpl;
@override @useResult
$Res call({
 double pressureGamma, double min
});




}
/// @nodoc
class __$BrushOpacityCopyWithImpl<$Res>
    implements _$BrushOpacityCopyWith<$Res> {
  __$BrushOpacityCopyWithImpl(this._self, this._then);

  final _BrushOpacity _self;
  final $Res Function(_BrushOpacity) _then;

/// Create a copy of BrushOpacity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pressureGamma = null,Object? min = null,}) {
  return _then(_BrushOpacity(
pressureGamma: null == pressureGamma ? _self.pressureGamma : pressureGamma // ignore: cast_nullable_to_non_nullable
as double,min: null == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$BrushGrain {

 String get texture; double get scale; double get strength;
/// Create a copy of BrushGrain
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrushGrainCopyWith<BrushGrain> get copyWith => _$BrushGrainCopyWithImpl<BrushGrain>(this as BrushGrain, _$identity);

  /// Serializes this BrushGrain to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BrushGrain;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrushGrain&&(identical(other.texture, _this.texture) || other.texture == _this.texture)&&(identical(other.scale, _this.scale) || other.scale == _this.scale)&&(identical(other.strength, _this.strength) || other.strength == _this.strength));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BrushGrain;
  return Object.hash(runtimeType,_this.texture,_this.scale,_this.strength);
}

@override
String toString() {
  final _this = this as BrushGrain;
  return 'BrushGrain(texture: ${_this.texture}, scale: ${_this.scale}, strength: ${_this.strength})';
}


}

/// @nodoc
abstract mixin class $BrushGrainCopyWith<$Res>  {
  factory $BrushGrainCopyWith(BrushGrain value, $Res Function(BrushGrain) _then) = _$BrushGrainCopyWithImpl;
@useResult
$Res call({
 String texture, double scale, double strength
});




}
/// @nodoc
class _$BrushGrainCopyWithImpl<$Res>
    implements $BrushGrainCopyWith<$Res> {
  _$BrushGrainCopyWithImpl(this._self, this._then);

  final BrushGrain _self;
  final $Res Function(BrushGrain) _then;

/// Create a copy of BrushGrain
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? texture = null,Object? scale = null,Object? strength = null,}) {
  return _then(BrushGrain(
texture: null == texture ? _self.texture : texture // ignore: cast_nullable_to_non_nullable
as String,scale: null == scale ? _self.scale : scale // ignore: cast_nullable_to_non_nullable
as double,strength: null == strength ? _self.strength : strength // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _BrushGrain implements BrushGrain {
  const _BrushGrain({this.texture = '', this.scale = 1, this.strength = 0});
  factory _BrushGrain.fromJson(Map<String, dynamic> json) => _$BrushGrainFromJson(json);

@override@JsonKey() final  String texture;
@override@JsonKey() final  double scale;
@override@JsonKey() final  double strength;

/// Create a copy of BrushGrain
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrushGrainCopyWith<_BrushGrain> get copyWith => __$BrushGrainCopyWithImpl<_BrushGrain>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BrushGrainToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrushGrain&&(identical(other.texture, texture) || other.texture == texture)&&(identical(other.scale, scale) || other.scale == scale)&&(identical(other.strength, strength) || other.strength == strength));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,texture,scale,strength);
}

@override
String toString() {
    return 'BrushGrain(texture: $texture, scale: $scale, strength: $strength)';
}


}

/// @nodoc
abstract mixin class _$BrushGrainCopyWith<$Res> implements $BrushGrainCopyWith<$Res> {
  factory _$BrushGrainCopyWith(_BrushGrain value, $Res Function(_BrushGrain) _then) = __$BrushGrainCopyWithImpl;
@override @useResult
$Res call({
 String texture, double scale, double strength
});




}
/// @nodoc
class __$BrushGrainCopyWithImpl<$Res>
    implements _$BrushGrainCopyWith<$Res> {
  __$BrushGrainCopyWithImpl(this._self, this._then);

  final _BrushGrain _self;
  final $Res Function(_BrushGrain) _then;

/// Create a copy of BrushGrain
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? texture = null,Object? scale = null,Object? strength = null,}) {
  return _then(_BrushGrain(
texture: null == texture ? _self.texture : texture // ignore: cast_nullable_to_non_nullable
as String,scale: null == scale ? _self.scale : scale // ignore: cast_nullable_to_non_nullable
as double,strength: null == strength ? _self.strength : strength // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$BrushDynamic {

 BrushInput get input; BrushOutput get output;/// Piecewise-linear points `[x, y]`, x in 0–1, sorted by x.
 List<List<double>> get curve;
/// Create a copy of BrushDynamic
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrushDynamicCopyWith<BrushDynamic> get copyWith => _$BrushDynamicCopyWithImpl<BrushDynamic>(this as BrushDynamic, _$identity);

  /// Serializes this BrushDynamic to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BrushDynamic;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrushDynamic&&(identical(other.input, _this.input) || other.input == _this.input)&&(identical(other.output, _this.output) || other.output == _this.output)&&const DeepCollectionEquality().equals(other.curve, _this.curve));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BrushDynamic;
  return Object.hash(runtimeType,_this.input,_this.output,const DeepCollectionEquality().hash(_this.curve));
}

@override
String toString() {
  final _this = this as BrushDynamic;
  return 'BrushDynamic(input: ${_this.input}, output: ${_this.output}, curve: ${_this.curve})';
}


}

/// @nodoc
abstract mixin class $BrushDynamicCopyWith<$Res>  {
  factory $BrushDynamicCopyWith(BrushDynamic value, $Res Function(BrushDynamic) _then) = _$BrushDynamicCopyWithImpl;
@useResult
$Res call({
 BrushInput input, BrushOutput output, List<List<double>> curve
});




}
/// @nodoc
class _$BrushDynamicCopyWithImpl<$Res>
    implements $BrushDynamicCopyWith<$Res> {
  _$BrushDynamicCopyWithImpl(this._self, this._then);

  final BrushDynamic _self;
  final $Res Function(BrushDynamic) _then;

/// Create a copy of BrushDynamic
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? input = null,Object? output = null,Object? curve = null,}) {
  return _then(BrushDynamic(
input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as BrushInput,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as BrushOutput,curve: null == curve ? _self.curve : curve // ignore: cast_nullable_to_non_nullable
as List<List<double>>,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _BrushDynamic implements BrushDynamic {
  const _BrushDynamic({this.input = BrushInput.pressure, this.output = BrushOutput.size,  List<List<double>> curve = const <List<double>>[]}): _curve = curve;
  factory _BrushDynamic.fromJson(Map<String, dynamic> json) => _$BrushDynamicFromJson(json);

@override@JsonKey() final  BrushInput input;
@override@JsonKey() final  BrushOutput output;
/// Piecewise-linear points `[x, y]`, x in 0–1, sorted by x.
 final  List<List<double>> _curve;
/// Piecewise-linear points `[x, y]`, x in 0–1, sorted by x.
@override@JsonKey() List<List<double>> get curve {
  if (_curve is EqualUnmodifiableListView) return _curve;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_curve);
}


/// Create a copy of BrushDynamic
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrushDynamicCopyWith<_BrushDynamic> get copyWith => __$BrushDynamicCopyWithImpl<_BrushDynamic>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BrushDynamicToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrushDynamic&&(identical(other.input, input) || other.input == input)&&(identical(other.output, output) || other.output == output)&&const DeepCollectionEquality().equals(other.curve, _curve));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,input,output,const DeepCollectionEquality().hash(_curve));
}

@override
String toString() {
    return 'BrushDynamic(input: $input, output: $output, curve: $curve)';
}


}

/// @nodoc
abstract mixin class _$BrushDynamicCopyWith<$Res> implements $BrushDynamicCopyWith<$Res> {
  factory _$BrushDynamicCopyWith(_BrushDynamic value, $Res Function(_BrushDynamic) _then) = __$BrushDynamicCopyWithImpl;
@override @useResult
$Res call({
 BrushInput input, BrushOutput output, List<List<double>> curve
});




}
/// @nodoc
class __$BrushDynamicCopyWithImpl<$Res>
    implements _$BrushDynamicCopyWith<$Res> {
  __$BrushDynamicCopyWithImpl(this._self, this._then);

  final _BrushDynamic _self;
  final $Res Function(_BrushDynamic) _then;

/// Create a copy of BrushDynamic
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? input = null,Object? output = null,Object? curve = null,}) {
  return _then(_BrushDynamic(
input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as BrushInput,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as BrushOutput,curve: null == curve ? _self._curve : curve // ignore: cast_nullable_to_non_nullable
as List<List<double>>,
  ));
}


}


/// @nodoc
mixin _$BrushDefinition {

 String get id; int get version; String get name; BrushEngine get engine; BrushWidth get width; BrushNib get nib; BrushTaper get taper; BrushDash get dash; bool get hairline; BrushOpacity get opacity; String get texture; double get spacing; double get scatter; double get sizeJitter; double get angleJitter; BrushAngleMode get angleMode; double get flow; bool get buildUp; BrushGrain get grain; bool get tiltShading; double get wetEdges; BrushBlend get blend; double? get defaultSize; double? get defaultOpacity; List<BrushDynamic> get dynamics;
/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrushDefinitionCopyWith<BrushDefinition> get copyWith => _$BrushDefinitionCopyWithImpl<BrushDefinition>(this as BrushDefinition, _$identity);

  /// Serializes this BrushDefinition to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BrushDefinition;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrushDefinition&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.engine, _this.engine) || other.engine == _this.engine)&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.nib, _this.nib) || other.nib == _this.nib)&&(identical(other.taper, _this.taper) || other.taper == _this.taper)&&(identical(other.dash, _this.dash) || other.dash == _this.dash)&&(identical(other.hairline, _this.hairline) || other.hairline == _this.hairline)&&(identical(other.opacity, _this.opacity) || other.opacity == _this.opacity)&&(identical(other.texture, _this.texture) || other.texture == _this.texture)&&(identical(other.spacing, _this.spacing) || other.spacing == _this.spacing)&&(identical(other.scatter, _this.scatter) || other.scatter == _this.scatter)&&(identical(other.sizeJitter, _this.sizeJitter) || other.sizeJitter == _this.sizeJitter)&&(identical(other.angleJitter, _this.angleJitter) || other.angleJitter == _this.angleJitter)&&(identical(other.angleMode, _this.angleMode) || other.angleMode == _this.angleMode)&&(identical(other.flow, _this.flow) || other.flow == _this.flow)&&(identical(other.buildUp, _this.buildUp) || other.buildUp == _this.buildUp)&&(identical(other.grain, _this.grain) || other.grain == _this.grain)&&(identical(other.tiltShading, _this.tiltShading) || other.tiltShading == _this.tiltShading)&&(identical(other.wetEdges, _this.wetEdges) || other.wetEdges == _this.wetEdges)&&(identical(other.blend, _this.blend) || other.blend == _this.blend)&&(identical(other.defaultSize, _this.defaultSize) || other.defaultSize == _this.defaultSize)&&(identical(other.defaultOpacity, _this.defaultOpacity) || other.defaultOpacity == _this.defaultOpacity)&&const DeepCollectionEquality().equals(other.dynamics, _this.dynamics));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BrushDefinition;
  return Object.hashAll([runtimeType,_this.id,_this.version,_this.name,_this.engine,_this.width,_this.nib,_this.taper,_this.dash,_this.hairline,_this.opacity,_this.texture,_this.spacing,_this.scatter,_this.sizeJitter,_this.angleJitter,_this.angleMode,_this.flow,_this.buildUp,_this.grain,_this.tiltShading,_this.wetEdges,_this.blend,_this.defaultSize,_this.defaultOpacity,const DeepCollectionEquality().hash(_this.dynamics)]);
}

@override
String toString() {
  final _this = this as BrushDefinition;
  return 'BrushDefinition(id: ${_this.id}, version: ${_this.version}, name: ${_this.name}, engine: ${_this.engine}, width: ${_this.width}, nib: ${_this.nib}, taper: ${_this.taper}, dash: ${_this.dash}, hairline: ${_this.hairline}, opacity: ${_this.opacity}, texture: ${_this.texture}, spacing: ${_this.spacing}, scatter: ${_this.scatter}, sizeJitter: ${_this.sizeJitter}, angleJitter: ${_this.angleJitter}, angleMode: ${_this.angleMode}, flow: ${_this.flow}, buildUp: ${_this.buildUp}, grain: ${_this.grain}, tiltShading: ${_this.tiltShading}, wetEdges: ${_this.wetEdges}, blend: ${_this.blend}, defaultSize: ${_this.defaultSize}, defaultOpacity: ${_this.defaultOpacity}, dynamics: ${_this.dynamics})';
}


}

/// @nodoc
abstract mixin class $BrushDefinitionCopyWith<$Res>  {
  factory $BrushDefinitionCopyWith(BrushDefinition value, $Res Function(BrushDefinition) _then) = _$BrushDefinitionCopyWithImpl;
@useResult
$Res call({
 String id, int version, String name, BrushEngine engine, BrushWidth width, BrushNib nib, BrushTaper taper, BrushDash dash, bool hairline, BrushOpacity opacity, String texture, double spacing, double scatter, double sizeJitter, double angleJitter, BrushAngleMode angleMode, double flow, bool buildUp, BrushGrain grain, bool tiltShading, double wetEdges, BrushBlend blend, double? defaultSize, double? defaultOpacity, List<BrushDynamic> dynamics
});


$BrushWidthCopyWith<$Res> get width;$BrushNibCopyWith<$Res> get nib;$BrushTaperCopyWith<$Res> get taper;$BrushDashCopyWith<$Res> get dash;$BrushOpacityCopyWith<$Res> get opacity;$BrushGrainCopyWith<$Res> get grain;

}
/// @nodoc
class _$BrushDefinitionCopyWithImpl<$Res>
    implements $BrushDefinitionCopyWith<$Res> {
  _$BrushDefinitionCopyWithImpl(this._self, this._then);

  final BrushDefinition _self;
  final $Res Function(BrushDefinition) _then;

/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? version = null,Object? name = null,Object? engine = null,Object? width = null,Object? nib = null,Object? taper = null,Object? dash = null,Object? hairline = null,Object? opacity = null,Object? texture = null,Object? spacing = null,Object? scatter = null,Object? sizeJitter = null,Object? angleJitter = null,Object? angleMode = null,Object? flow = null,Object? buildUp = null,Object? grain = null,Object? tiltShading = null,Object? wetEdges = null,Object? blend = null,Object? defaultSize = freezed,Object? defaultOpacity = freezed,Object? dynamics = null,}) {
  return _then(BrushDefinition(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,engine: null == engine ? _self.engine : engine // ignore: cast_nullable_to_non_nullable
as BrushEngine,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as BrushWidth,nib: null == nib ? _self.nib : nib // ignore: cast_nullable_to_non_nullable
as BrushNib,taper: null == taper ? _self.taper : taper // ignore: cast_nullable_to_non_nullable
as BrushTaper,dash: null == dash ? _self.dash : dash // ignore: cast_nullable_to_non_nullable
as BrushDash,hairline: null == hairline ? _self.hairline : hairline // ignore: cast_nullable_to_non_nullable
as bool,opacity: null == opacity ? _self.opacity : opacity // ignore: cast_nullable_to_non_nullable
as BrushOpacity,texture: null == texture ? _self.texture : texture // ignore: cast_nullable_to_non_nullable
as String,spacing: null == spacing ? _self.spacing : spacing // ignore: cast_nullable_to_non_nullable
as double,scatter: null == scatter ? _self.scatter : scatter // ignore: cast_nullable_to_non_nullable
as double,sizeJitter: null == sizeJitter ? _self.sizeJitter : sizeJitter // ignore: cast_nullable_to_non_nullable
as double,angleJitter: null == angleJitter ? _self.angleJitter : angleJitter // ignore: cast_nullable_to_non_nullable
as double,angleMode: null == angleMode ? _self.angleMode : angleMode // ignore: cast_nullable_to_non_nullable
as BrushAngleMode,flow: null == flow ? _self.flow : flow // ignore: cast_nullable_to_non_nullable
as double,buildUp: null == buildUp ? _self.buildUp : buildUp // ignore: cast_nullable_to_non_nullable
as bool,grain: null == grain ? _self.grain : grain // ignore: cast_nullable_to_non_nullable
as BrushGrain,tiltShading: null == tiltShading ? _self.tiltShading : tiltShading // ignore: cast_nullable_to_non_nullable
as bool,wetEdges: null == wetEdges ? _self.wetEdges : wetEdges // ignore: cast_nullable_to_non_nullable
as double,blend: null == blend ? _self.blend : blend // ignore: cast_nullable_to_non_nullable
as BrushBlend,defaultSize: freezed == defaultSize ? _self.defaultSize : defaultSize // ignore: cast_nullable_to_non_nullable
as double?,defaultOpacity: freezed == defaultOpacity ? _self.defaultOpacity : defaultOpacity // ignore: cast_nullable_to_non_nullable
as double?,dynamics: null == dynamics ? _self.dynamics : dynamics // ignore: cast_nullable_to_non_nullable
as List<BrushDynamic>,
  ));
}
/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushWidthCopyWith<$Res> get width {
  
  return $BrushWidthCopyWith<$Res>(_self.width, (value) {
    return _then(_self.copyWith(width: value));
  });
}/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushNibCopyWith<$Res> get nib {
  
  return $BrushNibCopyWith<$Res>(_self.nib, (value) {
    return _then(_self.copyWith(nib: value));
  });
}/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushTaperCopyWith<$Res> get taper {
  
  return $BrushTaperCopyWith<$Res>(_self.taper, (value) {
    return _then(_self.copyWith(taper: value));
  });
}/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushDashCopyWith<$Res> get dash {
  
  return $BrushDashCopyWith<$Res>(_self.dash, (value) {
    return _then(_self.copyWith(dash: value));
  });
}/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushOpacityCopyWith<$Res> get opacity {
  
  return $BrushOpacityCopyWith<$Res>(_self.opacity, (value) {
    return _then(_self.copyWith(opacity: value));
  });
}/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushGrainCopyWith<$Res> get grain {
  
  return $BrushGrainCopyWith<$Res>(_self.grain, (value) {
    return _then(_self.copyWith(grain: value));
  });
}
}



/// @nodoc
@JsonSerializable()

class _BrushDefinition implements BrushDefinition {
  const _BrushDefinition({this.id = '', this.version = 1, this.name = '', this.engine = BrushEngine.outline, this.width = const BrushWidth(), this.nib = const BrushNib(), this.taper = const BrushTaper(), this.dash = const BrushDash(), this.hairline = false, this.opacity = const BrushOpacity(), this.texture = '', this.spacing = 0.1, this.scatter = 0, this.sizeJitter = 0, this.angleJitter = 0, this.angleMode = BrushAngleMode.direction, this.flow = 1, this.buildUp = true, this.grain = const BrushGrain(), this.tiltShading = false, this.wetEdges = 0, this.blend = BrushBlend.normal, this.defaultSize, this.defaultOpacity,  List<BrushDynamic> dynamics = const <BrushDynamic>[]}): _dynamics = dynamics;
  factory _BrushDefinition.fromJson(Map<String, dynamic> json) => _$BrushDefinitionFromJson(json);

@override@JsonKey() final  String id;
@override@JsonKey() final  int version;
@override@JsonKey() final  String name;
@override@JsonKey() final  BrushEngine engine;
@override@JsonKey() final  BrushWidth width;
@override@JsonKey() final  BrushNib nib;
@override@JsonKey() final  BrushTaper taper;
@override@JsonKey() final  BrushDash dash;
@override@JsonKey() final  bool hairline;
@override@JsonKey() final  BrushOpacity opacity;
@override@JsonKey() final  String texture;
@override@JsonKey() final  double spacing;
@override@JsonKey() final  double scatter;
@override@JsonKey() final  double sizeJitter;
@override@JsonKey() final  double angleJitter;
@override@JsonKey() final  BrushAngleMode angleMode;
@override@JsonKey() final  double flow;
@override@JsonKey() final  bool buildUp;
@override@JsonKey() final  BrushGrain grain;
@override@JsonKey() final  bool tiltShading;
@override@JsonKey() final  double wetEdges;
@override@JsonKey() final  BrushBlend blend;
@override final  double? defaultSize;
@override final  double? defaultOpacity;
 final  List<BrushDynamic> _dynamics;
@override@JsonKey() List<BrushDynamic> get dynamics {
  if (_dynamics is EqualUnmodifiableListView) return _dynamics;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_dynamics);
}


/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrushDefinitionCopyWith<_BrushDefinition> get copyWith => __$BrushDefinitionCopyWithImpl<_BrushDefinition>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BrushDefinitionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrushDefinition&&(identical(other.id, id) || other.id == id)&&(identical(other.version, version) || other.version == version)&&(identical(other.name, name) || other.name == name)&&(identical(other.engine, engine) || other.engine == engine)&&(identical(other.width, width) || other.width == width)&&(identical(other.nib, nib) || other.nib == nib)&&(identical(other.taper, taper) || other.taper == taper)&&(identical(other.dash, dash) || other.dash == dash)&&(identical(other.hairline, hairline) || other.hairline == hairline)&&(identical(other.opacity, opacity) || other.opacity == opacity)&&(identical(other.texture, texture) || other.texture == texture)&&(identical(other.spacing, spacing) || other.spacing == spacing)&&(identical(other.scatter, scatter) || other.scatter == scatter)&&(identical(other.sizeJitter, sizeJitter) || other.sizeJitter == sizeJitter)&&(identical(other.angleJitter, angleJitter) || other.angleJitter == angleJitter)&&(identical(other.angleMode, angleMode) || other.angleMode == angleMode)&&(identical(other.flow, flow) || other.flow == flow)&&(identical(other.buildUp, buildUp) || other.buildUp == buildUp)&&(identical(other.grain, grain) || other.grain == grain)&&(identical(other.tiltShading, tiltShading) || other.tiltShading == tiltShading)&&(identical(other.wetEdges, wetEdges) || other.wetEdges == wetEdges)&&(identical(other.blend, blend) || other.blend == blend)&&(identical(other.defaultSize, defaultSize) || other.defaultSize == defaultSize)&&(identical(other.defaultOpacity, defaultOpacity) || other.defaultOpacity == defaultOpacity)&&const DeepCollectionEquality().equals(other.dynamics, _dynamics));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,version,name,engine,width,nib,taper,dash,hairline,opacity,texture,spacing,scatter,sizeJitter,angleJitter,angleMode,flow,buildUp,grain,tiltShading,wetEdges,blend,defaultSize,defaultOpacity,const DeepCollectionEquality().hash(_dynamics)]);
}

@override
String toString() {
    return 'BrushDefinition(id: $id, version: $version, name: $name, engine: $engine, width: $width, nib: $nib, taper: $taper, dash: $dash, hairline: $hairline, opacity: $opacity, texture: $texture, spacing: $spacing, scatter: $scatter, sizeJitter: $sizeJitter, angleJitter: $angleJitter, angleMode: $angleMode, flow: $flow, buildUp: $buildUp, grain: $grain, tiltShading: $tiltShading, wetEdges: $wetEdges, blend: $blend, defaultSize: $defaultSize, defaultOpacity: $defaultOpacity, dynamics: $dynamics)';
}


}

/// @nodoc
abstract mixin class _$BrushDefinitionCopyWith<$Res> implements $BrushDefinitionCopyWith<$Res> {
  factory _$BrushDefinitionCopyWith(_BrushDefinition value, $Res Function(_BrushDefinition) _then) = __$BrushDefinitionCopyWithImpl;
@override @useResult
$Res call({
 String id, int version, String name, BrushEngine engine, BrushWidth width, BrushNib nib, BrushTaper taper, BrushDash dash, bool hairline, BrushOpacity opacity, String texture, double spacing, double scatter, double sizeJitter, double angleJitter, BrushAngleMode angleMode, double flow, bool buildUp, BrushGrain grain, bool tiltShading, double wetEdges, BrushBlend blend, double? defaultSize, double? defaultOpacity, List<BrushDynamic> dynamics
});


@override $BrushWidthCopyWith<$Res> get width;@override $BrushNibCopyWith<$Res> get nib;@override $BrushTaperCopyWith<$Res> get taper;@override $BrushDashCopyWith<$Res> get dash;@override $BrushOpacityCopyWith<$Res> get opacity;@override $BrushGrainCopyWith<$Res> get grain;

}
/// @nodoc
class __$BrushDefinitionCopyWithImpl<$Res>
    implements _$BrushDefinitionCopyWith<$Res> {
  __$BrushDefinitionCopyWithImpl(this._self, this._then);

  final _BrushDefinition _self;
  final $Res Function(_BrushDefinition) _then;

/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? version = null,Object? name = null,Object? engine = null,Object? width = null,Object? nib = null,Object? taper = null,Object? dash = null,Object? hairline = null,Object? opacity = null,Object? texture = null,Object? spacing = null,Object? scatter = null,Object? sizeJitter = null,Object? angleJitter = null,Object? angleMode = null,Object? flow = null,Object? buildUp = null,Object? grain = null,Object? tiltShading = null,Object? wetEdges = null,Object? blend = null,Object? defaultSize = freezed,Object? defaultOpacity = freezed,Object? dynamics = null,}) {
  return _then(_BrushDefinition(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,engine: null == engine ? _self.engine : engine // ignore: cast_nullable_to_non_nullable
as BrushEngine,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as BrushWidth,nib: null == nib ? _self.nib : nib // ignore: cast_nullable_to_non_nullable
as BrushNib,taper: null == taper ? _self.taper : taper // ignore: cast_nullable_to_non_nullable
as BrushTaper,dash: null == dash ? _self.dash : dash // ignore: cast_nullable_to_non_nullable
as BrushDash,hairline: null == hairline ? _self.hairline : hairline // ignore: cast_nullable_to_non_nullable
as bool,opacity: null == opacity ? _self.opacity : opacity // ignore: cast_nullable_to_non_nullable
as BrushOpacity,texture: null == texture ? _self.texture : texture // ignore: cast_nullable_to_non_nullable
as String,spacing: null == spacing ? _self.spacing : spacing // ignore: cast_nullable_to_non_nullable
as double,scatter: null == scatter ? _self.scatter : scatter // ignore: cast_nullable_to_non_nullable
as double,sizeJitter: null == sizeJitter ? _self.sizeJitter : sizeJitter // ignore: cast_nullable_to_non_nullable
as double,angleJitter: null == angleJitter ? _self.angleJitter : angleJitter // ignore: cast_nullable_to_non_nullable
as double,angleMode: null == angleMode ? _self.angleMode : angleMode // ignore: cast_nullable_to_non_nullable
as BrushAngleMode,flow: null == flow ? _self.flow : flow // ignore: cast_nullable_to_non_nullable
as double,buildUp: null == buildUp ? _self.buildUp : buildUp // ignore: cast_nullable_to_non_nullable
as bool,grain: null == grain ? _self.grain : grain // ignore: cast_nullable_to_non_nullable
as BrushGrain,tiltShading: null == tiltShading ? _self.tiltShading : tiltShading // ignore: cast_nullable_to_non_nullable
as bool,wetEdges: null == wetEdges ? _self.wetEdges : wetEdges // ignore: cast_nullable_to_non_nullable
as double,blend: null == blend ? _self.blend : blend // ignore: cast_nullable_to_non_nullable
as BrushBlend,defaultSize: freezed == defaultSize ? _self.defaultSize : defaultSize // ignore: cast_nullable_to_non_nullable
as double?,defaultOpacity: freezed == defaultOpacity ? _self.defaultOpacity : defaultOpacity // ignore: cast_nullable_to_non_nullable
as double?,dynamics: null == dynamics ? _self._dynamics : dynamics // ignore: cast_nullable_to_non_nullable
as List<BrushDynamic>,
  ));
}

/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushWidthCopyWith<$Res> get width {
  
  return $BrushWidthCopyWith<$Res>(_self.width, (value) {
    return _then(_self.copyWith(width: value));
  });
}/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushNibCopyWith<$Res> get nib {
  
  return $BrushNibCopyWith<$Res>(_self.nib, (value) {
    return _then(_self.copyWith(nib: value));
  });
}/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushTaperCopyWith<$Res> get taper {
  
  return $BrushTaperCopyWith<$Res>(_self.taper, (value) {
    return _then(_self.copyWith(taper: value));
  });
}/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushDashCopyWith<$Res> get dash {
  
  return $BrushDashCopyWith<$Res>(_self.dash, (value) {
    return _then(_self.copyWith(dash: value));
  });
}/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushOpacityCopyWith<$Res> get opacity {
  
  return $BrushOpacityCopyWith<$Res>(_self.opacity, (value) {
    return _then(_self.copyWith(opacity: value));
  });
}/// Create a copy of BrushDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrushGrainCopyWith<$Res> get grain {
  
  return $BrushGrainCopyWith<$Res>(_self.grain, (value) {
    return _then(_self.copyWith(grain: value));
  });
}
}

// dart format on
