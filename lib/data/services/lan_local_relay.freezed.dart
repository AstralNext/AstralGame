// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lan_local_relay.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RelaySpec {

 String get key; bool get inject; bool get injectMulticast; bool get injectLoopback; bool get forward; bool get udpForward; String get listenHost; int get listenPort; String get targetHost; int get targetPort; String get multicast; int get multicastPort; String get title; String get parser; Uint8List? get payload;
/// Create a copy of _RelaySpec
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RelaySpecCopyWith<_RelaySpec> get copyWith => __$RelaySpecCopyWithImpl<_RelaySpec>(this as _RelaySpec, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RelaySpec&&(identical(other.key, key) || other.key == key)&&(identical(other.inject, inject) || other.inject == inject)&&(identical(other.injectMulticast, injectMulticast) || other.injectMulticast == injectMulticast)&&(identical(other.injectLoopback, injectLoopback) || other.injectLoopback == injectLoopback)&&(identical(other.forward, forward) || other.forward == forward)&&(identical(other.udpForward, udpForward) || other.udpForward == udpForward)&&(identical(other.listenHost, listenHost) || other.listenHost == listenHost)&&(identical(other.listenPort, listenPort) || other.listenPort == listenPort)&&(identical(other.targetHost, targetHost) || other.targetHost == targetHost)&&(identical(other.targetPort, targetPort) || other.targetPort == targetPort)&&(identical(other.multicast, multicast) || other.multicast == multicast)&&(identical(other.multicastPort, multicastPort) || other.multicastPort == multicastPort)&&(identical(other.title, title) || other.title == title)&&(identical(other.parser, parser) || other.parser == parser)&&const DeepCollectionEquality().equals(other.payload, payload));
}


@override
int get hashCode => Object.hash(runtimeType,key,inject,injectMulticast,injectLoopback,forward,udpForward,listenHost,listenPort,targetHost,targetPort,multicast,multicastPort,title,parser,const DeepCollectionEquality().hash(payload));

@override
String toString() {
  return '_RelaySpec(key: $key, inject: $inject, injectMulticast: $injectMulticast, injectLoopback: $injectLoopback, forward: $forward, udpForward: $udpForward, listenHost: $listenHost, listenPort: $listenPort, targetHost: $targetHost, targetPort: $targetPort, multicast: $multicast, multicastPort: $multicastPort, title: $title, parser: $parser, payload: $payload)';
}


}

/// @nodoc
abstract mixin class _$RelaySpecCopyWith<$Res>  {
  factory _$RelaySpecCopyWith(_RelaySpec value, $Res Function(_RelaySpec) _then) = __$RelaySpecCopyWithImpl;
@useResult
$Res call({
 String key, bool inject, bool injectMulticast, bool injectLoopback, bool forward, bool udpForward, String listenHost, int listenPort, String targetHost, int targetPort, String multicast, int multicastPort, String title, String parser, Uint8List? payload
});




}
/// @nodoc
class __$RelaySpecCopyWithImpl<$Res>
    implements _$RelaySpecCopyWith<$Res> {
  __$RelaySpecCopyWithImpl(this._self, this._then);

  final _RelaySpec _self;
  final $Res Function(_RelaySpec) _then;

/// Create a copy of _RelaySpec
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? inject = null,Object? injectMulticast = null,Object? injectLoopback = null,Object? forward = null,Object? udpForward = null,Object? listenHost = null,Object? listenPort = null,Object? targetHost = null,Object? targetPort = null,Object? multicast = null,Object? multicastPort = null,Object? title = null,Object? parser = null,Object? payload = freezed,}) {
  return _then(_self.copyWith(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,inject: null == inject ? _self.inject : inject // ignore: cast_nullable_to_non_nullable
as bool,injectMulticast: null == injectMulticast ? _self.injectMulticast : injectMulticast // ignore: cast_nullable_to_non_nullable
as bool,injectLoopback: null == injectLoopback ? _self.injectLoopback : injectLoopback // ignore: cast_nullable_to_non_nullable
as bool,forward: null == forward ? _self.forward : forward // ignore: cast_nullable_to_non_nullable
as bool,udpForward: null == udpForward ? _self.udpForward : udpForward // ignore: cast_nullable_to_non_nullable
as bool,listenHost: null == listenHost ? _self.listenHost : listenHost // ignore: cast_nullable_to_non_nullable
as String,listenPort: null == listenPort ? _self.listenPort : listenPort // ignore: cast_nullable_to_non_nullable
as int,targetHost: null == targetHost ? _self.targetHost : targetHost // ignore: cast_nullable_to_non_nullable
as String,targetPort: null == targetPort ? _self.targetPort : targetPort // ignore: cast_nullable_to_non_nullable
as int,multicast: null == multicast ? _self.multicast : multicast // ignore: cast_nullable_to_non_nullable
as String,multicastPort: null == multicastPort ? _self.multicastPort : multicastPort // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,parser: null == parser ? _self.parser : parser // ignore: cast_nullable_to_non_nullable
as String,payload: freezed == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as Uint8List?,
  ));
}

}


/// Adds pattern-matching-related methods to [_RelaySpec].
extension _RelaySpecPatterns on _RelaySpec {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _$RelaySpecImpl value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _$RelaySpecImpl() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _$RelaySpecImpl value)  $default,){
final _that = this;
switch (_that) {
case _$RelaySpecImpl():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _$RelaySpecImpl value)?  $default,){
final _that = this;
switch (_that) {
case _$RelaySpecImpl() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  bool inject,  bool injectMulticast,  bool injectLoopback,  bool forward,  bool udpForward,  String listenHost,  int listenPort,  String targetHost,  int targetPort,  String multicast,  int multicastPort,  String title,  String parser,  Uint8List? payload)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _$RelaySpecImpl() when $default != null:
return $default(_that.key,_that.inject,_that.injectMulticast,_that.injectLoopback,_that.forward,_that.udpForward,_that.listenHost,_that.listenPort,_that.targetHost,_that.targetPort,_that.multicast,_that.multicastPort,_that.title,_that.parser,_that.payload);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  bool inject,  bool injectMulticast,  bool injectLoopback,  bool forward,  bool udpForward,  String listenHost,  int listenPort,  String targetHost,  int targetPort,  String multicast,  int multicastPort,  String title,  String parser,  Uint8List? payload)  $default,) {final _that = this;
switch (_that) {
case _$RelaySpecImpl():
return $default(_that.key,_that.inject,_that.injectMulticast,_that.injectLoopback,_that.forward,_that.udpForward,_that.listenHost,_that.listenPort,_that.targetHost,_that.targetPort,_that.multicast,_that.multicastPort,_that.title,_that.parser,_that.payload);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  bool inject,  bool injectMulticast,  bool injectLoopback,  bool forward,  bool udpForward,  String listenHost,  int listenPort,  String targetHost,  int targetPort,  String multicast,  int multicastPort,  String title,  String parser,  Uint8List? payload)?  $default,) {final _that = this;
switch (_that) {
case _$RelaySpecImpl() when $default != null:
return $default(_that.key,_that.inject,_that.injectMulticast,_that.injectLoopback,_that.forward,_that.udpForward,_that.listenHost,_that.listenPort,_that.targetHost,_that.targetPort,_that.multicast,_that.multicastPort,_that.title,_that.parser,_that.payload);case _:
  return null;

}
}

}

/// @nodoc


class _$RelaySpecImpl extends _RelaySpec {
  const _$RelaySpecImpl({required this.key, required this.inject, required this.injectMulticast, required this.injectLoopback, required this.forward, required this.udpForward, required this.listenHost, required this.listenPort, required this.targetHost, required this.targetPort, required this.multicast, required this.multicastPort, required this.title, required this.parser, required this.payload}): super._();
  

@override final  String key;
@override final  bool inject;
@override final  bool injectMulticast;
@override final  bool injectLoopback;
@override final  bool forward;
@override final  bool udpForward;
@override final  String listenHost;
@override final  int listenPort;
@override final  String targetHost;
@override final  int targetPort;
@override final  String multicast;
@override final  int multicastPort;
@override final  String title;
@override final  String parser;
@override final  Uint8List? payload;

/// Create a copy of _RelaySpec
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$$RelaySpecImplCopyWith<_$RelaySpecImpl> get copyWith => __$$RelaySpecImplCopyWithImpl<_$RelaySpecImpl>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _$RelaySpecImpl&&(identical(other.key, key) || other.key == key)&&(identical(other.inject, inject) || other.inject == inject)&&(identical(other.injectMulticast, injectMulticast) || other.injectMulticast == injectMulticast)&&(identical(other.injectLoopback, injectLoopback) || other.injectLoopback == injectLoopback)&&(identical(other.forward, forward) || other.forward == forward)&&(identical(other.udpForward, udpForward) || other.udpForward == udpForward)&&(identical(other.listenHost, listenHost) || other.listenHost == listenHost)&&(identical(other.listenPort, listenPort) || other.listenPort == listenPort)&&(identical(other.targetHost, targetHost) || other.targetHost == targetHost)&&(identical(other.targetPort, targetPort) || other.targetPort == targetPort)&&(identical(other.multicast, multicast) || other.multicast == multicast)&&(identical(other.multicastPort, multicastPort) || other.multicastPort == multicastPort)&&(identical(other.title, title) || other.title == title)&&(identical(other.parser, parser) || other.parser == parser)&&const DeepCollectionEquality().equals(other.payload, payload));
}


@override
int get hashCode => Object.hash(runtimeType,key,inject,injectMulticast,injectLoopback,forward,udpForward,listenHost,listenPort,targetHost,targetPort,multicast,multicastPort,title,parser,const DeepCollectionEquality().hash(payload));

@override
String toString() {
  return '_RelaySpec(key: $key, inject: $inject, injectMulticast: $injectMulticast, injectLoopback: $injectLoopback, forward: $forward, udpForward: $udpForward, listenHost: $listenHost, listenPort: $listenPort, targetHost: $targetHost, targetPort: $targetPort, multicast: $multicast, multicastPort: $multicastPort, title: $title, parser: $parser, payload: $payload)';
}


}

/// @nodoc
abstract mixin class _$$RelaySpecImplCopyWith<$Res> implements _$RelaySpecCopyWith<$Res> {
  factory _$$RelaySpecImplCopyWith(_$RelaySpecImpl value, $Res Function(_$RelaySpecImpl) _then) = __$$RelaySpecImplCopyWithImpl;
@override @useResult
$Res call({
 String key, bool inject, bool injectMulticast, bool injectLoopback, bool forward, bool udpForward, String listenHost, int listenPort, String targetHost, int targetPort, String multicast, int multicastPort, String title, String parser, Uint8List? payload
});




}
/// @nodoc
class __$$RelaySpecImplCopyWithImpl<$Res>
    implements _$$RelaySpecImplCopyWith<$Res> {
  __$$RelaySpecImplCopyWithImpl(this._self, this._then);

  final _$RelaySpecImpl _self;
  final $Res Function(_$RelaySpecImpl) _then;

/// Create a copy of _RelaySpec
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? inject = null,Object? injectMulticast = null,Object? injectLoopback = null,Object? forward = null,Object? udpForward = null,Object? listenHost = null,Object? listenPort = null,Object? targetHost = null,Object? targetPort = null,Object? multicast = null,Object? multicastPort = null,Object? title = null,Object? parser = null,Object? payload = freezed,}) {
  return _then(_$RelaySpecImpl(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,inject: null == inject ? _self.inject : inject // ignore: cast_nullable_to_non_nullable
as bool,injectMulticast: null == injectMulticast ? _self.injectMulticast : injectMulticast // ignore: cast_nullable_to_non_nullable
as bool,injectLoopback: null == injectLoopback ? _self.injectLoopback : injectLoopback // ignore: cast_nullable_to_non_nullable
as bool,forward: null == forward ? _self.forward : forward // ignore: cast_nullable_to_non_nullable
as bool,udpForward: null == udpForward ? _self.udpForward : udpForward // ignore: cast_nullable_to_non_nullable
as bool,listenHost: null == listenHost ? _self.listenHost : listenHost // ignore: cast_nullable_to_non_nullable
as String,listenPort: null == listenPort ? _self.listenPort : listenPort // ignore: cast_nullable_to_non_nullable
as int,targetHost: null == targetHost ? _self.targetHost : targetHost // ignore: cast_nullable_to_non_nullable
as String,targetPort: null == targetPort ? _self.targetPort : targetPort // ignore: cast_nullable_to_non_nullable
as int,multicast: null == multicast ? _self.multicast : multicast // ignore: cast_nullable_to_non_nullable
as String,multicastPort: null == multicastPort ? _self.multicastPort : multicastPort // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,parser: null == parser ? _self.parser : parser // ignore: cast_nullable_to_non_nullable
as String,payload: freezed == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as Uint8List?,
  ));
}


}

// dart format on
