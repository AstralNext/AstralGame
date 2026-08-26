// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'game_assist_rules.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GameAssistRulesCatalog {

 int get version;/// 有序列表（按 JSON 中 `sort`）。
 List<GameAssistGameRules> get games;
/// Create a copy of GameAssistRulesCatalog
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameAssistRulesCatalogCopyWith<GameAssistRulesCatalog> get copyWith => _$GameAssistRulesCatalogCopyWithImpl<GameAssistRulesCatalog>(this as GameAssistRulesCatalog, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameAssistRulesCatalog&&(identical(other.version, version) || other.version == version)&&const DeepCollectionEquality().equals(other.games, games));
}


@override
int get hashCode => Object.hash(runtimeType,version,const DeepCollectionEquality().hash(games));

@override
String toString() {
  return 'GameAssistRulesCatalog(version: $version, games: $games)';
}


}

/// @nodoc
abstract mixin class $GameAssistRulesCatalogCopyWith<$Res>  {
  factory $GameAssistRulesCatalogCopyWith(GameAssistRulesCatalog value, $Res Function(GameAssistRulesCatalog) _then) = _$GameAssistRulesCatalogCopyWithImpl;
@useResult
$Res call({
 int version, List<GameAssistGameRules> games
});




}
/// @nodoc
class _$GameAssistRulesCatalogCopyWithImpl<$Res>
    implements $GameAssistRulesCatalogCopyWith<$Res> {
  _$GameAssistRulesCatalogCopyWithImpl(this._self, this._then);

  final GameAssistRulesCatalog _self;
  final $Res Function(GameAssistRulesCatalog) _then;

/// Create a copy of GameAssistRulesCatalog
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? games = null,}) {
  return _then(_self.copyWith(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,games: null == games ? _self.games : games // ignore: cast_nullable_to_non_nullable
as List<GameAssistGameRules>,
  ));
}

}


/// Adds pattern-matching-related methods to [GameAssistRulesCatalog].
extension GameAssistRulesCatalogPatterns on GameAssistRulesCatalog {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameAssistRulesCatalog value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameAssistRulesCatalog() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameAssistRulesCatalog value)  $default,){
final _that = this;
switch (_that) {
case _GameAssistRulesCatalog():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameAssistRulesCatalog value)?  $default,){
final _that = this;
switch (_that) {
case _GameAssistRulesCatalog() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int version,  List<GameAssistGameRules> games)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameAssistRulesCatalog() when $default != null:
return $default(_that.version,_that.games);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int version,  List<GameAssistGameRules> games)  $default,) {final _that = this;
switch (_that) {
case _GameAssistRulesCatalog():
return $default(_that.version,_that.games);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int version,  List<GameAssistGameRules> games)?  $default,) {final _that = this;
switch (_that) {
case _GameAssistRulesCatalog() when $default != null:
return $default(_that.version,_that.games);case _:
  return null;

}
}

}

/// @nodoc


class _GameAssistRulesCatalog extends GameAssistRulesCatalog {
  const _GameAssistRulesCatalog({required this.version, required final  List<GameAssistGameRules> games}): _games = games,super._();
  

@override final  int version;
/// 有序列表（按 JSON 中 `sort`）。
 final  List<GameAssistGameRules> _games;
/// 有序列表（按 JSON 中 `sort`）。
@override List<GameAssistGameRules> get games {
  if (_games is EqualUnmodifiableListView) return _games;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_games);
}


/// Create a copy of GameAssistRulesCatalog
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameAssistRulesCatalogCopyWith<_GameAssistRulesCatalog> get copyWith => __$GameAssistRulesCatalogCopyWithImpl<_GameAssistRulesCatalog>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameAssistRulesCatalog&&(identical(other.version, version) || other.version == version)&&const DeepCollectionEquality().equals(other._games, _games));
}


@override
int get hashCode => Object.hash(runtimeType,version,const DeepCollectionEquality().hash(_games));

@override
String toString() {
  return 'GameAssistRulesCatalog(version: $version, games: $games)';
}


}

/// @nodoc
abstract mixin class _$GameAssistRulesCatalogCopyWith<$Res> implements $GameAssistRulesCatalogCopyWith<$Res> {
  factory _$GameAssistRulesCatalogCopyWith(_GameAssistRulesCatalog value, $Res Function(_GameAssistRulesCatalog) _then) = __$GameAssistRulesCatalogCopyWithImpl;
@override @useResult
$Res call({
 int version, List<GameAssistGameRules> games
});




}
/// @nodoc
class __$GameAssistRulesCatalogCopyWithImpl<$Res>
    implements _$GameAssistRulesCatalogCopyWith<$Res> {
  __$GameAssistRulesCatalogCopyWithImpl(this._self, this._then);

  final _GameAssistRulesCatalog _self;
  final $Res Function(_GameAssistRulesCatalog) _then;

/// Create a copy of GameAssistRulesCatalog
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? games = null,}) {
  return _then(_GameAssistRulesCatalog(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,games: null == games ? _self._games : games // ignore: cast_nullable_to_non_nullable
as List<GameAssistGameRules>,
  ));
}


}

/// @nodoc
mixin _$GameAssistGameRules {

 String get id; String get name;/// `#RRGGBB` 或 `#AARRGGBB`。
 String get colorHex;/// Material Icons 名称，如 `terrain`。
 String get iconName; Map<String, GameAssistPlatformRules> get platforms; int? get steamAppId; int? get sgdbGameId; String? get iconAsset; String? get gridAsset; bool get showInPicker; int get sort;/// 选择器里标题下方的短说明。
 String get description;/// 中文名；有则 UI 优先显示。
 String get nameZh;
/// Create a copy of GameAssistGameRules
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameAssistGameRulesCopyWith<GameAssistGameRules> get copyWith => _$GameAssistGameRulesCopyWithImpl<GameAssistGameRules>(this as GameAssistGameRules, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameAssistGameRules&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.colorHex, colorHex) || other.colorHex == colorHex)&&(identical(other.iconName, iconName) || other.iconName == iconName)&&const DeepCollectionEquality().equals(other.platforms, platforms)&&(identical(other.steamAppId, steamAppId) || other.steamAppId == steamAppId)&&(identical(other.sgdbGameId, sgdbGameId) || other.sgdbGameId == sgdbGameId)&&(identical(other.iconAsset, iconAsset) || other.iconAsset == iconAsset)&&(identical(other.gridAsset, gridAsset) || other.gridAsset == gridAsset)&&(identical(other.showInPicker, showInPicker) || other.showInPicker == showInPicker)&&(identical(other.sort, sort) || other.sort == sort)&&(identical(other.description, description) || other.description == description)&&(identical(other.nameZh, nameZh) || other.nameZh == nameZh));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,colorHex,iconName,const DeepCollectionEquality().hash(platforms),steamAppId,sgdbGameId,iconAsset,gridAsset,showInPicker,sort,description,nameZh);

@override
String toString() {
  return 'GameAssistGameRules(id: $id, name: $name, colorHex: $colorHex, iconName: $iconName, platforms: $platforms, steamAppId: $steamAppId, sgdbGameId: $sgdbGameId, iconAsset: $iconAsset, gridAsset: $gridAsset, showInPicker: $showInPicker, sort: $sort, description: $description, nameZh: $nameZh)';
}


}

/// @nodoc
abstract mixin class $GameAssistGameRulesCopyWith<$Res>  {
  factory $GameAssistGameRulesCopyWith(GameAssistGameRules value, $Res Function(GameAssistGameRules) _then) = _$GameAssistGameRulesCopyWithImpl;
@useResult
$Res call({
 String id, String name, String colorHex, String iconName, Map<String, GameAssistPlatformRules> platforms, int? steamAppId, int? sgdbGameId, String? iconAsset, String? gridAsset, bool showInPicker, int sort, String description, String nameZh
});




}
/// @nodoc
class _$GameAssistGameRulesCopyWithImpl<$Res>
    implements $GameAssistGameRulesCopyWith<$Res> {
  _$GameAssistGameRulesCopyWithImpl(this._self, this._then);

  final GameAssistGameRules _self;
  final $Res Function(GameAssistGameRules) _then;

/// Create a copy of GameAssistGameRules
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? colorHex = null,Object? iconName = null,Object? platforms = null,Object? steamAppId = freezed,Object? sgdbGameId = freezed,Object? iconAsset = freezed,Object? gridAsset = freezed,Object? showInPicker = null,Object? sort = null,Object? description = null,Object? nameZh = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,colorHex: null == colorHex ? _self.colorHex : colorHex // ignore: cast_nullable_to_non_nullable
as String,iconName: null == iconName ? _self.iconName : iconName // ignore: cast_nullable_to_non_nullable
as String,platforms: null == platforms ? _self.platforms : platforms // ignore: cast_nullable_to_non_nullable
as Map<String, GameAssistPlatformRules>,steamAppId: freezed == steamAppId ? _self.steamAppId : steamAppId // ignore: cast_nullable_to_non_nullable
as int?,sgdbGameId: freezed == sgdbGameId ? _self.sgdbGameId : sgdbGameId // ignore: cast_nullable_to_non_nullable
as int?,iconAsset: freezed == iconAsset ? _self.iconAsset : iconAsset // ignore: cast_nullable_to_non_nullable
as String?,gridAsset: freezed == gridAsset ? _self.gridAsset : gridAsset // ignore: cast_nullable_to_non_nullable
as String?,showInPicker: null == showInPicker ? _self.showInPicker : showInPicker // ignore: cast_nullable_to_non_nullable
as bool,sort: null == sort ? _self.sort : sort // ignore: cast_nullable_to_non_nullable
as int,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,nameZh: null == nameZh ? _self.nameZh : nameZh // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [GameAssistGameRules].
extension GameAssistGameRulesPatterns on GameAssistGameRules {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameAssistGameRules value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameAssistGameRules() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameAssistGameRules value)  $default,){
final _that = this;
switch (_that) {
case _GameAssistGameRules():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameAssistGameRules value)?  $default,){
final _that = this;
switch (_that) {
case _GameAssistGameRules() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String colorHex,  String iconName,  Map<String, GameAssistPlatformRules> platforms,  int? steamAppId,  int? sgdbGameId,  String? iconAsset,  String? gridAsset,  bool showInPicker,  int sort,  String description,  String nameZh)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameAssistGameRules() when $default != null:
return $default(_that.id,_that.name,_that.colorHex,_that.iconName,_that.platforms,_that.steamAppId,_that.sgdbGameId,_that.iconAsset,_that.gridAsset,_that.showInPicker,_that.sort,_that.description,_that.nameZh);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String colorHex,  String iconName,  Map<String, GameAssistPlatformRules> platforms,  int? steamAppId,  int? sgdbGameId,  String? iconAsset,  String? gridAsset,  bool showInPicker,  int sort,  String description,  String nameZh)  $default,) {final _that = this;
switch (_that) {
case _GameAssistGameRules():
return $default(_that.id,_that.name,_that.colorHex,_that.iconName,_that.platforms,_that.steamAppId,_that.sgdbGameId,_that.iconAsset,_that.gridAsset,_that.showInPicker,_that.sort,_that.description,_that.nameZh);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String colorHex,  String iconName,  Map<String, GameAssistPlatformRules> platforms,  int? steamAppId,  int? sgdbGameId,  String? iconAsset,  String? gridAsset,  bool showInPicker,  int sort,  String description,  String nameZh)?  $default,) {final _that = this;
switch (_that) {
case _GameAssistGameRules() when $default != null:
return $default(_that.id,_that.name,_that.colorHex,_that.iconName,_that.platforms,_that.steamAppId,_that.sgdbGameId,_that.iconAsset,_that.gridAsset,_that.showInPicker,_that.sort,_that.description,_that.nameZh);case _:
  return null;

}
}

}

/// @nodoc


class _GameAssistGameRules extends GameAssistGameRules {
  const _GameAssistGameRules({required this.id, required this.name, required this.colorHex, required this.iconName, required final  Map<String, GameAssistPlatformRules> platforms, this.steamAppId, this.sgdbGameId, this.iconAsset, this.gridAsset, this.showInPicker = true, this.sort = 100, this.description = '', this.nameZh = ''}): _platforms = platforms,super._();
  

@override final  String id;
@override final  String name;
/// `#RRGGBB` 或 `#AARRGGBB`。
@override final  String colorHex;
/// Material Icons 名称，如 `terrain`。
@override final  String iconName;
 final  Map<String, GameAssistPlatformRules> _platforms;
@override Map<String, GameAssistPlatformRules> get platforms {
  if (_platforms is EqualUnmodifiableMapView) return _platforms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_platforms);
}

@override final  int? steamAppId;
@override final  int? sgdbGameId;
@override final  String? iconAsset;
@override final  String? gridAsset;
@override@JsonKey() final  bool showInPicker;
@override@JsonKey() final  int sort;
/// 选择器里标题下方的短说明。
@override@JsonKey() final  String description;
/// 中文名；有则 UI 优先显示。
@override@JsonKey() final  String nameZh;

/// Create a copy of GameAssistGameRules
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameAssistGameRulesCopyWith<_GameAssistGameRules> get copyWith => __$GameAssistGameRulesCopyWithImpl<_GameAssistGameRules>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameAssistGameRules&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.colorHex, colorHex) || other.colorHex == colorHex)&&(identical(other.iconName, iconName) || other.iconName == iconName)&&const DeepCollectionEquality().equals(other._platforms, _platforms)&&(identical(other.steamAppId, steamAppId) || other.steamAppId == steamAppId)&&(identical(other.sgdbGameId, sgdbGameId) || other.sgdbGameId == sgdbGameId)&&(identical(other.iconAsset, iconAsset) || other.iconAsset == iconAsset)&&(identical(other.gridAsset, gridAsset) || other.gridAsset == gridAsset)&&(identical(other.showInPicker, showInPicker) || other.showInPicker == showInPicker)&&(identical(other.sort, sort) || other.sort == sort)&&(identical(other.description, description) || other.description == description)&&(identical(other.nameZh, nameZh) || other.nameZh == nameZh));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,colorHex,iconName,const DeepCollectionEquality().hash(_platforms),steamAppId,sgdbGameId,iconAsset,gridAsset,showInPicker,sort,description,nameZh);

@override
String toString() {
  return 'GameAssistGameRules(id: $id, name: $name, colorHex: $colorHex, iconName: $iconName, platforms: $platforms, steamAppId: $steamAppId, sgdbGameId: $sgdbGameId, iconAsset: $iconAsset, gridAsset: $gridAsset, showInPicker: $showInPicker, sort: $sort, description: $description, nameZh: $nameZh)';
}


}

/// @nodoc
abstract mixin class _$GameAssistGameRulesCopyWith<$Res> implements $GameAssistGameRulesCopyWith<$Res> {
  factory _$GameAssistGameRulesCopyWith(_GameAssistGameRules value, $Res Function(_GameAssistGameRules) _then) = __$GameAssistGameRulesCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String colorHex, String iconName, Map<String, GameAssistPlatformRules> platforms, int? steamAppId, int? sgdbGameId, String? iconAsset, String? gridAsset, bool showInPicker, int sort, String description, String nameZh
});




}
/// @nodoc
class __$GameAssistGameRulesCopyWithImpl<$Res>
    implements _$GameAssistGameRulesCopyWith<$Res> {
  __$GameAssistGameRulesCopyWithImpl(this._self, this._then);

  final _GameAssistGameRules _self;
  final $Res Function(_GameAssistGameRules) _then;

/// Create a copy of GameAssistGameRules
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? colorHex = null,Object? iconName = null,Object? platforms = null,Object? steamAppId = freezed,Object? sgdbGameId = freezed,Object? iconAsset = freezed,Object? gridAsset = freezed,Object? showInPicker = null,Object? sort = null,Object? description = null,Object? nameZh = null,}) {
  return _then(_GameAssistGameRules(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,colorHex: null == colorHex ? _self.colorHex : colorHex // ignore: cast_nullable_to_non_nullable
as String,iconName: null == iconName ? _self.iconName : iconName // ignore: cast_nullable_to_non_nullable
as String,platforms: null == platforms ? _self._platforms : platforms // ignore: cast_nullable_to_non_nullable
as Map<String, GameAssistPlatformRules>,steamAppId: freezed == steamAppId ? _self.steamAppId : steamAppId // ignore: cast_nullable_to_non_nullable
as int?,sgdbGameId: freezed == sgdbGameId ? _self.sgdbGameId : sgdbGameId // ignore: cast_nullable_to_non_nullable
as int?,iconAsset: freezed == iconAsset ? _self.iconAsset : iconAsset // ignore: cast_nullable_to_non_nullable
as String?,gridAsset: freezed == gridAsset ? _self.gridAsset : gridAsset // ignore: cast_nullable_to_non_nullable
as String?,showInPicker: null == showInPicker ? _self.showInPicker : showInPicker // ignore: cast_nullable_to_non_nullable
as bool,sort: null == sort ? _self.sort : sort // ignore: cast_nullable_to_non_nullable
as int,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,nameZh: null == nameZh ? _self.nameZh : nameZh // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$GameAssistLanGameDiscoverConfig {

 List<GameAssistLanGameDiscoverEntry> get entries;
/// Create a copy of GameAssistLanGameDiscoverConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameAssistLanGameDiscoverConfigCopyWith<GameAssistLanGameDiscoverConfig> get copyWith => _$GameAssistLanGameDiscoverConfigCopyWithImpl<GameAssistLanGameDiscoverConfig>(this as GameAssistLanGameDiscoverConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameAssistLanGameDiscoverConfig&&const DeepCollectionEquality().equals(other.entries, entries));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(entries));

@override
String toString() {
  return 'GameAssistLanGameDiscoverConfig(entries: $entries)';
}


}

/// @nodoc
abstract mixin class $GameAssistLanGameDiscoverConfigCopyWith<$Res>  {
  factory $GameAssistLanGameDiscoverConfigCopyWith(GameAssistLanGameDiscoverConfig value, $Res Function(GameAssistLanGameDiscoverConfig) _then) = _$GameAssistLanGameDiscoverConfigCopyWithImpl;
@useResult
$Res call({
 List<GameAssistLanGameDiscoverEntry> entries
});




}
/// @nodoc
class _$GameAssistLanGameDiscoverConfigCopyWithImpl<$Res>
    implements $GameAssistLanGameDiscoverConfigCopyWith<$Res> {
  _$GameAssistLanGameDiscoverConfigCopyWithImpl(this._self, this._then);

  final GameAssistLanGameDiscoverConfig _self;
  final $Res Function(GameAssistLanGameDiscoverConfig) _then;

/// Create a copy of GameAssistLanGameDiscoverConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entries = null,}) {
  return _then(_self.copyWith(
entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<GameAssistLanGameDiscoverEntry>,
  ));
}

}


/// Adds pattern-matching-related methods to [GameAssistLanGameDiscoverConfig].
extension GameAssistLanGameDiscoverConfigPatterns on GameAssistLanGameDiscoverConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameAssistLanGameDiscoverConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameAssistLanGameDiscoverConfig value)  $default,){
final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameAssistLanGameDiscoverConfig value)?  $default,){
final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<GameAssistLanGameDiscoverEntry> entries)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverConfig() when $default != null:
return $default(_that.entries);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<GameAssistLanGameDiscoverEntry> entries)  $default,) {final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverConfig():
return $default(_that.entries);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<GameAssistLanGameDiscoverEntry> entries)?  $default,) {final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverConfig() when $default != null:
return $default(_that.entries);case _:
  return null;

}
}

}

/// @nodoc


class _GameAssistLanGameDiscoverConfig extends GameAssistLanGameDiscoverConfig {
  const _GameAssistLanGameDiscoverConfig({final  List<GameAssistLanGameDiscoverEntry> entries = const []}): _entries = entries,super._();
  

 final  List<GameAssistLanGameDiscoverEntry> _entries;
@override@JsonKey() List<GameAssistLanGameDiscoverEntry> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}


/// Create a copy of GameAssistLanGameDiscoverConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameAssistLanGameDiscoverConfigCopyWith<_GameAssistLanGameDiscoverConfig> get copyWith => __$GameAssistLanGameDiscoverConfigCopyWithImpl<_GameAssistLanGameDiscoverConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameAssistLanGameDiscoverConfig&&const DeepCollectionEquality().equals(other._entries, _entries));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_entries));

@override
String toString() {
  return 'GameAssistLanGameDiscoverConfig(entries: $entries)';
}


}

/// @nodoc
abstract mixin class _$GameAssistLanGameDiscoverConfigCopyWith<$Res> implements $GameAssistLanGameDiscoverConfigCopyWith<$Res> {
  factory _$GameAssistLanGameDiscoverConfigCopyWith(_GameAssistLanGameDiscoverConfig value, $Res Function(_GameAssistLanGameDiscoverConfig) _then) = __$GameAssistLanGameDiscoverConfigCopyWithImpl;
@override @useResult
$Res call({
 List<GameAssistLanGameDiscoverEntry> entries
});




}
/// @nodoc
class __$GameAssistLanGameDiscoverConfigCopyWithImpl<$Res>
    implements _$GameAssistLanGameDiscoverConfigCopyWith<$Res> {
  __$GameAssistLanGameDiscoverConfigCopyWithImpl(this._self, this._then);

  final _GameAssistLanGameDiscoverConfig _self;
  final $Res Function(_GameAssistLanGameDiscoverConfig) _then;

/// Create a copy of GameAssistLanGameDiscoverConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entries = null,}) {
  return _then(_GameAssistLanGameDiscoverConfig(
entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<GameAssistLanGameDiscoverEntry>,
  ));
}


}

/// @nodoc
mixin _$GameAssistLanGameDiscoverEntry {

 String get id; String get label;/// `static_port` | `udp_multicast` | `udp_probe` | `udp_broadcast` | `process_udp`
 String get type; int get port;/// 组播地址（不含端口）。
 String? get multicast; int get multicastPort;/// `minecraft_motd` / `mindustry_server` / `scfa_lan` …
 String? get parser;/// `udp_probe` 探测包十六进制，如 `fe01`。
 String? get probe;/// 标题模板：`{player}` `{game}` `{label}` `{motd}` `{map}`。
 String? get title;/// `process_udp`：exe 名，如 `game.exe`。
 List<String> get process;/// `process_udp`：窗口标题关键字，如 `Forged Alliance`。
 List<String> get window;/// `process_udp`：本机代答发现口（FA 默认 15000）。
 int get beaconPort;
/// Create a copy of GameAssistLanGameDiscoverEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameAssistLanGameDiscoverEntryCopyWith<GameAssistLanGameDiscoverEntry> get copyWith => _$GameAssistLanGameDiscoverEntryCopyWithImpl<GameAssistLanGameDiscoverEntry>(this as GameAssistLanGameDiscoverEntry, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameAssistLanGameDiscoverEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.type, type) || other.type == type)&&(identical(other.port, port) || other.port == port)&&(identical(other.multicast, multicast) || other.multicast == multicast)&&(identical(other.multicastPort, multicastPort) || other.multicastPort == multicastPort)&&(identical(other.parser, parser) || other.parser == parser)&&(identical(other.probe, probe) || other.probe == probe)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.process, process)&&const DeepCollectionEquality().equals(other.window, window)&&(identical(other.beaconPort, beaconPort) || other.beaconPort == beaconPort));
}


@override
int get hashCode => Object.hash(runtimeType,id,label,type,port,multicast,multicastPort,parser,probe,title,const DeepCollectionEquality().hash(process),const DeepCollectionEquality().hash(window),beaconPort);

@override
String toString() {
  return 'GameAssistLanGameDiscoverEntry(id: $id, label: $label, type: $type, port: $port, multicast: $multicast, multicastPort: $multicastPort, parser: $parser, probe: $probe, title: $title, process: $process, window: $window, beaconPort: $beaconPort)';
}


}

/// @nodoc
abstract mixin class $GameAssistLanGameDiscoverEntryCopyWith<$Res>  {
  factory $GameAssistLanGameDiscoverEntryCopyWith(GameAssistLanGameDiscoverEntry value, $Res Function(GameAssistLanGameDiscoverEntry) _then) = _$GameAssistLanGameDiscoverEntryCopyWithImpl;
@useResult
$Res call({
 String id, String label, String type, int port, String? multicast, int multicastPort, String? parser, String? probe, String? title, List<String> process, List<String> window, int beaconPort
});




}
/// @nodoc
class _$GameAssistLanGameDiscoverEntryCopyWithImpl<$Res>
    implements $GameAssistLanGameDiscoverEntryCopyWith<$Res> {
  _$GameAssistLanGameDiscoverEntryCopyWithImpl(this._self, this._then);

  final GameAssistLanGameDiscoverEntry _self;
  final $Res Function(GameAssistLanGameDiscoverEntry) _then;

/// Create a copy of GameAssistLanGameDiscoverEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? type = null,Object? port = null,Object? multicast = freezed,Object? multicastPort = null,Object? parser = freezed,Object? probe = freezed,Object? title = freezed,Object? process = null,Object? window = null,Object? beaconPort = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,multicast: freezed == multicast ? _self.multicast : multicast // ignore: cast_nullable_to_non_nullable
as String?,multicastPort: null == multicastPort ? _self.multicastPort : multicastPort // ignore: cast_nullable_to_non_nullable
as int,parser: freezed == parser ? _self.parser : parser // ignore: cast_nullable_to_non_nullable
as String?,probe: freezed == probe ? _self.probe : probe // ignore: cast_nullable_to_non_nullable
as String?,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,process: null == process ? _self.process : process // ignore: cast_nullable_to_non_nullable
as List<String>,window: null == window ? _self.window : window // ignore: cast_nullable_to_non_nullable
as List<String>,beaconPort: null == beaconPort ? _self.beaconPort : beaconPort // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [GameAssistLanGameDiscoverEntry].
extension GameAssistLanGameDiscoverEntryPatterns on GameAssistLanGameDiscoverEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameAssistLanGameDiscoverEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameAssistLanGameDiscoverEntry value)  $default,){
final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameAssistLanGameDiscoverEntry value)?  $default,){
final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String label,  String type,  int port,  String? multicast,  int multicastPort,  String? parser,  String? probe,  String? title,  List<String> process,  List<String> window,  int beaconPort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverEntry() when $default != null:
return $default(_that.id,_that.label,_that.type,_that.port,_that.multicast,_that.multicastPort,_that.parser,_that.probe,_that.title,_that.process,_that.window,_that.beaconPort);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String label,  String type,  int port,  String? multicast,  int multicastPort,  String? parser,  String? probe,  String? title,  List<String> process,  List<String> window,  int beaconPort)  $default,) {final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverEntry():
return $default(_that.id,_that.label,_that.type,_that.port,_that.multicast,_that.multicastPort,_that.parser,_that.probe,_that.title,_that.process,_that.window,_that.beaconPort);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String label,  String type,  int port,  String? multicast,  int multicastPort,  String? parser,  String? probe,  String? title,  List<String> process,  List<String> window,  int beaconPort)?  $default,) {final _that = this;
switch (_that) {
case _GameAssistLanGameDiscoverEntry() when $default != null:
return $default(_that.id,_that.label,_that.type,_that.port,_that.multicast,_that.multicastPort,_that.parser,_that.probe,_that.title,_that.process,_that.window,_that.beaconPort);case _:
  return null;

}
}

}

/// @nodoc


class _GameAssistLanGameDiscoverEntry extends GameAssistLanGameDiscoverEntry {
  const _GameAssistLanGameDiscoverEntry({required this.id, required this.label, required this.type, this.port = 0, this.multicast, this.multicastPort = 0, this.parser, this.probe, this.title, final  List<String> process = const [], final  List<String> window = const [], this.beaconPort = 0}): _process = process,_window = window,super._();
  

@override final  String id;
@override final  String label;
/// `static_port` | `udp_multicast` | `udp_probe` | `udp_broadcast` | `process_udp`
@override final  String type;
@override@JsonKey() final  int port;
/// 组播地址（不含端口）。
@override final  String? multicast;
@override@JsonKey() final  int multicastPort;
/// `minecraft_motd` / `mindustry_server` / `scfa_lan` …
@override final  String? parser;
/// `udp_probe` 探测包十六进制，如 `fe01`。
@override final  String? probe;
/// 标题模板：`{player}` `{game}` `{label}` `{motd}` `{map}`。
@override final  String? title;
/// `process_udp`：exe 名，如 `game.exe`。
 final  List<String> _process;
/// `process_udp`：exe 名，如 `game.exe`。
@override@JsonKey() List<String> get process {
  if (_process is EqualUnmodifiableListView) return _process;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_process);
}

/// `process_udp`：窗口标题关键字，如 `Forged Alliance`。
 final  List<String> _window;
/// `process_udp`：窗口标题关键字，如 `Forged Alliance`。
@override@JsonKey() List<String> get window {
  if (_window is EqualUnmodifiableListView) return _window;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_window);
}

/// `process_udp`：本机代答发现口（FA 默认 15000）。
@override@JsonKey() final  int beaconPort;

/// Create a copy of GameAssistLanGameDiscoverEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameAssistLanGameDiscoverEntryCopyWith<_GameAssistLanGameDiscoverEntry> get copyWith => __$GameAssistLanGameDiscoverEntryCopyWithImpl<_GameAssistLanGameDiscoverEntry>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameAssistLanGameDiscoverEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.type, type) || other.type == type)&&(identical(other.port, port) || other.port == port)&&(identical(other.multicast, multicast) || other.multicast == multicast)&&(identical(other.multicastPort, multicastPort) || other.multicastPort == multicastPort)&&(identical(other.parser, parser) || other.parser == parser)&&(identical(other.probe, probe) || other.probe == probe)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other._process, _process)&&const DeepCollectionEquality().equals(other._window, _window)&&(identical(other.beaconPort, beaconPort) || other.beaconPort == beaconPort));
}


@override
int get hashCode => Object.hash(runtimeType,id,label,type,port,multicast,multicastPort,parser,probe,title,const DeepCollectionEquality().hash(_process),const DeepCollectionEquality().hash(_window),beaconPort);

@override
String toString() {
  return 'GameAssistLanGameDiscoverEntry(id: $id, label: $label, type: $type, port: $port, multicast: $multicast, multicastPort: $multicastPort, parser: $parser, probe: $probe, title: $title, process: $process, window: $window, beaconPort: $beaconPort)';
}


}

/// @nodoc
abstract mixin class _$GameAssistLanGameDiscoverEntryCopyWith<$Res> implements $GameAssistLanGameDiscoverEntryCopyWith<$Res> {
  factory _$GameAssistLanGameDiscoverEntryCopyWith(_GameAssistLanGameDiscoverEntry value, $Res Function(_GameAssistLanGameDiscoverEntry) _then) = __$GameAssistLanGameDiscoverEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, String type, int port, String? multicast, int multicastPort, String? parser, String? probe, String? title, List<String> process, List<String> window, int beaconPort
});




}
/// @nodoc
class __$GameAssistLanGameDiscoverEntryCopyWithImpl<$Res>
    implements _$GameAssistLanGameDiscoverEntryCopyWith<$Res> {
  __$GameAssistLanGameDiscoverEntryCopyWithImpl(this._self, this._then);

  final _GameAssistLanGameDiscoverEntry _self;
  final $Res Function(_GameAssistLanGameDiscoverEntry) _then;

/// Create a copy of GameAssistLanGameDiscoverEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? type = null,Object? port = null,Object? multicast = freezed,Object? multicastPort = null,Object? parser = freezed,Object? probe = freezed,Object? title = freezed,Object? process = null,Object? window = null,Object? beaconPort = null,}) {
  return _then(_GameAssistLanGameDiscoverEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,multicast: freezed == multicast ? _self.multicast : multicast // ignore: cast_nullable_to_non_nullable
as String?,multicastPort: null == multicastPort ? _self.multicastPort : multicastPort // ignore: cast_nullable_to_non_nullable
as int,parser: freezed == parser ? _self.parser : parser // ignore: cast_nullable_to_non_nullable
as String?,probe: freezed == probe ? _self.probe : probe // ignore: cast_nullable_to_non_nullable
as String?,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,process: null == process ? _self._process : process // ignore: cast_nullable_to_non_nullable
as List<String>,window: null == window ? _self._window : window // ignore: cast_nullable_to_non_nullable
as List<String>,beaconPort: null == beaconPort ? _self.beaconPort : beaconPort // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$GameAssistNetworkConfig {

/// 写入 TOML `[flags] enable_udp_broadcast_relay`（Windows）。
 bool get enableUdpBroadcastRelay;/// `tcp` / `udp`；未写则 UDP。
 GameAssistNetworkProtocol get protocol;/// JSON 是否显式写了 `protocol`（合并远程时避免把未写当成 UDP 覆盖本地）。
 bool get protocolSpecified;
/// Create a copy of GameAssistNetworkConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameAssistNetworkConfigCopyWith<GameAssistNetworkConfig> get copyWith => _$GameAssistNetworkConfigCopyWithImpl<GameAssistNetworkConfig>(this as GameAssistNetworkConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameAssistNetworkConfig&&(identical(other.enableUdpBroadcastRelay, enableUdpBroadcastRelay) || other.enableUdpBroadcastRelay == enableUdpBroadcastRelay)&&(identical(other.protocol, protocol) || other.protocol == protocol)&&(identical(other.protocolSpecified, protocolSpecified) || other.protocolSpecified == protocolSpecified));
}


@override
int get hashCode => Object.hash(runtimeType,enableUdpBroadcastRelay,protocol,protocolSpecified);

@override
String toString() {
  return 'GameAssistNetworkConfig(enableUdpBroadcastRelay: $enableUdpBroadcastRelay, protocol: $protocol, protocolSpecified: $protocolSpecified)';
}


}

/// @nodoc
abstract mixin class $GameAssistNetworkConfigCopyWith<$Res>  {
  factory $GameAssistNetworkConfigCopyWith(GameAssistNetworkConfig value, $Res Function(GameAssistNetworkConfig) _then) = _$GameAssistNetworkConfigCopyWithImpl;
@useResult
$Res call({
 bool enableUdpBroadcastRelay, GameAssistNetworkProtocol protocol, bool protocolSpecified
});




}
/// @nodoc
class _$GameAssistNetworkConfigCopyWithImpl<$Res>
    implements $GameAssistNetworkConfigCopyWith<$Res> {
  _$GameAssistNetworkConfigCopyWithImpl(this._self, this._then);

  final GameAssistNetworkConfig _self;
  final $Res Function(GameAssistNetworkConfig) _then;

/// Create a copy of GameAssistNetworkConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? enableUdpBroadcastRelay = null,Object? protocol = null,Object? protocolSpecified = null,}) {
  return _then(_self.copyWith(
enableUdpBroadcastRelay: null == enableUdpBroadcastRelay ? _self.enableUdpBroadcastRelay : enableUdpBroadcastRelay // ignore: cast_nullable_to_non_nullable
as bool,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as GameAssistNetworkProtocol,protocolSpecified: null == protocolSpecified ? _self.protocolSpecified : protocolSpecified // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [GameAssistNetworkConfig].
extension GameAssistNetworkConfigPatterns on GameAssistNetworkConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameAssistNetworkConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameAssistNetworkConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameAssistNetworkConfig value)  $default,){
final _that = this;
switch (_that) {
case _GameAssistNetworkConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameAssistNetworkConfig value)?  $default,){
final _that = this;
switch (_that) {
case _GameAssistNetworkConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool enableUdpBroadcastRelay,  GameAssistNetworkProtocol protocol,  bool protocolSpecified)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameAssistNetworkConfig() when $default != null:
return $default(_that.enableUdpBroadcastRelay,_that.protocol,_that.protocolSpecified);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool enableUdpBroadcastRelay,  GameAssistNetworkProtocol protocol,  bool protocolSpecified)  $default,) {final _that = this;
switch (_that) {
case _GameAssistNetworkConfig():
return $default(_that.enableUdpBroadcastRelay,_that.protocol,_that.protocolSpecified);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool enableUdpBroadcastRelay,  GameAssistNetworkProtocol protocol,  bool protocolSpecified)?  $default,) {final _that = this;
switch (_that) {
case _GameAssistNetworkConfig() when $default != null:
return $default(_that.enableUdpBroadcastRelay,_that.protocol,_that.protocolSpecified);case _:
  return null;

}
}

}

/// @nodoc


class _GameAssistNetworkConfig extends GameAssistNetworkConfig {
  const _GameAssistNetworkConfig({this.enableUdpBroadcastRelay = false, this.protocol = GameAssistNetworkProtocol.udp, this.protocolSpecified = false}): super._();
  

/// 写入 TOML `[flags] enable_udp_broadcast_relay`（Windows）。
@override@JsonKey() final  bool enableUdpBroadcastRelay;
/// `tcp` / `udp`；未写则 UDP。
@override@JsonKey() final  GameAssistNetworkProtocol protocol;
/// JSON 是否显式写了 `protocol`（合并远程时避免把未写当成 UDP 覆盖本地）。
@override@JsonKey() final  bool protocolSpecified;

/// Create a copy of GameAssistNetworkConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameAssistNetworkConfigCopyWith<_GameAssistNetworkConfig> get copyWith => __$GameAssistNetworkConfigCopyWithImpl<_GameAssistNetworkConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameAssistNetworkConfig&&(identical(other.enableUdpBroadcastRelay, enableUdpBroadcastRelay) || other.enableUdpBroadcastRelay == enableUdpBroadcastRelay)&&(identical(other.protocol, protocol) || other.protocol == protocol)&&(identical(other.protocolSpecified, protocolSpecified) || other.protocolSpecified == protocolSpecified));
}


@override
int get hashCode => Object.hash(runtimeType,enableUdpBroadcastRelay,protocol,protocolSpecified);

@override
String toString() {
  return 'GameAssistNetworkConfig(enableUdpBroadcastRelay: $enableUdpBroadcastRelay, protocol: $protocol, protocolSpecified: $protocolSpecified)';
}


}

/// @nodoc
abstract mixin class _$GameAssistNetworkConfigCopyWith<$Res> implements $GameAssistNetworkConfigCopyWith<$Res> {
  factory _$GameAssistNetworkConfigCopyWith(_GameAssistNetworkConfig value, $Res Function(_GameAssistNetworkConfig) _then) = __$GameAssistNetworkConfigCopyWithImpl;
@override @useResult
$Res call({
 bool enableUdpBroadcastRelay, GameAssistNetworkProtocol protocol, bool protocolSpecified
});




}
/// @nodoc
class __$GameAssistNetworkConfigCopyWithImpl<$Res>
    implements _$GameAssistNetworkConfigCopyWith<$Res> {
  __$GameAssistNetworkConfigCopyWithImpl(this._self, this._then);

  final _GameAssistNetworkConfig _self;
  final $Res Function(_GameAssistNetworkConfig) _then;

/// Create a copy of GameAssistNetworkConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? enableUdpBroadcastRelay = null,Object? protocol = null,Object? protocolSpecified = null,}) {
  return _then(_GameAssistNetworkConfig(
enableUdpBroadcastRelay: null == enableUdpBroadcastRelay ? _self.enableUdpBroadcastRelay : enableUdpBroadcastRelay // ignore: cast_nullable_to_non_nullable
as bool,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as GameAssistNetworkProtocol,protocolSpecified: null == protocolSpecified ? _self.protocolSpecified : protocolSpecified // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$GameAssistPlatformRules {

 GameAssistNetworkConfig get network; GameAssistMagicWallConfig get magicWall; List<GameAssistForwardRule> get forwards;/// 发现本机开放游戏并经 ET 宣告。
 GameAssistLanGameDiscoverConfig? get lanGameDiscover;/// 进房后自动检测进程并注入（Windows / Unity Mono）。
 GameAssistInjectConfig? get inject;
/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameAssistPlatformRulesCopyWith<GameAssistPlatformRules> get copyWith => _$GameAssistPlatformRulesCopyWithImpl<GameAssistPlatformRules>(this as GameAssistPlatformRules, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameAssistPlatformRules&&(identical(other.network, network) || other.network == network)&&(identical(other.magicWall, magicWall) || other.magicWall == magicWall)&&const DeepCollectionEquality().equals(other.forwards, forwards)&&(identical(other.lanGameDiscover, lanGameDiscover) || other.lanGameDiscover == lanGameDiscover)&&(identical(other.inject, inject) || other.inject == inject));
}


@override
int get hashCode => Object.hash(runtimeType,network,magicWall,const DeepCollectionEquality().hash(forwards),lanGameDiscover,inject);

@override
String toString() {
  return 'GameAssistPlatformRules(network: $network, magicWall: $magicWall, forwards: $forwards, lanGameDiscover: $lanGameDiscover, inject: $inject)';
}


}

/// @nodoc
abstract mixin class $GameAssistPlatformRulesCopyWith<$Res>  {
  factory $GameAssistPlatformRulesCopyWith(GameAssistPlatformRules value, $Res Function(GameAssistPlatformRules) _then) = _$GameAssistPlatformRulesCopyWithImpl;
@useResult
$Res call({
 GameAssistNetworkConfig network, GameAssistMagicWallConfig magicWall, List<GameAssistForwardRule> forwards, GameAssistLanGameDiscoverConfig? lanGameDiscover, GameAssistInjectConfig? inject
});


$GameAssistNetworkConfigCopyWith<$Res> get network;$GameAssistMagicWallConfigCopyWith<$Res> get magicWall;$GameAssistLanGameDiscoverConfigCopyWith<$Res>? get lanGameDiscover;$GameAssistInjectConfigCopyWith<$Res>? get inject;

}
/// @nodoc
class _$GameAssistPlatformRulesCopyWithImpl<$Res>
    implements $GameAssistPlatformRulesCopyWith<$Res> {
  _$GameAssistPlatformRulesCopyWithImpl(this._self, this._then);

  final GameAssistPlatformRules _self;
  final $Res Function(GameAssistPlatformRules) _then;

/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? network = null,Object? magicWall = null,Object? forwards = null,Object? lanGameDiscover = freezed,Object? inject = freezed,}) {
  return _then(_self.copyWith(
network: null == network ? _self.network : network // ignore: cast_nullable_to_non_nullable
as GameAssistNetworkConfig,magicWall: null == magicWall ? _self.magicWall : magicWall // ignore: cast_nullable_to_non_nullable
as GameAssistMagicWallConfig,forwards: null == forwards ? _self.forwards : forwards // ignore: cast_nullable_to_non_nullable
as List<GameAssistForwardRule>,lanGameDiscover: freezed == lanGameDiscover ? _self.lanGameDiscover : lanGameDiscover // ignore: cast_nullable_to_non_nullable
as GameAssistLanGameDiscoverConfig?,inject: freezed == inject ? _self.inject : inject // ignore: cast_nullable_to_non_nullable
as GameAssistInjectConfig?,
  ));
}
/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameAssistNetworkConfigCopyWith<$Res> get network {
  
  return $GameAssistNetworkConfigCopyWith<$Res>(_self.network, (value) {
    return _then(_self.copyWith(network: value));
  });
}/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameAssistMagicWallConfigCopyWith<$Res> get magicWall {
  
  return $GameAssistMagicWallConfigCopyWith<$Res>(_self.magicWall, (value) {
    return _then(_self.copyWith(magicWall: value));
  });
}/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameAssistLanGameDiscoverConfigCopyWith<$Res>? get lanGameDiscover {
    if (_self.lanGameDiscover == null) {
    return null;
  }

  return $GameAssistLanGameDiscoverConfigCopyWith<$Res>(_self.lanGameDiscover!, (value) {
    return _then(_self.copyWith(lanGameDiscover: value));
  });
}/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameAssistInjectConfigCopyWith<$Res>? get inject {
    if (_self.inject == null) {
    return null;
  }

  return $GameAssistInjectConfigCopyWith<$Res>(_self.inject!, (value) {
    return _then(_self.copyWith(inject: value));
  });
}
}


/// Adds pattern-matching-related methods to [GameAssistPlatformRules].
extension GameAssistPlatformRulesPatterns on GameAssistPlatformRules {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameAssistPlatformRules value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameAssistPlatformRules() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameAssistPlatformRules value)  $default,){
final _that = this;
switch (_that) {
case _GameAssistPlatformRules():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameAssistPlatformRules value)?  $default,){
final _that = this;
switch (_that) {
case _GameAssistPlatformRules() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( GameAssistNetworkConfig network,  GameAssistMagicWallConfig magicWall,  List<GameAssistForwardRule> forwards,  GameAssistLanGameDiscoverConfig? lanGameDiscover,  GameAssistInjectConfig? inject)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameAssistPlatformRules() when $default != null:
return $default(_that.network,_that.magicWall,_that.forwards,_that.lanGameDiscover,_that.inject);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( GameAssistNetworkConfig network,  GameAssistMagicWallConfig magicWall,  List<GameAssistForwardRule> forwards,  GameAssistLanGameDiscoverConfig? lanGameDiscover,  GameAssistInjectConfig? inject)  $default,) {final _that = this;
switch (_that) {
case _GameAssistPlatformRules():
return $default(_that.network,_that.magicWall,_that.forwards,_that.lanGameDiscover,_that.inject);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( GameAssistNetworkConfig network,  GameAssistMagicWallConfig magicWall,  List<GameAssistForwardRule> forwards,  GameAssistLanGameDiscoverConfig? lanGameDiscover,  GameAssistInjectConfig? inject)?  $default,) {final _that = this;
switch (_that) {
case _GameAssistPlatformRules() when $default != null:
return $default(_that.network,_that.magicWall,_that.forwards,_that.lanGameDiscover,_that.inject);case _:
  return null;

}
}

}

/// @nodoc


class _GameAssistPlatformRules extends GameAssistPlatformRules {
  const _GameAssistPlatformRules({this.network = const GameAssistNetworkConfig(), required this.magicWall, final  List<GameAssistForwardRule> forwards = const [], this.lanGameDiscover, this.inject}): _forwards = forwards,super._();
  

@override@JsonKey() final  GameAssistNetworkConfig network;
@override final  GameAssistMagicWallConfig magicWall;
 final  List<GameAssistForwardRule> _forwards;
@override@JsonKey() List<GameAssistForwardRule> get forwards {
  if (_forwards is EqualUnmodifiableListView) return _forwards;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_forwards);
}

/// 发现本机开放游戏并经 ET 宣告。
@override final  GameAssistLanGameDiscoverConfig? lanGameDiscover;
/// 进房后自动检测进程并注入（Windows / Unity Mono）。
@override final  GameAssistInjectConfig? inject;

/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameAssistPlatformRulesCopyWith<_GameAssistPlatformRules> get copyWith => __$GameAssistPlatformRulesCopyWithImpl<_GameAssistPlatformRules>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameAssistPlatformRules&&(identical(other.network, network) || other.network == network)&&(identical(other.magicWall, magicWall) || other.magicWall == magicWall)&&const DeepCollectionEquality().equals(other._forwards, _forwards)&&(identical(other.lanGameDiscover, lanGameDiscover) || other.lanGameDiscover == lanGameDiscover)&&(identical(other.inject, inject) || other.inject == inject));
}


@override
int get hashCode => Object.hash(runtimeType,network,magicWall,const DeepCollectionEquality().hash(_forwards),lanGameDiscover,inject);

@override
String toString() {
  return 'GameAssistPlatformRules(network: $network, magicWall: $magicWall, forwards: $forwards, lanGameDiscover: $lanGameDiscover, inject: $inject)';
}


}

/// @nodoc
abstract mixin class _$GameAssistPlatformRulesCopyWith<$Res> implements $GameAssistPlatformRulesCopyWith<$Res> {
  factory _$GameAssistPlatformRulesCopyWith(_GameAssistPlatformRules value, $Res Function(_GameAssistPlatformRules) _then) = __$GameAssistPlatformRulesCopyWithImpl;
@override @useResult
$Res call({
 GameAssistNetworkConfig network, GameAssistMagicWallConfig magicWall, List<GameAssistForwardRule> forwards, GameAssistLanGameDiscoverConfig? lanGameDiscover, GameAssistInjectConfig? inject
});


@override $GameAssistNetworkConfigCopyWith<$Res> get network;@override $GameAssistMagicWallConfigCopyWith<$Res> get magicWall;@override $GameAssistLanGameDiscoverConfigCopyWith<$Res>? get lanGameDiscover;@override $GameAssistInjectConfigCopyWith<$Res>? get inject;

}
/// @nodoc
class __$GameAssistPlatformRulesCopyWithImpl<$Res>
    implements _$GameAssistPlatformRulesCopyWith<$Res> {
  __$GameAssistPlatformRulesCopyWithImpl(this._self, this._then);

  final _GameAssistPlatformRules _self;
  final $Res Function(_GameAssistPlatformRules) _then;

/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? network = null,Object? magicWall = null,Object? forwards = null,Object? lanGameDiscover = freezed,Object? inject = freezed,}) {
  return _then(_GameAssistPlatformRules(
network: null == network ? _self.network : network // ignore: cast_nullable_to_non_nullable
as GameAssistNetworkConfig,magicWall: null == magicWall ? _self.magicWall : magicWall // ignore: cast_nullable_to_non_nullable
as GameAssistMagicWallConfig,forwards: null == forwards ? _self._forwards : forwards // ignore: cast_nullable_to_non_nullable
as List<GameAssistForwardRule>,lanGameDiscover: freezed == lanGameDiscover ? _self.lanGameDiscover : lanGameDiscover // ignore: cast_nullable_to_non_nullable
as GameAssistLanGameDiscoverConfig?,inject: freezed == inject ? _self.inject : inject // ignore: cast_nullable_to_non_nullable
as GameAssistInjectConfig?,
  ));
}

/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameAssistNetworkConfigCopyWith<$Res> get network {
  
  return $GameAssistNetworkConfigCopyWith<$Res>(_self.network, (value) {
    return _then(_self.copyWith(network: value));
  });
}/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameAssistMagicWallConfigCopyWith<$Res> get magicWall {
  
  return $GameAssistMagicWallConfigCopyWith<$Res>(_self.magicWall, (value) {
    return _then(_self.copyWith(magicWall: value));
  });
}/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameAssistLanGameDiscoverConfigCopyWith<$Res>? get lanGameDiscover {
    if (_self.lanGameDiscover == null) {
    return null;
  }

  return $GameAssistLanGameDiscoverConfigCopyWith<$Res>(_self.lanGameDiscover!, (value) {
    return _then(_self.copyWith(lanGameDiscover: value));
  });
}/// Create a copy of GameAssistPlatformRules
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameAssistInjectConfigCopyWith<$Res>? get inject {
    if (_self.inject == null) {
    return null;
  }

  return $GameAssistInjectConfigCopyWith<$Res>(_self.inject!, (value) {
    return _then(_self.copyWith(inject: value));
  });
}
}

/// @nodoc
mixin _$GameAssistInjectConfig {

/// 目前仅 `mono`（Unity）。
 String get type; List<String> get process; List<String> get window;/// 文件名，如 `AstralRaftNet.dll`。安装后在 `native/<gameId>/`。
 String get dll; String get namespace; String get className; String get method;/// 首次发现进程后等待多少秒再注入，避免游戏未完全启动就注入导致崩溃。
 int get delaySeconds;
/// Create a copy of GameAssistInjectConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameAssistInjectConfigCopyWith<GameAssistInjectConfig> get copyWith => _$GameAssistInjectConfigCopyWithImpl<GameAssistInjectConfig>(this as GameAssistInjectConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameAssistInjectConfig&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.process, process)&&const DeepCollectionEquality().equals(other.window, window)&&(identical(other.dll, dll) || other.dll == dll)&&(identical(other.namespace, namespace) || other.namespace == namespace)&&(identical(other.className, className) || other.className == className)&&(identical(other.method, method) || other.method == method)&&(identical(other.delaySeconds, delaySeconds) || other.delaySeconds == delaySeconds));
}


@override
int get hashCode => Object.hash(runtimeType,type,const DeepCollectionEquality().hash(process),const DeepCollectionEquality().hash(window),dll,namespace,className,method,delaySeconds);

@override
String toString() {
  return 'GameAssistInjectConfig(type: $type, process: $process, window: $window, dll: $dll, namespace: $namespace, className: $className, method: $method, delaySeconds: $delaySeconds)';
}


}

/// @nodoc
abstract mixin class $GameAssistInjectConfigCopyWith<$Res>  {
  factory $GameAssistInjectConfigCopyWith(GameAssistInjectConfig value, $Res Function(GameAssistInjectConfig) _then) = _$GameAssistInjectConfigCopyWithImpl;
@useResult
$Res call({
 String type, List<String> process, List<String> window, String dll, String namespace, String className, String method, int delaySeconds
});




}
/// @nodoc
class _$GameAssistInjectConfigCopyWithImpl<$Res>
    implements $GameAssistInjectConfigCopyWith<$Res> {
  _$GameAssistInjectConfigCopyWithImpl(this._self, this._then);

  final GameAssistInjectConfig _self;
  final $Res Function(GameAssistInjectConfig) _then;

/// Create a copy of GameAssistInjectConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? process = null,Object? window = null,Object? dll = null,Object? namespace = null,Object? className = null,Object? method = null,Object? delaySeconds = null,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,process: null == process ? _self.process : process // ignore: cast_nullable_to_non_nullable
as List<String>,window: null == window ? _self.window : window // ignore: cast_nullable_to_non_nullable
as List<String>,dll: null == dll ? _self.dll : dll // ignore: cast_nullable_to_non_nullable
as String,namespace: null == namespace ? _self.namespace : namespace // ignore: cast_nullable_to_non_nullable
as String,className: null == className ? _self.className : className // ignore: cast_nullable_to_non_nullable
as String,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,delaySeconds: null == delaySeconds ? _self.delaySeconds : delaySeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [GameAssistInjectConfig].
extension GameAssistInjectConfigPatterns on GameAssistInjectConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameAssistInjectConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameAssistInjectConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameAssistInjectConfig value)  $default,){
final _that = this;
switch (_that) {
case _GameAssistInjectConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameAssistInjectConfig value)?  $default,){
final _that = this;
switch (_that) {
case _GameAssistInjectConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String type,  List<String> process,  List<String> window,  String dll,  String namespace,  String className,  String method,  int delaySeconds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameAssistInjectConfig() when $default != null:
return $default(_that.type,_that.process,_that.window,_that.dll,_that.namespace,_that.className,_that.method,_that.delaySeconds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String type,  List<String> process,  List<String> window,  String dll,  String namespace,  String className,  String method,  int delaySeconds)  $default,) {final _that = this;
switch (_that) {
case _GameAssistInjectConfig():
return $default(_that.type,_that.process,_that.window,_that.dll,_that.namespace,_that.className,_that.method,_that.delaySeconds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String type,  List<String> process,  List<String> window,  String dll,  String namespace,  String className,  String method,  int delaySeconds)?  $default,) {final _that = this;
switch (_that) {
case _GameAssistInjectConfig() when $default != null:
return $default(_that.type,_that.process,_that.window,_that.dll,_that.namespace,_that.className,_that.method,_that.delaySeconds);case _:
  return null;

}
}

}

/// @nodoc


class _GameAssistInjectConfig extends GameAssistInjectConfig {
  const _GameAssistInjectConfig({required this.type, final  List<String> process = const [], final  List<String> window = const [], this.dll = '', this.namespace = '', this.className = '', this.method = 'Init', this.delaySeconds = 5}): _process = process,_window = window,super._();
  

/// 目前仅 `mono`（Unity）。
@override final  String type;
 final  List<String> _process;
@override@JsonKey() List<String> get process {
  if (_process is EqualUnmodifiableListView) return _process;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_process);
}

 final  List<String> _window;
@override@JsonKey() List<String> get window {
  if (_window is EqualUnmodifiableListView) return _window;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_window);
}

/// 文件名，如 `AstralRaftNet.dll`。安装后在 `native/<gameId>/`。
@override@JsonKey() final  String dll;
@override@JsonKey() final  String namespace;
@override@JsonKey() final  String className;
@override@JsonKey() final  String method;
/// 首次发现进程后等待多少秒再注入，避免游戏未完全启动就注入导致崩溃。
@override@JsonKey() final  int delaySeconds;

/// Create a copy of GameAssistInjectConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameAssistInjectConfigCopyWith<_GameAssistInjectConfig> get copyWith => __$GameAssistInjectConfigCopyWithImpl<_GameAssistInjectConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameAssistInjectConfig&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other._process, _process)&&const DeepCollectionEquality().equals(other._window, _window)&&(identical(other.dll, dll) || other.dll == dll)&&(identical(other.namespace, namespace) || other.namespace == namespace)&&(identical(other.className, className) || other.className == className)&&(identical(other.method, method) || other.method == method)&&(identical(other.delaySeconds, delaySeconds) || other.delaySeconds == delaySeconds));
}


@override
int get hashCode => Object.hash(runtimeType,type,const DeepCollectionEquality().hash(_process),const DeepCollectionEquality().hash(_window),dll,namespace,className,method,delaySeconds);

@override
String toString() {
  return 'GameAssistInjectConfig(type: $type, process: $process, window: $window, dll: $dll, namespace: $namespace, className: $className, method: $method, delaySeconds: $delaySeconds)';
}


}

/// @nodoc
abstract mixin class _$GameAssistInjectConfigCopyWith<$Res> implements $GameAssistInjectConfigCopyWith<$Res> {
  factory _$GameAssistInjectConfigCopyWith(_GameAssistInjectConfig value, $Res Function(_GameAssistInjectConfig) _then) = __$GameAssistInjectConfigCopyWithImpl;
@override @useResult
$Res call({
 String type, List<String> process, List<String> window, String dll, String namespace, String className, String method, int delaySeconds
});




}
/// @nodoc
class __$GameAssistInjectConfigCopyWithImpl<$Res>
    implements _$GameAssistInjectConfigCopyWith<$Res> {
  __$GameAssistInjectConfigCopyWithImpl(this._self, this._then);

  final _GameAssistInjectConfig _self;
  final $Res Function(_GameAssistInjectConfig) _then;

/// Create a copy of GameAssistInjectConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? process = null,Object? window = null,Object? dll = null,Object? namespace = null,Object? className = null,Object? method = null,Object? delaySeconds = null,}) {
  return _then(_GameAssistInjectConfig(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,process: null == process ? _self._process : process // ignore: cast_nullable_to_non_nullable
as List<String>,window: null == window ? _self._window : window // ignore: cast_nullable_to_non_nullable
as List<String>,dll: null == dll ? _self.dll : dll // ignore: cast_nullable_to_non_nullable
as String,namespace: null == namespace ? _self.namespace : namespace // ignore: cast_nullable_to_non_nullable
as String,className: null == className ? _self.className : className // ignore: cast_nullable_to_non_nullable
as String,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,delaySeconds: null == delaySeconds ? _self.delaySeconds : delaySeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$GameAssistMagicWallConfig {

 bool get enabled;/// 每个 exe 一套规则。
 List<GameAssistMagicWallExe> get targets;
/// Create a copy of GameAssistMagicWallConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameAssistMagicWallConfigCopyWith<GameAssistMagicWallConfig> get copyWith => _$GameAssistMagicWallConfigCopyWithImpl<GameAssistMagicWallConfig>(this as GameAssistMagicWallConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameAssistMagicWallConfig&&(identical(other.enabled, enabled) || other.enabled == enabled)&&const DeepCollectionEquality().equals(other.targets, targets));
}


@override
int get hashCode => Object.hash(runtimeType,enabled,const DeepCollectionEquality().hash(targets));

@override
String toString() {
  return 'GameAssistMagicWallConfig(enabled: $enabled, targets: $targets)';
}


}

/// @nodoc
abstract mixin class $GameAssistMagicWallConfigCopyWith<$Res>  {
  factory $GameAssistMagicWallConfigCopyWith(GameAssistMagicWallConfig value, $Res Function(GameAssistMagicWallConfig) _then) = _$GameAssistMagicWallConfigCopyWithImpl;
@useResult
$Res call({
 bool enabled, List<GameAssistMagicWallExe> targets
});




}
/// @nodoc
class _$GameAssistMagicWallConfigCopyWithImpl<$Res>
    implements $GameAssistMagicWallConfigCopyWith<$Res> {
  _$GameAssistMagicWallConfigCopyWithImpl(this._self, this._then);

  final GameAssistMagicWallConfig _self;
  final $Res Function(GameAssistMagicWallConfig) _then;

/// Create a copy of GameAssistMagicWallConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? enabled = null,Object? targets = null,}) {
  return _then(_self.copyWith(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,targets: null == targets ? _self.targets : targets // ignore: cast_nullable_to_non_nullable
as List<GameAssistMagicWallExe>,
  ));
}

}


/// Adds pattern-matching-related methods to [GameAssistMagicWallConfig].
extension GameAssistMagicWallConfigPatterns on GameAssistMagicWallConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameAssistMagicWallConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameAssistMagicWallConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameAssistMagicWallConfig value)  $default,){
final _that = this;
switch (_that) {
case _GameAssistMagicWallConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameAssistMagicWallConfig value)?  $default,){
final _that = this;
switch (_that) {
case _GameAssistMagicWallConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool enabled,  List<GameAssistMagicWallExe> targets)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameAssistMagicWallConfig() when $default != null:
return $default(_that.enabled,_that.targets);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool enabled,  List<GameAssistMagicWallExe> targets)  $default,) {final _that = this;
switch (_that) {
case _GameAssistMagicWallConfig():
return $default(_that.enabled,_that.targets);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool enabled,  List<GameAssistMagicWallExe> targets)?  $default,) {final _that = this;
switch (_that) {
case _GameAssistMagicWallConfig() when $default != null:
return $default(_that.enabled,_that.targets);case _:
  return null;

}
}

}

/// @nodoc


class _GameAssistMagicWallConfig extends GameAssistMagicWallConfig {
  const _GameAssistMagicWallConfig({this.enabled = false, final  List<GameAssistMagicWallExe> targets = const []}): _targets = targets,super._();
  

@override@JsonKey() final  bool enabled;
/// 每个 exe 一套规则。
 final  List<GameAssistMagicWallExe> _targets;
/// 每个 exe 一套规则。
@override@JsonKey() List<GameAssistMagicWallExe> get targets {
  if (_targets is EqualUnmodifiableListView) return _targets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_targets);
}


/// Create a copy of GameAssistMagicWallConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameAssistMagicWallConfigCopyWith<_GameAssistMagicWallConfig> get copyWith => __$GameAssistMagicWallConfigCopyWithImpl<_GameAssistMagicWallConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameAssistMagicWallConfig&&(identical(other.enabled, enabled) || other.enabled == enabled)&&const DeepCollectionEquality().equals(other._targets, _targets));
}


@override
int get hashCode => Object.hash(runtimeType,enabled,const DeepCollectionEquality().hash(_targets));

@override
String toString() {
  return 'GameAssistMagicWallConfig(enabled: $enabled, targets: $targets)';
}


}

/// @nodoc
abstract mixin class _$GameAssistMagicWallConfigCopyWith<$Res> implements $GameAssistMagicWallConfigCopyWith<$Res> {
  factory _$GameAssistMagicWallConfigCopyWith(_GameAssistMagicWallConfig value, $Res Function(_GameAssistMagicWallConfig) _then) = __$GameAssistMagicWallConfigCopyWithImpl;
@override @useResult
$Res call({
 bool enabled, List<GameAssistMagicWallExe> targets
});




}
/// @nodoc
class __$GameAssistMagicWallConfigCopyWithImpl<$Res>
    implements _$GameAssistMagicWallConfigCopyWith<$Res> {
  __$GameAssistMagicWallConfigCopyWithImpl(this._self, this._then);

  final _GameAssistMagicWallConfig _self;
  final $Res Function(_GameAssistMagicWallConfig) _then;

/// Create a copy of GameAssistMagicWallConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? enabled = null,Object? targets = null,}) {
  return _then(_GameAssistMagicWallConfig(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,targets: null == targets ? _self._targets : targets // ignore: cast_nullable_to_non_nullable
as List<GameAssistMagicWallExe>,
  ));
}


}

/// @nodoc
mixin _$GameAssistMagicWallExe {

 String get process; List<GameAssistMagicWallRule> get rules;
/// Create a copy of GameAssistMagicWallExe
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameAssistMagicWallExeCopyWith<GameAssistMagicWallExe> get copyWith => _$GameAssistMagicWallExeCopyWithImpl<GameAssistMagicWallExe>(this as GameAssistMagicWallExe, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameAssistMagicWallExe&&(identical(other.process, process) || other.process == process)&&const DeepCollectionEquality().equals(other.rules, rules));
}


@override
int get hashCode => Object.hash(runtimeType,process,const DeepCollectionEquality().hash(rules));

@override
String toString() {
  return 'GameAssistMagicWallExe(process: $process, rules: $rules)';
}


}

/// @nodoc
abstract mixin class $GameAssistMagicWallExeCopyWith<$Res>  {
  factory $GameAssistMagicWallExeCopyWith(GameAssistMagicWallExe value, $Res Function(GameAssistMagicWallExe) _then) = _$GameAssistMagicWallExeCopyWithImpl;
@useResult
$Res call({
 String process, List<GameAssistMagicWallRule> rules
});




}
/// @nodoc
class _$GameAssistMagicWallExeCopyWithImpl<$Res>
    implements $GameAssistMagicWallExeCopyWith<$Res> {
  _$GameAssistMagicWallExeCopyWithImpl(this._self, this._then);

  final GameAssistMagicWallExe _self;
  final $Res Function(GameAssistMagicWallExe) _then;

/// Create a copy of GameAssistMagicWallExe
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? process = null,Object? rules = null,}) {
  return _then(_self.copyWith(
process: null == process ? _self.process : process // ignore: cast_nullable_to_non_nullable
as String,rules: null == rules ? _self.rules : rules // ignore: cast_nullable_to_non_nullable
as List<GameAssistMagicWallRule>,
  ));
}

}


/// Adds pattern-matching-related methods to [GameAssistMagicWallExe].
extension GameAssistMagicWallExePatterns on GameAssistMagicWallExe {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameAssistMagicWallExe value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameAssistMagicWallExe() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameAssistMagicWallExe value)  $default,){
final _that = this;
switch (_that) {
case _GameAssistMagicWallExe():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameAssistMagicWallExe value)?  $default,){
final _that = this;
switch (_that) {
case _GameAssistMagicWallExe() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String process,  List<GameAssistMagicWallRule> rules)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameAssistMagicWallExe() when $default != null:
return $default(_that.process,_that.rules);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String process,  List<GameAssistMagicWallRule> rules)  $default,) {final _that = this;
switch (_that) {
case _GameAssistMagicWallExe():
return $default(_that.process,_that.rules);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String process,  List<GameAssistMagicWallRule> rules)?  $default,) {final _that = this;
switch (_that) {
case _GameAssistMagicWallExe() when $default != null:
return $default(_that.process,_that.rules);case _:
  return null;

}
}

}

/// @nodoc


class _GameAssistMagicWallExe extends GameAssistMagicWallExe {
  const _GameAssistMagicWallExe({required this.process, final  List<GameAssistMagicWallRule> rules = const []}): _rules = rules,super._();
  

@override final  String process;
 final  List<GameAssistMagicWallRule> _rules;
@override@JsonKey() List<GameAssistMagicWallRule> get rules {
  if (_rules is EqualUnmodifiableListView) return _rules;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rules);
}


/// Create a copy of GameAssistMagicWallExe
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameAssistMagicWallExeCopyWith<_GameAssistMagicWallExe> get copyWith => __$GameAssistMagicWallExeCopyWithImpl<_GameAssistMagicWallExe>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameAssistMagicWallExe&&(identical(other.process, process) || other.process == process)&&const DeepCollectionEquality().equals(other._rules, _rules));
}


@override
int get hashCode => Object.hash(runtimeType,process,const DeepCollectionEquality().hash(_rules));

@override
String toString() {
  return 'GameAssistMagicWallExe(process: $process, rules: $rules)';
}


}

/// @nodoc
abstract mixin class _$GameAssistMagicWallExeCopyWith<$Res> implements $GameAssistMagicWallExeCopyWith<$Res> {
  factory _$GameAssistMagicWallExeCopyWith(_GameAssistMagicWallExe value, $Res Function(_GameAssistMagicWallExe) _then) = __$GameAssistMagicWallExeCopyWithImpl;
@override @useResult
$Res call({
 String process, List<GameAssistMagicWallRule> rules
});




}
/// @nodoc
class __$GameAssistMagicWallExeCopyWithImpl<$Res>
    implements _$GameAssistMagicWallExeCopyWith<$Res> {
  __$GameAssistMagicWallExeCopyWithImpl(this._self, this._then);

  final _GameAssistMagicWallExe _self;
  final $Res Function(_GameAssistMagicWallExe) _then;

/// Create a copy of GameAssistMagicWallExe
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? process = null,Object? rules = null,}) {
  return _then(_GameAssistMagicWallExe(
process: null == process ? _self.process : process // ignore: cast_nullable_to_non_nullable
as String,rules: null == rules ? _self._rules : rules // ignore: cast_nullable_to_non_nullable
as List<GameAssistMagicWallRule>,
  ));
}


}

/// @nodoc
mixin _$GameAssistMagicWallRule {

 String get id; String get name; bool get enabled; String get action; String get protocol; String get direction; String? get remoteIp; String? get localIp; String? get remotePort; String? get localPort; String? get description;
/// Create a copy of GameAssistMagicWallRule
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameAssistMagicWallRuleCopyWith<GameAssistMagicWallRule> get copyWith => _$GameAssistMagicWallRuleCopyWithImpl<GameAssistMagicWallRule>(this as GameAssistMagicWallRule, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameAssistMagicWallRule&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.action, action) || other.action == action)&&(identical(other.protocol, protocol) || other.protocol == protocol)&&(identical(other.direction, direction) || other.direction == direction)&&(identical(other.remoteIp, remoteIp) || other.remoteIp == remoteIp)&&(identical(other.localIp, localIp) || other.localIp == localIp)&&(identical(other.remotePort, remotePort) || other.remotePort == remotePort)&&(identical(other.localPort, localPort) || other.localPort == localPort)&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,enabled,action,protocol,direction,remoteIp,localIp,remotePort,localPort,description);

@override
String toString() {
  return 'GameAssistMagicWallRule(id: $id, name: $name, enabled: $enabled, action: $action, protocol: $protocol, direction: $direction, remoteIp: $remoteIp, localIp: $localIp, remotePort: $remotePort, localPort: $localPort, description: $description)';
}


}

/// @nodoc
abstract mixin class $GameAssistMagicWallRuleCopyWith<$Res>  {
  factory $GameAssistMagicWallRuleCopyWith(GameAssistMagicWallRule value, $Res Function(GameAssistMagicWallRule) _then) = _$GameAssistMagicWallRuleCopyWithImpl;
@useResult
$Res call({
 String id, String name, bool enabled, String action, String protocol, String direction, String? remoteIp, String? localIp, String? remotePort, String? localPort, String? description
});




}
/// @nodoc
class _$GameAssistMagicWallRuleCopyWithImpl<$Res>
    implements $GameAssistMagicWallRuleCopyWith<$Res> {
  _$GameAssistMagicWallRuleCopyWithImpl(this._self, this._then);

  final GameAssistMagicWallRule _self;
  final $Res Function(GameAssistMagicWallRule) _then;

/// Create a copy of GameAssistMagicWallRule
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? enabled = null,Object? action = null,Object? protocol = null,Object? direction = null,Object? remoteIp = freezed,Object? localIp = freezed,Object? remotePort = freezed,Object? localPort = freezed,Object? description = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as String,remoteIp: freezed == remoteIp ? _self.remoteIp : remoteIp // ignore: cast_nullable_to_non_nullable
as String?,localIp: freezed == localIp ? _self.localIp : localIp // ignore: cast_nullable_to_non_nullable
as String?,remotePort: freezed == remotePort ? _self.remotePort : remotePort // ignore: cast_nullable_to_non_nullable
as String?,localPort: freezed == localPort ? _self.localPort : localPort // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [GameAssistMagicWallRule].
extension GameAssistMagicWallRulePatterns on GameAssistMagicWallRule {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameAssistMagicWallRule value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameAssistMagicWallRule() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameAssistMagicWallRule value)  $default,){
final _that = this;
switch (_that) {
case _GameAssistMagicWallRule():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameAssistMagicWallRule value)?  $default,){
final _that = this;
switch (_that) {
case _GameAssistMagicWallRule() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  bool enabled,  String action,  String protocol,  String direction,  String? remoteIp,  String? localIp,  String? remotePort,  String? localPort,  String? description)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameAssistMagicWallRule() when $default != null:
return $default(_that.id,_that.name,_that.enabled,_that.action,_that.protocol,_that.direction,_that.remoteIp,_that.localIp,_that.remotePort,_that.localPort,_that.description);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  bool enabled,  String action,  String protocol,  String direction,  String? remoteIp,  String? localIp,  String? remotePort,  String? localPort,  String? description)  $default,) {final _that = this;
switch (_that) {
case _GameAssistMagicWallRule():
return $default(_that.id,_that.name,_that.enabled,_that.action,_that.protocol,_that.direction,_that.remoteIp,_that.localIp,_that.remotePort,_that.localPort,_that.description);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  bool enabled,  String action,  String protocol,  String direction,  String? remoteIp,  String? localIp,  String? remotePort,  String? localPort,  String? description)?  $default,) {final _that = this;
switch (_that) {
case _GameAssistMagicWallRule() when $default != null:
return $default(_that.id,_that.name,_that.enabled,_that.action,_that.protocol,_that.direction,_that.remoteIp,_that.localIp,_that.remotePort,_that.localPort,_that.description);case _:
  return null;

}
}

}

/// @nodoc


class _GameAssistMagicWallRule extends GameAssistMagicWallRule {
  const _GameAssistMagicWallRule({this.id = '', this.name = 'allow', this.enabled = true, this.action = 'allow', this.protocol = 'both', this.direction = 'both', this.remoteIp, this.localIp, this.remotePort, this.localPort, this.description}): super._();
  

@override@JsonKey() final  String id;
@override@JsonKey() final  String name;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  String action;
@override@JsonKey() final  String protocol;
@override@JsonKey() final  String direction;
@override final  String? remoteIp;
@override final  String? localIp;
@override final  String? remotePort;
@override final  String? localPort;
@override final  String? description;

/// Create a copy of GameAssistMagicWallRule
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameAssistMagicWallRuleCopyWith<_GameAssistMagicWallRule> get copyWith => __$GameAssistMagicWallRuleCopyWithImpl<_GameAssistMagicWallRule>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameAssistMagicWallRule&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.action, action) || other.action == action)&&(identical(other.protocol, protocol) || other.protocol == protocol)&&(identical(other.direction, direction) || other.direction == direction)&&(identical(other.remoteIp, remoteIp) || other.remoteIp == remoteIp)&&(identical(other.localIp, localIp) || other.localIp == localIp)&&(identical(other.remotePort, remotePort) || other.remotePort == remotePort)&&(identical(other.localPort, localPort) || other.localPort == localPort)&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,enabled,action,protocol,direction,remoteIp,localIp,remotePort,localPort,description);

@override
String toString() {
  return 'GameAssistMagicWallRule(id: $id, name: $name, enabled: $enabled, action: $action, protocol: $protocol, direction: $direction, remoteIp: $remoteIp, localIp: $localIp, remotePort: $remotePort, localPort: $localPort, description: $description)';
}


}

/// @nodoc
abstract mixin class _$GameAssistMagicWallRuleCopyWith<$Res> implements $GameAssistMagicWallRuleCopyWith<$Res> {
  factory _$GameAssistMagicWallRuleCopyWith(_GameAssistMagicWallRule value, $Res Function(_GameAssistMagicWallRule) _then) = __$GameAssistMagicWallRuleCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, bool enabled, String action, String protocol, String direction, String? remoteIp, String? localIp, String? remotePort, String? localPort, String? description
});




}
/// @nodoc
class __$GameAssistMagicWallRuleCopyWithImpl<$Res>
    implements _$GameAssistMagicWallRuleCopyWith<$Res> {
  __$GameAssistMagicWallRuleCopyWithImpl(this._self, this._then);

  final _GameAssistMagicWallRule _self;
  final $Res Function(_GameAssistMagicWallRule) _then;

/// Create a copy of GameAssistMagicWallRule
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? enabled = null,Object? action = null,Object? protocol = null,Object? direction = null,Object? remoteIp = freezed,Object? localIp = freezed,Object? remotePort = freezed,Object? localPort = freezed,Object? description = freezed,}) {
  return _then(_GameAssistMagicWallRule(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as String,remoteIp: freezed == remoteIp ? _self.remoteIp : remoteIp // ignore: cast_nullable_to_non_nullable
as String?,localIp: freezed == localIp ? _self.localIp : localIp // ignore: cast_nullable_to_non_nullable
as String?,remotePort: freezed == remotePort ? _self.remotePort : remotePort // ignore: cast_nullable_to_non_nullable
as String?,localPort: freezed == localPort ? _self.localPort : localPort // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$GameAssistForwardRule {

 String get listen; String get target; String get proto;/// 仅房主启动该转发。
 bool get hostOnly;
/// Create a copy of GameAssistForwardRule
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameAssistForwardRuleCopyWith<GameAssistForwardRule> get copyWith => _$GameAssistForwardRuleCopyWithImpl<GameAssistForwardRule>(this as GameAssistForwardRule, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameAssistForwardRule&&(identical(other.listen, listen) || other.listen == listen)&&(identical(other.target, target) || other.target == target)&&(identical(other.proto, proto) || other.proto == proto)&&(identical(other.hostOnly, hostOnly) || other.hostOnly == hostOnly));
}


@override
int get hashCode => Object.hash(runtimeType,listen,target,proto,hostOnly);

@override
String toString() {
  return 'GameAssistForwardRule(listen: $listen, target: $target, proto: $proto, hostOnly: $hostOnly)';
}


}

/// @nodoc
abstract mixin class $GameAssistForwardRuleCopyWith<$Res>  {
  factory $GameAssistForwardRuleCopyWith(GameAssistForwardRule value, $Res Function(GameAssistForwardRule) _then) = _$GameAssistForwardRuleCopyWithImpl;
@useResult
$Res call({
 String listen, String target, String proto, bool hostOnly
});




}
/// @nodoc
class _$GameAssistForwardRuleCopyWithImpl<$Res>
    implements $GameAssistForwardRuleCopyWith<$Res> {
  _$GameAssistForwardRuleCopyWithImpl(this._self, this._then);

  final GameAssistForwardRule _self;
  final $Res Function(GameAssistForwardRule) _then;

/// Create a copy of GameAssistForwardRule
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listen = null,Object? target = null,Object? proto = null,Object? hostOnly = null,}) {
  return _then(_self.copyWith(
listen: null == listen ? _self.listen : listen // ignore: cast_nullable_to_non_nullable
as String,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as String,proto: null == proto ? _self.proto : proto // ignore: cast_nullable_to_non_nullable
as String,hostOnly: null == hostOnly ? _self.hostOnly : hostOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [GameAssistForwardRule].
extension GameAssistForwardRulePatterns on GameAssistForwardRule {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameAssistForwardRule value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameAssistForwardRule() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameAssistForwardRule value)  $default,){
final _that = this;
switch (_that) {
case _GameAssistForwardRule():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameAssistForwardRule value)?  $default,){
final _that = this;
switch (_that) {
case _GameAssistForwardRule() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String listen,  String target,  String proto,  bool hostOnly)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameAssistForwardRule() when $default != null:
return $default(_that.listen,_that.target,_that.proto,_that.hostOnly);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String listen,  String target,  String proto,  bool hostOnly)  $default,) {final _that = this;
switch (_that) {
case _GameAssistForwardRule():
return $default(_that.listen,_that.target,_that.proto,_that.hostOnly);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String listen,  String target,  String proto,  bool hostOnly)?  $default,) {final _that = this;
switch (_that) {
case _GameAssistForwardRule() when $default != null:
return $default(_that.listen,_that.target,_that.proto,_that.hostOnly);case _:
  return null;

}
}

}

/// @nodoc


class _GameAssistForwardRule extends GameAssistForwardRule {
  const _GameAssistForwardRule({required this.listen, required this.target, this.proto = 'tcp', this.hostOnly = true}): super._();
  

@override final  String listen;
@override final  String target;
@override@JsonKey() final  String proto;
/// 仅房主启动该转发。
@override@JsonKey() final  bool hostOnly;

/// Create a copy of GameAssistForwardRule
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameAssistForwardRuleCopyWith<_GameAssistForwardRule> get copyWith => __$GameAssistForwardRuleCopyWithImpl<_GameAssistForwardRule>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameAssistForwardRule&&(identical(other.listen, listen) || other.listen == listen)&&(identical(other.target, target) || other.target == target)&&(identical(other.proto, proto) || other.proto == proto)&&(identical(other.hostOnly, hostOnly) || other.hostOnly == hostOnly));
}


@override
int get hashCode => Object.hash(runtimeType,listen,target,proto,hostOnly);

@override
String toString() {
  return 'GameAssistForwardRule(listen: $listen, target: $target, proto: $proto, hostOnly: $hostOnly)';
}


}

/// @nodoc
abstract mixin class _$GameAssistForwardRuleCopyWith<$Res> implements $GameAssistForwardRuleCopyWith<$Res> {
  factory _$GameAssistForwardRuleCopyWith(_GameAssistForwardRule value, $Res Function(_GameAssistForwardRule) _then) = __$GameAssistForwardRuleCopyWithImpl;
@override @useResult
$Res call({
 String listen, String target, String proto, bool hostOnly
});




}
/// @nodoc
class __$GameAssistForwardRuleCopyWithImpl<$Res>
    implements _$GameAssistForwardRuleCopyWith<$Res> {
  __$GameAssistForwardRuleCopyWithImpl(this._self, this._then);

  final _GameAssistForwardRule _self;
  final $Res Function(_GameAssistForwardRule) _then;

/// Create a copy of GameAssistForwardRule
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listen = null,Object? target = null,Object? proto = null,Object? hostOnly = null,}) {
  return _then(_GameAssistForwardRule(
listen: null == listen ? _self.listen : listen // ignore: cast_nullable_to_non_nullable
as String,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as String,proto: null == proto ? _self.proto : proto // ignore: cast_nullable_to_non_nullable
as String,hostOnly: null == hostOnly ? _self.hostOnly : hostOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
