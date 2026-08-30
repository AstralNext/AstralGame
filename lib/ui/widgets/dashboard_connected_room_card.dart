import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 已连接房间卡：游戏封面、房间名、短码、IP、分享/收藏/离开按钮。
class ConnectedRoomCard extends StatelessWidget {
  const ConnectedRoomCard({
    super.key,
    required this.roomDisplayName,
    this.roomRoleLabel,
    this.roomGameId,
    this.roomShortCode,
    required this.isRoomHost,
    this.hostOnline = true,
    this.isLinking = false,
    this.virtualIp,
    required this.onShare,
    required this.onDisconnect,
    required this.onBookmark,
    this.isBookmarked = false,
  });

  final String roomDisplayName;
  final String? roomRoleLabel;
  final String? roomGameId;
  final String? roomShortCode;
  final bool isRoomHost;
  final bool hostOnline;
  final bool isLinking;
  final String? virtualIp;
  final VoidCallback onShare;
  final VoidCallback onDisconnect;
  final VoidCallback onBookmark;
  final bool isBookmarked;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final game = GameCatalog.byId(roomGameId);
    final code = roomShortCode?.trim() ?? '';
    final ip = virtualIp?.trim() ?? '';
    final showHostOffline = false; // 不再显示"房主离线"提示

    return AstralCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLinking) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: palette.accentMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '正在连接组网…短码可先分享给好友',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else if (showHostOffline) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: palette.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.wifi_off_rounded, size: 18, color: palette.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '房主已离线，可等待其恢复或自行离开',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (game != null)
                GameGridCover(game: game, width: 72, height: 108)
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: palette.accentMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.meeting_room, color: palette.accent),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomDisplayName,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      game?.displayName ?? '',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (ip.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        ip,
                        style: textTheme.labelSmall?.copyWith(
                          color: palette.textTertiary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    if (code.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              code,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '复制短码',
                            visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: code),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('已复制：$code')),
                                );
                              }
                            },
                            icon: Icon(
                              Icons.copy,
                              size: 18,
                              color: palette.accent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton(
                tooltip: isBookmarked ? '取消收藏' : '收藏当前房间',
                onPressed: onBookmark,
                icon: Icon(
                  isBookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: isBookmarked ? palette.accent : palette.accent,
                  fill: isBookmarked ? 1 : 0,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: onShare,
                  child: const Text('分享'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onDisconnect,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.error,
                    side: BorderSide(
                      color: palette.error.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Text('离开'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
