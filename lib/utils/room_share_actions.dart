import 'package:astral_game/utils/room_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// 手机走系统分享；桌面优先系统分享，失败则复制链接。
Future<void> shareJoinInvite({
  required BuildContext context,
  required String url,
  String? gameName,
}) async {
  if (url.trim().isEmpty) return;
  final text = joinShareMessage(url, gameName: gameName);
  try {
    await Share.share(text, subject: (gameName ?? '').trim().isEmpty
        ? 'Astral Game'
        : gameName!.trim());
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('邀请链接已复制')),
    );
  }
}
