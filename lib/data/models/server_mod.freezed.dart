// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'server_mod.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PeerEndpoint {

 String get uri;
/// Create a copy of PeerEndpoint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PeerEndpointCopyWith<PeerEndpoint> get copyWith => _$PeerEndpointCopyWithImpl<PeerEndpoint>(this as PeerEndpoint, _$identity);

  /// Serializes this PeerEndpoint to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PeerEndpoint&&(identical(other.uri, uri) || other.uri == uri));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uri);

@override
String toString() {
  return 'PeerEndpoint(uri: $uri)';
}


}

/// @nodoc
abstract mixin class $PeerEndpointCopyWith<$Res>  {
  factory $PeerEndpointCopyWith(PeerEndpoint value, $Res Function(PeerEndpoint) _then) = _$PeerEndpointCopyWithImpl;
@useResult
$Res call({
 String uri
});




}
/// @nodoc
class _$PeerEndpointCopyWithImpl<$Res>
    implements $PeerEndpointCopyWith<$Res> {
  _$PeerEndpointCopyWithImpl(this._self, this._then);

  final PeerEndpoint _self;
  final $Res Function(PeerEndpoint) _then;

/// Create a copy of PeerEndpoint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? uri = null,}) {
  return _then(_self.copyWith(
uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PeerEndpoint].
extension PeerEndpointPatterns on PeerEndpoint {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PeerEndpoint value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PeerEndpoint() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PeerEndpoint value)  $default,){
final _that = this;
switch (_that) {
case _PeerEndpoint():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PeerEndpoint value)?  $default,){
final _that = this;
switch (_that) {
case _PeerEndpoint() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String uri)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PeerEndpoint() when $default != null:
return $default(_that.uri);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String uri)  $default,) {final _that = this;
switch (_that) {
case _PeerEndpoint():
return $default(_that.uri);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String uri)?  $default,) {final _that = this;
switch (_that) {
case _PeerEndpoint() when $default != null:
return $default(_that.uri);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PeerEndpoint implements PeerEndpoint {
  const _PeerEndpoint({required this.uri});
  factory _PeerEndpoint.fromJson(Map<String, dynamic> json) => _$PeerEndpointFromJson(json);

@override final  String uri;

/// Create a copy of PeerEndpoint
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PeerEndpointCopyWith<_PeerEndpoint> get copyWith => __$PeerEndpointCopyWithImpl<_PeerEndpoint>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PeerEndpointToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PeerEndpoint&&(identical(other.uri, uri) || other.uri == uri));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uri);

@override
String toString() {
  return 'PeerEndpoint(uri: $uri)';
}


}

/// @nodoc
abstract mixin class _$PeerEndpointCopyWith<$Res> implements $PeerEndpointCopyWith<$Res> {
  factory _$PeerEndpointCopyWith(_PeerEndpoint value, $Res Function(_PeerEndpoint) _then) = __$PeerEndpointCopyWithImpl;
@override @useResult
$Res call({
 String uri
});




}
/// @nodoc
class __$PeerEndpointCopyWithImpl<$Res>
    implements _$PeerEndpointCopyWith<$Res> {
  __$PeerEndpointCopyWithImpl(this._self, this._then);

  final _PeerEndpoint _self;
  final $Res Function(_PeerEndpoint) _then;

/// Create a copy of PeerEndpoint
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? uri = null,}) {
  return _then(_PeerEndpoint(
uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
