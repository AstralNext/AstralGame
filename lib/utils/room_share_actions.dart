import 'package:astral_game/ui/widgets/app_snack_bar.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

Future<void> copyJoinInvite(BuildContext context, String url) async {
  final t = url.trim();
  if (t.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: t));
  if (!context.mounted) return;
  showAppSnackBar(context, '邀请链接已复制');
}

/// Android 调系统分享；其余平台直接复制邀请链接（复制失败时仅记日志）。
Future<void> shareJoinInvite({
  required BuildContext context,
  required String url,
  String? gameName,
}) async {
  if (url.trim().isEmpty) return;
  if (RuntimePlatform.isAndroid) {
    final name = (gameName ?? '').trim();
    final text = joinShareMessage(url, gameName: name);
    try {
      await Share.share(text, subject: name.isEmpty ? 'Astral Game' : name);
      return;
    } catch (e) {
      appLogger.w('[ShareActions] 系统分享失败，回退为复制', error: e);
    }
  }
  if (!context.mounted) return;
  await copyJoinInvite(context, url);
}
