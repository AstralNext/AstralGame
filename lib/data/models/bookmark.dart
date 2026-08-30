import 'dart:convert';

import 'package:astral_game/data/models/active_room_session.dart';
import 'package:crypto/crypto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'bookmark.freezed.dart';
part 'bookmark.g.dart';

/// 本地收藏的房间：完整保存 [RoomInvitePayload]，加入时无需再查短码服务。
///
/// 仅用户主动触发「⭐ 收藏」写入；不再有"加入历史"这套自动写入机制。
@freezed
@JsonSerializable(explicitToJson: true)
abstract class Bookmark with _$Bookmark {
  const Bookmark._();

  const factory Bookmark({
    required final int id,
    required final String customName,
    required final RoomInvitePayload payload,
    final String? originalShortCode,
    final String? originalOfflineToken,
    required final DateTime savedAt,
    final DateTime? lastUsedAt,
    @Default(false) final bool pinned,
  }) = _Bookmark;

  factory Bookmark.fromJson(Map<String, dynamic> json) =>
      _$BookmarkFromJson(json);

  /// 搜索字段合并（小写化后匹配）。
  String get searchHaystack {
    final buf = StringBuffer();
    buf.write(customName.toLowerCase());
    buf.write(' ');
    buf.write(payload.gameName.toLowerCase());
    buf.write(' ');
    buf.write((payload.displayName ?? '').toLowerCase());
    buf.write(' ');
    buf.write((originalShortCode ?? '').toLowerCase());
    buf.write(' ');
    buf.write(payload.gameId.toLowerCase());
    return buf.toString();
  }

  /// 排序时间基准：最近用过优先，否则按收藏时间。
  DateTime get sortKey => lastUsedAt ?? savedAt;

  /// 展示名：customName 优先，fallback 到游戏名，再 fallback 到网络名。
  String get displayName {
    if (customName.trim().isNotEmpty) return customName.trim();
    if (payload.gameName.trim().isNotEmpty) return payload.gameName.trim();
    return payload.networkName;
  }

  /// 收藏时无短码（如：从离线邀请直接收藏），也能给一个可展示的"标识"。
  String get codeLabel =>
      originalShortCode?.isNotEmpty == true ? originalShortCode! : '离线';

  /// 这条收藏对应的 payload 内容哈希（gameName + networkName + networkSecret + peers 有序列表）。
  ///
  /// 用于 UI 判断"当前房间是否已收藏"——同一个房间不管谁的机器上、不管用户有没有改过
  /// customName / pinned，payload 内容哈希都一样。
  String get contentHash => hashInviteContent(payload);

  /// 与给定 payload 做内容级比对（哈希一致即视为同一个房间）。
  bool matchesPayload(RoomInvitePayload other) =>
      contentHash == hashInviteContent(other);
}

/// 对 [RoomInvitePayload] 做 SHA-256 哈希。
///
/// 参与哈希的字段：gameName / networkName / networkSecret / peers.uri（先排序保证稳定）。
/// 不参与：customName / displayName / originalShortCode / pinned / savedAt 等"皮肤"字段。
String hashInviteContent(RoomInvitePayload p) {
  final sortedPeers = (p.peers.map((e) => e.uri).toList()..sort())
      .join('|');
  final input = [
    p.gameId,
    p.gameName,
    p.networkName,
    p.networkSecret,
    sortedPeers,
  ].join('\u0001');
  final bytes = utf8.encode(input);
  final digest = sha256.convert(bytes);
  // 取前 16 字节 → 32 hex 字符，足够碰撞忽略不计
  return digest.toString().substring(0, 32);
}
