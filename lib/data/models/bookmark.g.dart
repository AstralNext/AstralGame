// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmark.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Bookmark _$BookmarkFromJson(Map<String, dynamic> json) => _Bookmark(
  id: (json['id'] as num).toInt(),
  customName: json['customName'] as String,
  payload: RoomInvitePayload.fromJson(json['payload'] as Map<String, dynamic>),
  savedAt: DateTime.parse(json['savedAt'] as String),
  lastUsedAt: json['lastUsedAt'] == null
      ? null
      : DateTime.parse(json['lastUsedAt'] as String),
  pinned: json['pinned'] as bool? ?? false,
);
