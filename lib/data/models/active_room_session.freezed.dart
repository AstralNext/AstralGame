// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'active_room_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RoomInvitePayload {

 int get v;@JsonKey(name: 'game_id') String get gameId;@JsonKey(name: 'game_name') String get gameName;@JsonKey(name: 'network_name') String get networkName;@JsonKey(name: 'network_secret') String get networkSecret; List<PeerEndpoint> get peers;@JsonKey(name: 'display_name') String? get displayName;
/// Create a copy of RoomInvitePayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomInvitePayloadCopyWith<RoomInvitePayload> get copyWith => _$RoomInvitePayloadCopyWithImpl<RoomInvitePayload>(this as RoomInvitePayload, _$identity);

  /// Serializes this RoomInvitePayload to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomInvitePayload&&(identical(other.v, v) || other.v == v)&&(identical(other.gameId, gameId) || other.gameId == gameId)&&(identical(other.gameName, gameName) || other.gameName == gameName)&&(identical(other.networkName, networkName) || other.networkName == networkName)&&(identical(other.networkSecret, networkSecret) || other.networkSecret == networkSecret)&&const DeepCollectionEquality().equals(other.peers, peers)&&(identical(other.displayName, displayName) || other.displayName == displayName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,v,gameId,gameName,networkName,networkSecret,const DeepCollectionEquality().hash(peers),displayName);

@override
String toString() {
  return 'RoomInvitePayload(v: $v, gameId: $gameId, gameName: $gameName, networkName: $networkName, networkSecret: $networkSecret, peers: $peers, displayName: $displayName)';
}


}

/// @nodoc
abstract mixin class $RoomInvitePayloadCopyWith<$Res>  {
  factory $RoomInvitePayloadCopyWith(RoomInvitePayload value, $Res Function(RoomInvitePayload) _then) = _$RoomInvitePayloadCopyWithImpl;
@useResult
$Res call({
 int v,@JsonKey(name: 'game_id') String gameId,@JsonKey(name: 'game_name') String gameName,@JsonKey(name: 'network_name') String networkName,@JsonKey(name: 'network_secret') String networkSecret, List<PeerEndpoint> peers,@JsonKey(name: 'display_name') String? displayName
});




}
/// @nodoc
class _$RoomInvitePayloadCopyWithImpl<$Res>
    implements $RoomInvitePayloadCopyWith<$Res> {
  _$RoomInvitePayloadCopyWithImpl(this._self, this._then);

  final RoomInvitePayload _self;
  final $Res Function(RoomInvitePayload) _then;

/// Create a copy of RoomInvitePayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? v = null,Object? gameId = null,Object? gameName = null,Object? networkName = null,Object? networkSecret = null,Object? peers = null,Object? displayName = freezed,}) {
  return _then(_self.copyWith(
v: null == v ? _self.v : v // ignore: cast_nullable_to_non_nullable
as int,gameId: null == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String,gameName: null == gameName ? _self.gameName : gameName // ignore: cast_nullable_to_non_nullable
as String,networkName: null == networkName ? _self.networkName : networkName // ignore: cast_nullable_to_non_nullable
as String,networkSecret: null == networkSecret ? _self.networkSecret : networkSecret // ignore: cast_nullable_to_non_nullable
as String,peers: null == peers ? _self.peers : peers // ignore: cast_nullable_to_non_nullable
as List<PeerEndpoint>,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [RoomInvitePayload].
extension RoomInvitePayloadPatterns on RoomInvitePayload {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoomInvitePayload value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoomInvitePayload() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoomInvitePayload value)  $default,){
final _that = this;
switch (_that) {
case _RoomInvitePayload():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoomInvitePayload value)?  $default,){
final _that = this;
switch (_that) {
case _RoomInvitePayload() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int v, @JsonKey(name: 'game_id')  String gameId, @JsonKey(name: 'game_name')  String gameName, @JsonKey(name: 'network_name')  String networkName, @JsonKey(name: 'network_secret')  String networkSecret,  List<PeerEndpoint> peers, @JsonKey(name: 'display_name')  String? displayName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoomInvitePayload() when $default != null:
return $default(_that.v,_that.gameId,_that.gameName,_that.networkName,_that.networkSecret,_that.peers,_that.displayName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int v, @JsonKey(name: 'game_id')  String gameId, @JsonKey(name: 'game_name')  String gameName, @JsonKey(name: 'network_name')  String networkName, @JsonKey(name: 'network_secret')  String networkSecret,  List<PeerEndpoint> peers, @JsonKey(name: 'display_name')  String? displayName)  $default,) {final _that = this;
switch (_that) {
case _RoomInvitePayload():
return $default(_that.v,_that.gameId,_that.gameName,_that.networkName,_that.networkSecret,_that.peers,_that.displayName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int v, @JsonKey(name: 'game_id')  String gameId, @JsonKey(name: 'game_name')  String gameName, @JsonKey(name: 'network_name')  String networkName, @JsonKey(name: 'network_secret')  String networkSecret,  List<PeerEndpoint> peers, @JsonKey(name: 'display_name')  String? displayName)?  $default,) {final _that = this;
switch (_that) {
case _RoomInvitePayload() when $default != null:
return $default(_that.v,_that.gameId,_that.gameName,_that.networkName,_that.networkSecret,_that.peers,_that.displayName);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true)
class _RoomInvitePayload extends RoomInvitePayload {
  const _RoomInvitePayload({this.v = 1, @JsonKey(name: 'game_id') required this.gameId, @JsonKey(name: 'game_name') required this.gameName, @JsonKey(name: 'network_name') required this.networkName, @JsonKey(name: 'network_secret') required this.networkSecret, required final  List<PeerEndpoint> peers, @JsonKey(name: 'display_name') this.displayName}): _peers = peers,super._();
  factory _RoomInvitePayload.fromJson(Map<String, dynamic> json) => _$RoomInvitePayloadFromJson(json);

@override@JsonKey() final  int v;
@override@JsonKey(name: 'game_id') final  String gameId;
@override@JsonKey(name: 'game_name') final  String gameName;
@override@JsonKey(name: 'network_name') final  String networkName;
@override@JsonKey(name: 'network_secret') final  String networkSecret;
 final  List<PeerEndpoint> _peers;
@override List<PeerEndpoint> get peers {
  if (_peers is EqualUnmodifiableListView) return _peers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_peers);
}

@override@JsonKey(name: 'display_name') final  String? displayName;

/// Create a copy of RoomInvitePayload
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomInvitePayloadCopyWith<_RoomInvitePayload> get copyWith => __$RoomInvitePayloadCopyWithImpl<_RoomInvitePayload>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoomInvitePayloadToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoomInvitePayload&&(identical(other.v, v) || other.v == v)&&(identical(other.gameId, gameId) || other.gameId == gameId)&&(identical(other.gameName, gameName) || other.gameName == gameName)&&(identical(other.networkName, networkName) || other.networkName == networkName)&&(identical(other.networkSecret, networkSecret) || other.networkSecret == networkSecret)&&const DeepCollectionEquality().equals(other._peers, _peers)&&(identical(other.displayName, displayName) || other.displayName == displayName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,v,gameId,gameName,networkName,networkSecret,const DeepCollectionEquality().hash(_peers),displayName);

@override
String toString() {
  return 'RoomInvitePayload(v: $v, gameId: $gameId, gameName: $gameName, networkName: $networkName, networkSecret: $networkSecret, peers: $peers, displayName: $displayName)';
}


}

/// @nodoc
abstract mixin class _$RoomInvitePayloadCopyWith<$Res> implements $RoomInvitePayloadCopyWith<$Res> {
  factory _$RoomInvitePayloadCopyWith(_RoomInvitePayload value, $Res Function(_RoomInvitePayload) _then) = __$RoomInvitePayloadCopyWithImpl;
@override @useResult
$Res call({
 int v,@JsonKey(name: 'game_id') String gameId,@JsonKey(name: 'game_name') String gameName,@JsonKey(name: 'network_name') String networkName,@JsonKey(name: 'network_secret') String networkSecret, List<PeerEndpoint> peers,@JsonKey(name: 'display_name') String? displayName
});




}
/// @nodoc
class __$RoomInvitePayloadCopyWithImpl<$Res>
    implements _$RoomInvitePayloadCopyWith<$Res> {
  __$RoomInvitePayloadCopyWithImpl(this._self, this._then);

  final _RoomInvitePayload _self;
  final $Res Function(_RoomInvitePayload) _then;

/// Create a copy of RoomInvitePayload
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? v = null,Object? gameId = null,Object? gameName = null,Object? networkName = null,Object? networkSecret = null,Object? peers = null,Object? displayName = freezed,}) {
  return _then(_RoomInvitePayload(
v: null == v ? _self.v : v // ignore: cast_nullable_to_non_nullable
as int,gameId: null == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String,gameName: null == gameName ? _self.gameName : gameName // ignore: cast_nullable_to_non_nullable
as String,networkName: null == networkName ? _self.networkName : networkName // ignore: cast_nullable_to_non_nullable
as String,networkSecret: null == networkSecret ? _self.networkSecret : networkSecret // ignore: cast_nullable_to_non_nullable
as String,peers: null == peers ? _self._peers : peers // ignore: cast_nullable_to_non_nullable
as List<PeerEndpoint>,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$HostResumeSnapshot {

 String get gameId; String get gameName; String get networkName; String get networkSecret; String get displayName;
/// Create a copy of HostResumeSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HostResumeSnapshotCopyWith<HostResumeSnapshot> get copyWith => _$HostResumeSnapshotCopyWithImpl<HostResumeSnapshot>(this as HostResumeSnapshot, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HostResumeSnapshot&&(identical(other.gameId, gameId) || other.gameId == gameId)&&(identical(other.gameName, gameName) || other.gameName == gameName)&&(identical(other.networkName, networkName) || other.networkName == networkName)&&(identical(other.networkSecret, networkSecret) || other.networkSecret == networkSecret)&&(identical(other.displayName, displayName) || other.displayName == displayName));
}


@override
int get hashCode => Object.hash(runtimeType,gameId,gameName,networkName,networkSecret,displayName);

@override
String toString() {
  return 'HostResumeSnapshot(gameId: $gameId, gameName: $gameName, networkName: $networkName, networkSecret: $networkSecret, displayName: $displayName)';
}


}

/// @nodoc
abstract mixin class $HostResumeSnapshotCopyWith<$Res>  {
  factory $HostResumeSnapshotCopyWith(HostResumeSnapshot value, $Res Function(HostResumeSnapshot) _then) = _$HostResumeSnapshotCopyWithImpl;
@useResult
$Res call({
 String gameId, String gameName, String networkName, String networkSecret, String displayName
});




}
/// @nodoc
class _$HostResumeSnapshotCopyWithImpl<$Res>
    implements $HostResumeSnapshotCopyWith<$Res> {
  _$HostResumeSnapshotCopyWithImpl(this._self, this._then);

  final HostResumeSnapshot _self;
  final $Res Function(HostResumeSnapshot) _then;

/// Create a copy of HostResumeSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? gameId = null,Object? gameName = null,Object? networkName = null,Object? networkSecret = null,Object? displayName = null,}) {
  return _then(_self.copyWith(
gameId: null == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String,gameName: null == gameName ? _self.gameName : gameName // ignore: cast_nullable_to_non_nullable
as String,networkName: null == networkName ? _self.networkName : networkName // ignore: cast_nullable_to_non_nullable
as String,networkSecret: null == networkSecret ? _self.networkSecret : networkSecret // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [HostResumeSnapshot].
extension HostResumeSnapshotPatterns on HostResumeSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HostResumeSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HostResumeSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HostResumeSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _HostResumeSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HostResumeSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _HostResumeSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String gameId,  String gameName,  String networkName,  String networkSecret,  String displayName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HostResumeSnapshot() when $default != null:
return $default(_that.gameId,_that.gameName,_that.networkName,_that.networkSecret,_that.displayName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String gameId,  String gameName,  String networkName,  String networkSecret,  String displayName)  $default,) {final _that = this;
switch (_that) {
case _HostResumeSnapshot():
return $default(_that.gameId,_that.gameName,_that.networkName,_that.networkSecret,_that.displayName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String gameId,  String gameName,  String networkName,  String networkSecret,  String displayName)?  $default,) {final _that = this;
switch (_that) {
case _HostResumeSnapshot() when $default != null:
return $default(_that.gameId,_that.gameName,_that.networkName,_that.networkSecret,_that.displayName);case _:
  return null;

}
}

}

/// @nodoc


class _HostResumeSnapshot implements HostResumeSnapshot {
  const _HostResumeSnapshot({required this.gameId, required this.gameName, required this.networkName, required this.networkSecret, required this.displayName});
  

@override final  String gameId;
@override final  String gameName;
@override final  String networkName;
@override final  String networkSecret;
@override final  String displayName;

/// Create a copy of HostResumeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HostResumeSnapshotCopyWith<_HostResumeSnapshot> get copyWith => __$HostResumeSnapshotCopyWithImpl<_HostResumeSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HostResumeSnapshot&&(identical(other.gameId, gameId) || other.gameId == gameId)&&(identical(other.gameName, gameName) || other.gameName == gameName)&&(identical(other.networkName, networkName) || other.networkName == networkName)&&(identical(other.networkSecret, networkSecret) || other.networkSecret == networkSecret)&&(identical(other.displayName, displayName) || other.displayName == displayName));
}


@override
int get hashCode => Object.hash(runtimeType,gameId,gameName,networkName,networkSecret,displayName);

@override
String toString() {
  return 'HostResumeSnapshot(gameId: $gameId, gameName: $gameName, networkName: $networkName, networkSecret: $networkSecret, displayName: $displayName)';
}


}

/// @nodoc
abstract mixin class _$HostResumeSnapshotCopyWith<$Res> implements $HostResumeSnapshotCopyWith<$Res> {
  factory _$HostResumeSnapshotCopyWith(_HostResumeSnapshot value, $Res Function(_HostResumeSnapshot) _then) = __$HostResumeSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String gameId, String gameName, String networkName, String networkSecret, String displayName
});




}
/// @nodoc
class __$HostResumeSnapshotCopyWithImpl<$Res>
    implements _$HostResumeSnapshotCopyWith<$Res> {
  __$HostResumeSnapshotCopyWithImpl(this._self, this._then);

  final _HostResumeSnapshot _self;
  final $Res Function(_HostResumeSnapshot) _then;

/// Create a copy of HostResumeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? gameId = null,Object? gameName = null,Object? networkName = null,Object? networkSecret = null,Object? displayName = null,}) {
  return _then(_HostResumeSnapshot(
gameId: null == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String,gameName: null == gameName ? _self.gameName : gameName // ignore: cast_nullable_to_non_nullable
as String,networkName: null == networkName ? _self.networkName : networkName // ignore: cast_nullable_to_non_nullable
as String,networkSecret: null == networkSecret ? _self.networkSecret : networkSecret // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ActiveRoomSession {

 bool get isHost; String get gameId; String get gameName; String get networkName; String get networkSecret; String get displayName; String? get shortCode; String? get adminToken;
/// Create a copy of ActiveRoomSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActiveRoomSessionCopyWith<ActiveRoomSession> get copyWith => _$ActiveRoomSessionCopyWithImpl<ActiveRoomSession>(this as ActiveRoomSession, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActiveRoomSession&&(identical(other.isHost, isHost) || other.isHost == isHost)&&(identical(other.gameId, gameId) || other.gameId == gameId)&&(identical(other.gameName, gameName) || other.gameName == gameName)&&(identical(other.networkName, networkName) || other.networkName == networkName)&&(identical(other.networkSecret, networkSecret) || other.networkSecret == networkSecret)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.shortCode, shortCode) || other.shortCode == shortCode)&&(identical(other.adminToken, adminToken) || other.adminToken == adminToken));
}


@override
int get hashCode => Object.hash(runtimeType,isHost,gameId,gameName,networkName,networkSecret,displayName,shortCode,adminToken);

@override
String toString() {
  return 'ActiveRoomSession(isHost: $isHost, gameId: $gameId, gameName: $gameName, networkName: $networkName, networkSecret: $networkSecret, displayName: $displayName, shortCode: $shortCode, adminToken: $adminToken)';
}


}

/// @nodoc
abstract mixin class $ActiveRoomSessionCopyWith<$Res>  {
  factory $ActiveRoomSessionCopyWith(ActiveRoomSession value, $Res Function(ActiveRoomSession) _then) = _$ActiveRoomSessionCopyWithImpl;
@useResult
$Res call({
 bool isHost, String gameId, String gameName, String networkName, String networkSecret, String displayName, String? shortCode, String? adminToken
});




}
/// @nodoc
class _$ActiveRoomSessionCopyWithImpl<$Res>
    implements $ActiveRoomSessionCopyWith<$Res> {
  _$ActiveRoomSessionCopyWithImpl(this._self, this._then);

  final ActiveRoomSession _self;
  final $Res Function(ActiveRoomSession) _then;

/// Create a copy of ActiveRoomSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? isHost = null,Object? gameId = null,Object? gameName = null,Object? networkName = null,Object? networkSecret = null,Object? displayName = null,Object? shortCode = freezed,Object? adminToken = freezed,}) {
  return _then(_self.copyWith(
isHost: null == isHost ? _self.isHost : isHost // ignore: cast_nullable_to_non_nullable
as bool,gameId: null == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String,gameName: null == gameName ? _self.gameName : gameName // ignore: cast_nullable_to_non_nullable
as String,networkName: null == networkName ? _self.networkName : networkName // ignore: cast_nullable_to_non_nullable
as String,networkSecret: null == networkSecret ? _self.networkSecret : networkSecret // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,shortCode: freezed == shortCode ? _self.shortCode : shortCode // ignore: cast_nullable_to_non_nullable
as String?,adminToken: freezed == adminToken ? _self.adminToken : adminToken // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ActiveRoomSession].
extension ActiveRoomSessionPatterns on ActiveRoomSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActiveRoomSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActiveRoomSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActiveRoomSession value)  $default,){
final _that = this;
switch (_that) {
case _ActiveRoomSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActiveRoomSession value)?  $default,){
final _that = this;
switch (_that) {
case _ActiveRoomSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool isHost,  String gameId,  String gameName,  String networkName,  String networkSecret,  String displayName,  String? shortCode,  String? adminToken)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActiveRoomSession() when $default != null:
return $default(_that.isHost,_that.gameId,_that.gameName,_that.networkName,_that.networkSecret,_that.displayName,_that.shortCode,_that.adminToken);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool isHost,  String gameId,  String gameName,  String networkName,  String networkSecret,  String displayName,  String? shortCode,  String? adminToken)  $default,) {final _that = this;
switch (_that) {
case _ActiveRoomSession():
return $default(_that.isHost,_that.gameId,_that.gameName,_that.networkName,_that.networkSecret,_that.displayName,_that.shortCode,_that.adminToken);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool isHost,  String gameId,  String gameName,  String networkName,  String networkSecret,  String displayName,  String? shortCode,  String? adminToken)?  $default,) {final _that = this;
switch (_that) {
case _ActiveRoomSession() when $default != null:
return $default(_that.isHost,_that.gameId,_that.gameName,_that.networkName,_that.networkSecret,_that.displayName,_that.shortCode,_that.adminToken);case _:
  return null;

}
}

}

/// @nodoc


class _ActiveRoomSession extends ActiveRoomSession {
  const _ActiveRoomSession({required this.isHost, required this.gameId, required this.gameName, required this.networkName, required this.networkSecret, required this.displayName, this.shortCode, this.adminToken}): super._();
  

@override final  bool isHost;
@override final  String gameId;
@override final  String gameName;
@override final  String networkName;
@override final  String networkSecret;
@override final  String displayName;
@override final  String? shortCode;
@override final  String? adminToken;

/// Create a copy of ActiveRoomSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActiveRoomSessionCopyWith<_ActiveRoomSession> get copyWith => __$ActiveRoomSessionCopyWithImpl<_ActiveRoomSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActiveRoomSession&&(identical(other.isHost, isHost) || other.isHost == isHost)&&(identical(other.gameId, gameId) || other.gameId == gameId)&&(identical(other.gameName, gameName) || other.gameName == gameName)&&(identical(other.networkName, networkName) || other.networkName == networkName)&&(identical(other.networkSecret, networkSecret) || other.networkSecret == networkSecret)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.shortCode, shortCode) || other.shortCode == shortCode)&&(identical(other.adminToken, adminToken) || other.adminToken == adminToken));
}


@override
int get hashCode => Object.hash(runtimeType,isHost,gameId,gameName,networkName,networkSecret,displayName,shortCode,adminToken);

@override
String toString() {
  return 'ActiveRoomSession(isHost: $isHost, gameId: $gameId, gameName: $gameName, networkName: $networkName, networkSecret: $networkSecret, displayName: $displayName, shortCode: $shortCode, adminToken: $adminToken)';
}


}

/// @nodoc
abstract mixin class _$ActiveRoomSessionCopyWith<$Res> implements $ActiveRoomSessionCopyWith<$Res> {
  factory _$ActiveRoomSessionCopyWith(_ActiveRoomSession value, $Res Function(_ActiveRoomSession) _then) = __$ActiveRoomSessionCopyWithImpl;
@override @useResult
$Res call({
 bool isHost, String gameId, String gameName, String networkName, String networkSecret, String displayName, String? shortCode, String? adminToken
});




}
/// @nodoc
class __$ActiveRoomSessionCopyWithImpl<$Res>
    implements _$ActiveRoomSessionCopyWith<$Res> {
  __$ActiveRoomSessionCopyWithImpl(this._self, this._then);

  final _ActiveRoomSession _self;
  final $Res Function(_ActiveRoomSession) _then;

/// Create a copy of ActiveRoomSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? isHost = null,Object? gameId = null,Object? gameName = null,Object? networkName = null,Object? networkSecret = null,Object? displayName = null,Object? shortCode = freezed,Object? adminToken = freezed,}) {
  return _then(_ActiveRoomSession(
isHost: null == isHost ? _self.isHost : isHost // ignore: cast_nullable_to_non_nullable
as bool,gameId: null == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String,gameName: null == gameName ? _self.gameName : gameName // ignore: cast_nullable_to_non_nullable
as String,networkName: null == networkName ? _self.networkName : networkName // ignore: cast_nullable_to_non_nullable
as String,networkSecret: null == networkSecret ? _self.networkSecret : networkSecret // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,shortCode: freezed == shortCode ? _self.shortCode : shortCode // ignore: cast_nullable_to_non_nullable
as String?,adminToken: freezed == adminToken ? _self.adminToken : adminToken // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
