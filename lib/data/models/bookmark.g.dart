// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmark.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Bookmark _$BookmarkFromJson(Map<String, dynamic> json) => _Bookmark(
  id: (json['id'] as num).toInt(),
  customName: json['customName'] as String,
  payload: RoomInvitePayload.fromJson(json['payload'] as Map<String, dynamic>),
  originalShortCode: json['originalShortCode'] as String?,
  originalOfflineToken: json['originalOfflineToken'] as String?,
  savedAt: DateTime.parse(json['savedAt'] as String),
  lastUsedAt: json['lastUsedAt'] == null
      ? null
      : DateTime.parse(json['lastUsedAt'] as String),
  pinned: json['pinned'] as bool? ?? false,
);

Map<String, dynamic> _$BookmarkToJson(_Bookmark instance) => <String, dynamic>{
  'id': instance.id,
  'customName': instance.customName,
  'payload': instance.payload.toJson(),
  'originalShortCode': instance.originalShortCode,
  'originalOfflineToken': instance.originalOfflineToken,
  'savedAt': instance.savedAt.toIso8601String(),
  'lastUsedAt': instance.lastUsedAt?.toIso8601String(),
  'pinned': instance.pinned,
};
