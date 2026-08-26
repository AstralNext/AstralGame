import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

Future<void> copyJoinInvite(BuildContext context, String url) async {
final t = url.trim();
if (t.isEmpty) return;
await Clipboard.setData(ClipboardData(text: t));
if (!context.mounted) return;
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('邀请链接已复制')),
);
}

/// 手机走系统分享；桌面优先系统分享，失败则复制链接。
Future<void> shareJoinInvite({
required BuildContext context,
required String url,
String? gameName,
}) async {
if (url.trim().isEmpty) return;
final name = (gameName ?? '').trim();
final text = joinShareMessage(url, gameName: name);
try {
await Share.share(
text,
subject: name.isEmpty ? 'Astral Game' : name,
);
} catch (e) {
      appLogger.w('[ShareActions] 操作失败', error: e);
await copyJoinInvite(context, url);

    }
}
