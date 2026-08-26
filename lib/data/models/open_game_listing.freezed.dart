// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'open_game_listing.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$OpenGameListing {

/// 去重键：`peerId:adId`。
 String get key; int get fromPeerId; String get ownerName; String get roomGameId; String get adId; String get label; String get ipv4; int get port; String? get motd; DateTime get expiresAt; bool get isSelf; bool get isRoomHost;
/// Create a copy of OpenGameListing
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OpenGameListingCopyWith<OpenGameListing> get copyWith => _$OpenGameListingCopyWithImpl<OpenGameListing>(this as OpenGameListing, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OpenGameListing&&(identical(other.key, key) || other.key == key)&&(identical(other.fromPeerId, fromPeerId) || other.fromPeerId == fromPeerId)&&(identical(other.ownerName, ownerName) || other.ownerName == ownerName)&&(identical(other.roomGameId, roomGameId) || other.roomGameId == roomGameId)&&(identical(other.adId, adId) || other.adId == adId)&&(identical(other.label, label) || other.label == label)&&(identical(other.ipv4, ipv4) || other.ipv4 == ipv4)&&(identical(other.port, port) || other.port == port)&&(identical(other.motd, motd) || other.motd == motd)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.isSelf, isSelf) || other.isSelf == isSelf)&&(identical(other.isRoomHost, isRoomHost) || other.isRoomHost == isRoomHost));
}


@override
int get hashCode => Object.hash(runtimeType,key,fromPeerId,ownerName,roomGameId,adId,label,ipv4,port,motd,expiresAt,isSelf,isRoomHost);

@override
String toString() {
  return 'OpenGameListing(key: $key, fromPeerId: $fromPeerId, ownerName: $ownerName, roomGameId: $roomGameId, adId: $adId, label: $label, ipv4: $ipv4, port: $port, motd: $motd, expiresAt: $expiresAt, isSelf: $isSelf, isRoomHost: $isRoomHost)';
}


}

/// @nodoc
abstract mixin class $OpenGameListingCopyWith<$Res>  {
  factory $OpenGameListingCopyWith(OpenGameListing value, $Res Function(OpenGameListing) _then) = _$OpenGameListingCopyWithImpl;
@useResult
$Res call({
 String key, int fromPeerId, String ownerName, String roomGameId, String adId, String label, String ipv4, int port, String? motd, DateTime expiresAt, bool isSelf, bool isRoomHost
});




}
/// @nodoc
class _$OpenGameListingCopyWithImpl<$Res>
    implements $OpenGameListingCopyWith<$Res> {
  _$OpenGameListingCopyWithImpl(this._self, this._then);

  final OpenGameListing _self;
  final $Res Function(OpenGameListing) _then;

/// Create a copy of OpenGameListing
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? fromPeerId = null,Object? ownerName = null,Object? roomGameId = null,Object? adId = null,Object? label = null,Object? ipv4 = null,Object? port = null,Object? motd = freezed,Object? expiresAt = null,Object? isSelf = null,Object? isRoomHost = null,}) {
  return _then(_self.copyWith(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,fromPeerId: null == fromPeerId ? _self.fromPeerId : fromPeerId // ignore: cast_nullable_to_non_nullable
as int,ownerName: null == ownerName ? _self.ownerName : ownerName // ignore: cast_nullable_to_non_nullable
as String,roomGameId: null == roomGameId ? _self.roomGameId : roomGameId // ignore: cast_nullable_to_non_nullable
as String,adId: null == adId ? _self.adId : adId // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,ipv4: null == ipv4 ? _self.ipv4 : ipv4 // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,motd: freezed == motd ? _self.motd : motd // ignore: cast_nullable_to_non_nullable
as String?,expiresAt: null == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as DateTime,isSelf: null == isSelf ? _self.isSelf : isSelf // ignore: cast_nullable_to_non_nullable
as bool,isRoomHost: null == isRoomHost ? _self.isRoomHost : isRoomHost // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [OpenGameListing].
extension OpenGameListingPatterns on OpenGameListing {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OpenGameListing value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OpenGameListing() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OpenGameListing value)  $default,){
final _that = this;
switch (_that) {
case _OpenGameListing():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OpenGameListing value)?  $default,){
final _that = this;
switch (_that) {
case _OpenGameListing() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  int fromPeerId,  String ownerName,  String roomGameId,  String adId,  String label,  String ipv4,  int port,  String? motd,  DateTime expiresAt,  bool isSelf,  bool isRoomHost)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OpenGameListing() when $default != null:
return $default(_that.key,_that.fromPeerId,_that.ownerName,_that.roomGameId,_that.adId,_that.label,_that.ipv4,_that.port,_that.motd,_that.expiresAt,_that.isSelf,_that.isRoomHost);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  int fromPeerId,  String ownerName,  String roomGameId,  String adId,  String label,  String ipv4,  int port,  String? motd,  DateTime expiresAt,  bool isSelf,  bool isRoomHost)  $default,) {final _that = this;
switch (_that) {
case _OpenGameListing():
return $default(_that.key,_that.fromPeerId,_that.ownerName,_that.roomGameId,_that.adId,_that.label,_that.ipv4,_that.port,_that.motd,_that.expiresAt,_that.isSelf,_that.isRoomHost);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  int fromPeerId,  String ownerName,  String roomGameId,  String adId,  String label,  String ipv4,  int port,  String? motd,  DateTime expiresAt,  bool isSelf,  bool isRoomHost)?  $default,) {final _that = this;
switch (_that) {
case _OpenGameListing() when $default != null:
return $default(_that.key,_that.fromPeerId,_that.ownerName,_that.roomGameId,_that.adId,_that.label,_that.ipv4,_that.port,_that.motd,_that.expiresAt,_that.isSelf,_that.isRoomHost);case _:
  return null;

}
}

}

/// @nodoc


class _OpenGameListing extends OpenGameListing {
  const _OpenGameListing({required this.key, required this.fromPeerId, required this.ownerName, required this.roomGameId, required this.adId, required this.label, required this.ipv4, required this.port, this.motd, required this.expiresAt, this.isSelf = false, this.isRoomHost = false}): super._();
  

/// 去重键：`peerId:adId`。
@override final  String key;
@override final  int fromPeerId;
@override final  String ownerName;
@override final  String roomGameId;
@override final  String adId;
@override final  String label;
@override final  String ipv4;
@override final  int port;
@override final  String? motd;
@override final  DateTime expiresAt;
@override@JsonKey() final  bool isSelf;
@override@JsonKey() final  bool isRoomHost;

/// Create a copy of OpenGameListing
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OpenGameListingCopyWith<_OpenGameListing> get copyWith => __$OpenGameListingCopyWithImpl<_OpenGameListing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _OpenGameListing&&(identical(other.key, key) || other.key == key)&&(identical(other.fromPeerId, fromPeerId) || other.fromPeerId == fromPeerId)&&(identical(other.ownerName, ownerName) || other.ownerName == ownerName)&&(identical(other.roomGameId, roomGameId) || other.roomGameId == roomGameId)&&(identical(other.adId, adId) || other.adId == adId)&&(identical(other.label, label) || other.label == label)&&(identical(other.ipv4, ipv4) || other.ipv4 == ipv4)&&(identical(other.port, port) || other.port == port)&&(identical(other.motd, motd) || other.motd == motd)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.isSelf, isSelf) || other.isSelf == isSelf)&&(identical(other.isRoomHost, isRoomHost) || other.isRoomHost == isRoomHost));
}


@override
int get hashCode => Object.hash(runtimeType,key,fromPeerId,ownerName,roomGameId,adId,label,ipv4,port,motd,expiresAt,isSelf,isRoomHost);

@override
String toString() {
  return 'OpenGameListing(key: $key, fromPeerId: $fromPeerId, ownerName: $ownerName, roomGameId: $roomGameId, adId: $adId, label: $label, ipv4: $ipv4, port: $port, motd: $motd, expiresAt: $expiresAt, isSelf: $isSelf, isRoomHost: $isRoomHost)';
}


}

/// @nodoc
abstract mixin class _$OpenGameListingCopyWith<$Res> implements $OpenGameListingCopyWith<$Res> {
  factory _$OpenGameListingCopyWith(_OpenGameListing value, $Res Function(_OpenGameListing) _then) = __$OpenGameListingCopyWithImpl;
@override @useResult
$Res call({
 String key, int fromPeerId, String ownerName, String roomGameId, String adId, String label, String ipv4, int port, String? motd, DateTime expiresAt, bool isSelf, bool isRoomHost
});




}
/// @nodoc
class __$OpenGameListingCopyWithImpl<$Res>
    implements _$OpenGameListingCopyWith<$Res> {
  __$OpenGameListingCopyWithImpl(this._self, this._then);

  final _OpenGameListing _self;
  final $Res Function(_OpenGameListing) _then;

/// Create a copy of OpenGameListing
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? fromPeerId = null,Object? ownerName = null,Object? roomGameId = null,Object? adId = null,Object? label = null,Object? ipv4 = null,Object? port = null,Object? motd = freezed,Object? expiresAt = null,Object? isSelf = null,Object? isRoomHost = null,}) {
  return _then(_OpenGameListing(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,fromPeerId: null == fromPeerId ? _self.fromPeerId : fromPeerId // ignore: cast_nullable_to_non_nullable
as int,ownerName: null == ownerName ? _self.ownerName : ownerName // ignore: cast_nullable_to_non_nullable
as String,roomGameId: null == roomGameId ? _self.roomGameId : roomGameId // ignore: cast_nullable_to_non_nullable
as String,adId: null == adId ? _self.adId : adId // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,ipv4: null == ipv4 ? _self.ipv4 : ipv4 // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,motd: freezed == motd ? _self.motd : motd // ignore: cast_nullable_to_non_nullable
as String?,expiresAt: null == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as DateTime,isSelf: null == isSelf ? _self.isSelf : isSelf // ignore: cast_nullable_to_non_nullable
as bool,isRoomHost: null == isRoomHost ? _self.isRoomHost : isRoomHost // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$LocalOpenGameAd {

 GameAssistLanGameDiscoverEntry get entry; String get ipv4; String get roomGameId; int get port; String get label; String? get motd;
/// Create a copy of LocalOpenGameAd
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LocalOpenGameAdCopyWith<LocalOpenGameAd> get copyWith => _$LocalOpenGameAdCopyWithImpl<LocalOpenGameAd>(this as LocalOpenGameAd, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LocalOpenGameAd&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.ipv4, ipv4) || other.ipv4 == ipv4)&&(identical(other.roomGameId, roomGameId) || other.roomGameId == roomGameId)&&(identical(other.port, port) || other.port == port)&&(identical(other.label, label) || other.label == label)&&(identical(other.motd, motd) || other.motd == motd));
}


@override
int get hashCode => Object.hash(runtimeType,entry,ipv4,roomGameId,port,label,motd);

@override
String toString() {
  return 'LocalOpenGameAd(entry: $entry, ipv4: $ipv4, roomGameId: $roomGameId, port: $port, label: $label, motd: $motd)';
}


}

/// @nodoc
abstract mixin class $LocalOpenGameAdCopyWith<$Res>  {
  factory $LocalOpenGameAdCopyWith(LocalOpenGameAd value, $Res Function(LocalOpenGameAd) _then) = _$LocalOpenGameAdCopyWithImpl;
@useResult
$Res call({
 GameAssistLanGameDiscoverEntry entry, String ipv4, String roomGameId, int port, String label, String? motd
});


$GameAssistLanGameDiscoverEntryCopyWith<$Res> get entry;

}
/// @nodoc
class _$LocalOpenGameAdCopyWithImpl<$Res>
    implements $LocalOpenGameAdCopyWith<$Res> {
  _$LocalOpenGameAdCopyWithImpl(this._self, this._then);

  final LocalOpenGameAd _self;
  final $Res Function(LocalOpenGameAd) _then;

/// Create a copy of LocalOpenGameAd
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? ipv4 = null,Object? roomGameId = null,Object? port = null,Object? label = null,Object? motd = freezed,}) {
  return _then(_self.copyWith(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as GameAssistLanGameDiscoverEntry,ipv4: null == ipv4 ? _self.ipv4 : ipv4 // ignore: cast_nullable_to_non_nullable
as String,roomGameId: null == roomGameId ? _self.roomGameId : roomGameId // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,motd: freezed == motd ? _self.motd : motd // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of LocalOpenGameAd
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameAssistLanGameDiscoverEntryCopyWith<$Res> get entry {
  
  return $GameAssistLanGameDiscoverEntryCopyWith<$Res>(_self.entry, (value) {
    return _then(_self.copyWith(entry: value));
  });
}
}


/// Adds pattern-matching-related methods to [LocalOpenGameAd].
extension LocalOpenGameAdPatterns on LocalOpenGameAd {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LocalOpenGameAd value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LocalOpenGameAd() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LocalOpenGameAd value)  $default,){
final _that = this;
switch (_that) {
case _LocalOpenGameAd():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LocalOpenGameAd value)?  $default,){
final _that = this;
switch (_that) {
case _LocalOpenGameAd() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( GameAssistLanGameDiscoverEntry entry,  String ipv4,  String roomGameId,  int port,  String label,  String? motd)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LocalOpenGameAd() when $default != null:
return $default(_that.entry,_that.ipv4,_that.roomGameId,_that.port,_that.label,_that.motd);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( GameAssistLanGameDiscoverEntry entry,  String ipv4,  String roomGameId,  int port,  String label,  String? motd)  $default,) {final _that = this;
switch (_that) {
case _LocalOpenGameAd():
return $default(_that.entry,_that.ipv4,_that.roomGameId,_that.port,_that.label,_that.motd);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( GameAssistLanGameDiscoverEntry entry,  String ipv4,  String roomGameId,  int port,  String label,  String? motd)?  $default,) {final _that = this;
switch (_that) {
case _LocalOpenGameAd() when $default != null:
return $default(_that.entry,_that.ipv4,_that.roomGameId,_that.port,_that.label,_that.motd);case _:
  return null;

}
}

}

/// @nodoc


class _LocalOpenGameAd implements LocalOpenGameAd {
  const _LocalOpenGameAd({required this.entry, required this.ipv4, required this.roomGameId, required this.port, required this.label, this.motd});
  

@override final  GameAssistLanGameDiscoverEntry entry;
@override final  String ipv4;
@override final  String roomGameId;
@override final  int port;
@override final  String label;
@override final  String? motd;

/// Create a copy of LocalOpenGameAd
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LocalOpenGameAdCopyWith<_LocalOpenGameAd> get copyWith => __$LocalOpenGameAdCopyWithImpl<_LocalOpenGameAd>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LocalOpenGameAd&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.ipv4, ipv4) || other.ipv4 == ipv4)&&(identical(other.roomGameId, roomGameId) || other.roomGameId == roomGameId)&&(identical(other.port, port) || other.port == port)&&(identical(other.label, label) || other.label == label)&&(identical(other.motd, motd) || other.motd == motd));
}


@override
int get hashCode => Object.hash(runtimeType,entry,ipv4,roomGameId,port,label,motd);

@override
String toString() {
  return 'LocalOpenGameAd(entry: $entry, ipv4: $ipv4, roomGameId: $roomGameId, port: $port, label: $label, motd: $motd)';
}


}

/// @nodoc
abstract mixin class _$LocalOpenGameAdCopyWith<$Res> implements $LocalOpenGameAdCopyWith<$Res> {
  factory _$LocalOpenGameAdCopyWith(_LocalOpenGameAd value, $Res Function(_LocalOpenGameAd) _then) = __$LocalOpenGameAdCopyWithImpl;
@override @useResult
$Res call({
 GameAssistLanGameDiscoverEntry entry, String ipv4, String roomGameId, int port, String label, String? motd
});


@override $GameAssistLanGameDiscoverEntryCopyWith<$Res> get entry;

}
/// @nodoc
class __$LocalOpenGameAdCopyWithImpl<$Res>
    implements _$LocalOpenGameAdCopyWith<$Res> {
  __$LocalOpenGameAdCopyWithImpl(this._self, this._then);

  final _LocalOpenGameAd _self;
  final $Res Function(_LocalOpenGameAd) _then;

/// Create a copy of LocalOpenGameAd
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? ipv4 = null,Object? roomGameId = null,Object? port = null,Object? label = null,Object? motd = freezed,}) {
  return _then(_LocalOpenGameAd(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as GameAssistLanGameDiscoverEntry,ipv4: null == ipv4 ? _self.ipv4 : ipv4 // ignore: cast_nullable_to_non_nullable
as String,roomGameId: null == roomGameId ? _self.roomGameId : roomGameId // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,motd: freezed == motd ? _self.motd : motd // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of LocalOpenGameAd
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameAssistLanGameDiscoverEntryCopyWith<$Res> get entry {
  
  return $GameAssistLanGameDiscoverEntryCopyWith<$Res>(_self.entry, (value) {
    return _then(_self.copyWith(entry: value));
  });
}
}

// dart format on
