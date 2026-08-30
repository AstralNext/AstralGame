// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bookmark.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Bookmark {

 int get id; String get customName; RoomInvitePayload get payload; String? get originalShortCode; String? get originalOfflineToken; DateTime get savedAt; DateTime? get lastUsedAt; bool get pinned;
/// Create a copy of Bookmark
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BookmarkCopyWith<Bookmark> get copyWith => _$BookmarkCopyWithImpl<Bookmark>(this as Bookmark, _$identity);

  /// Serializes this Bookmark to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Bookmark&&(identical(other.id, id) || other.id == id)&&(identical(other.customName, customName) || other.customName == customName)&&(identical(other.payload, payload) || other.payload == payload)&&(identical(other.originalShortCode, originalShortCode) || other.originalShortCode == originalShortCode)&&(identical(other.originalOfflineToken, originalOfflineToken) || other.originalOfflineToken == originalOfflineToken)&&(identical(other.savedAt, savedAt) || other.savedAt == savedAt)&&(identical(other.lastUsedAt, lastUsedAt) || other.lastUsedAt == lastUsedAt)&&(identical(other.pinned, pinned) || other.pinned == pinned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,customName,payload,originalShortCode,originalOfflineToken,savedAt,lastUsedAt,pinned);

@override
String toString() {
  return 'Bookmark(id: $id, customName: $customName, payload: $payload, originalShortCode: $originalShortCode, originalOfflineToken: $originalOfflineToken, savedAt: $savedAt, lastUsedAt: $lastUsedAt, pinned: $pinned)';
}


}

/// @nodoc
abstract mixin class $BookmarkCopyWith<$Res>  {
  factory $BookmarkCopyWith(Bookmark value, $Res Function(Bookmark) _then) = _$BookmarkCopyWithImpl;
@useResult
$Res call({
 int id, String customName, RoomInvitePayload payload, String? originalShortCode, String? originalOfflineToken, DateTime savedAt, DateTime? lastUsedAt, bool pinned
});


$RoomInvitePayloadCopyWith<$Res> get payload;

}
/// @nodoc
class _$BookmarkCopyWithImpl<$Res>
    implements $BookmarkCopyWith<$Res> {
  _$BookmarkCopyWithImpl(this._self, this._then);

  final Bookmark _self;
  final $Res Function(Bookmark) _then;

/// Create a copy of Bookmark
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? customName = null,Object? payload = null,Object? originalShortCode = freezed,Object? originalOfflineToken = freezed,Object? savedAt = null,Object? lastUsedAt = freezed,Object? pinned = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,customName: null == customName ? _self.customName : customName // ignore: cast_nullable_to_non_nullable
as String,payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as RoomInvitePayload,originalShortCode: freezed == originalShortCode ? _self.originalShortCode : originalShortCode // ignore: cast_nullable_to_non_nullable
as String?,originalOfflineToken: freezed == originalOfflineToken ? _self.originalOfflineToken : originalOfflineToken // ignore: cast_nullable_to_non_nullable
as String?,savedAt: null == savedAt ? _self.savedAt : savedAt // ignore: cast_nullable_to_non_nullable
as DateTime,lastUsedAt: freezed == lastUsedAt ? _self.lastUsedAt : lastUsedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of Bookmark
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoomInvitePayloadCopyWith<$Res> get payload {
  
  return $RoomInvitePayloadCopyWith<$Res>(_self.payload, (value) {
    return _then(_self.copyWith(payload: value));
  });
}
}


/// Adds pattern-matching-related methods to [Bookmark].
extension BookmarkPatterns on Bookmark {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Bookmark value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Bookmark() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Bookmark value)  $default,){
final _that = this;
switch (_that) {
case _Bookmark():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Bookmark value)?  $default,){
final _that = this;
switch (_that) {
case _Bookmark() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String customName,  RoomInvitePayload payload,  String? originalShortCode,  String? originalOfflineToken,  DateTime savedAt,  DateTime? lastUsedAt,  bool pinned)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Bookmark() when $default != null:
return $default(_that.id,_that.customName,_that.payload,_that.originalShortCode,_that.originalOfflineToken,_that.savedAt,_that.lastUsedAt,_that.pinned);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String customName,  RoomInvitePayload payload,  String? originalShortCode,  String? originalOfflineToken,  DateTime savedAt,  DateTime? lastUsedAt,  bool pinned)  $default,) {final _that = this;
switch (_that) {
case _Bookmark():
return $default(_that.id,_that.customName,_that.payload,_that.originalShortCode,_that.originalOfflineToken,_that.savedAt,_that.lastUsedAt,_that.pinned);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String customName,  RoomInvitePayload payload,  String? originalShortCode,  String? originalOfflineToken,  DateTime savedAt,  DateTime? lastUsedAt,  bool pinned)?  $default,) {final _that = this;
switch (_that) {
case _Bookmark() when $default != null:
return $default(_that.id,_that.customName,_that.payload,_that.originalShortCode,_that.originalOfflineToken,_that.savedAt,_that.lastUsedAt,_that.pinned);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true)
class _Bookmark extends Bookmark {
  const _Bookmark({required this.id, required this.customName, required this.payload, this.originalShortCode, this.originalOfflineToken, required this.savedAt, this.lastUsedAt, this.pinned = false}): super._();
  factory _Bookmark.fromJson(Map<String, dynamic> json) => _$BookmarkFromJson(json);

@override final  int id;
@override final  String customName;
@override final  RoomInvitePayload payload;
@override final  String? originalShortCode;
@override final  String? originalOfflineToken;
@override final  DateTime savedAt;
@override final  DateTime? lastUsedAt;
@override@JsonKey() final  bool pinned;

/// Create a copy of Bookmark
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BookmarkCopyWith<_Bookmark> get copyWith => __$BookmarkCopyWithImpl<_Bookmark>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BookmarkToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Bookmark&&(identical(other.id, id) || other.id == id)&&(identical(other.customName, customName) || other.customName == customName)&&(identical(other.payload, payload) || other.payload == payload)&&(identical(other.originalShortCode, originalShortCode) || other.originalShortCode == originalShortCode)&&(identical(other.originalOfflineToken, originalOfflineToken) || other.originalOfflineToken == originalOfflineToken)&&(identical(other.savedAt, savedAt) || other.savedAt == savedAt)&&(identical(other.lastUsedAt, lastUsedAt) || other.lastUsedAt == lastUsedAt)&&(identical(other.pinned, pinned) || other.pinned == pinned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,customName,payload,originalShortCode,originalOfflineToken,savedAt,lastUsedAt,pinned);

@override
String toString() {
  return 'Bookmark(id: $id, customName: $customName, payload: $payload, originalShortCode: $originalShortCode, originalOfflineToken: $originalOfflineToken, savedAt: $savedAt, lastUsedAt: $lastUsedAt, pinned: $pinned)';
}


}

/// @nodoc
abstract mixin class _$BookmarkCopyWith<$Res> implements $BookmarkCopyWith<$Res> {
  factory _$BookmarkCopyWith(_Bookmark value, $Res Function(_Bookmark) _then) = __$BookmarkCopyWithImpl;
@override @useResult
$Res call({
 int id, String customName, RoomInvitePayload payload, String? originalShortCode, String? originalOfflineToken, DateTime savedAt, DateTime? lastUsedAt, bool pinned
});


@override $RoomInvitePayloadCopyWith<$Res> get payload;

}
/// @nodoc
class __$BookmarkCopyWithImpl<$Res>
    implements _$BookmarkCopyWith<$Res> {
  __$BookmarkCopyWithImpl(this._self, this._then);

  final _Bookmark _self;
  final $Res Function(_Bookmark) _then;

/// Create a copy of Bookmark
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? customName = null,Object? payload = null,Object? originalShortCode = freezed,Object? originalOfflineToken = freezed,Object? savedAt = null,Object? lastUsedAt = freezed,Object? pinned = null,}) {
  return _then(_Bookmark(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,customName: null == customName ? _self.customName : customName // ignore: cast_nullable_to_non_nullable
as String,payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as RoomInvitePayload,originalShortCode: freezed == originalShortCode ? _self.originalShortCode : originalShortCode // ignore: cast_nullable_to_non_nullable
as String?,originalOfflineToken: freezed == originalOfflineToken ? _self.originalOfflineToken : originalOfflineToken // ignore: cast_nullable_to_non_nullable
as String?,savedAt: null == savedAt ? _self.savedAt : savedAt // ignore: cast_nullable_to_non_nullable
as DateTime,lastUsedAt: freezed == lastUsedAt ? _self.lastUsedAt : lastUsedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of Bookmark
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoomInvitePayloadCopyWith<$Res> get payload {
  
  return $RoomInvitePayloadCopyWith<$Res>(_self.payload, (value) {
    return _then(_self.copyWith(payload: value));
  });
}
}

// dart format on
