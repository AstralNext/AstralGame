import 'package:astral_game/utils/room_share_actions.dart';
import 'package:flutter/material.dart';

/// 「分享房间」弹窗：展示邀请链接，标题栏带「收藏当前房间」星标，底部「分享」。
Future<void> showShareRoomDialog(
  BuildContext context, {
  required String url,
  required bool viaShort,
  required String gameName,
  required VoidCallback onBookmark,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('分享房间')),
          IconButton(
            tooltip: '⭐ 收藏当前房间',
            onPressed: () {
              Navigator.pop(dialogContext);
              onBookmark();
            },
            icon: Icon(
              Icons.bookmark_border_rounded,
              color: Theme.of(dialogContext).colorScheme.primary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              viaShort
                  ? '发给好友这条链接即可加入。短码服务不可用时会自动改用离线链接。'
                  : '短码服务不可用，已生成离线邀请链接。好友点开即可加入。',
            ),
            const SizedBox(height: 16),
            SelectableText(
              url.isNotEmpty ? url : '（无法生成邀请）',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: url.isEmpty
              ? null
              : () async {
                  Navigator.pop(dialogContext);
                  if (!context.mounted) return;
                  await shareJoinInvite(
                    context: context,
                    url: url,
                    gameName: gameName,
                  );
                },
          child: const Text('分享'),
        ),
      ],
    ),
  );
}
