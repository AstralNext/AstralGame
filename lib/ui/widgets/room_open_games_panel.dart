import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/models/lan_relay_status.dart';
import 'package:astral_game/data/models/open_game_listing.dart';
import 'package:astral_game/data/services/open_games_service.dart';
import 'package:astral_game/di.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

/// 房间右侧下方：经 ET 同步的「开放游戏」列表（含自己）。
class RoomOpenGamesPanel extends StatelessWidget {
  const RoomOpenGamesPanel({
    super.key,
    required this.gameId,
    this.compact = false,
  });

  final String? gameId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final game = GameCatalog.byId(gameId);
    final openGames = getIt<OpenGamesService>();

    return Watch((context) {
      final entries = openGames.listings.value;
      final showRelay = OpenGamesService.lanAssistEnabled;
      final relays = showRelay ? openGames.relayStatuses.value : const {};
      final active = openGames.isActive;

      if (!active && entries.isEmpty) {
        return const SizedBox.shrink();
      }

      return DecoratedBox(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(compact ? 16 : 20),
          border: Border.all(color: palette.divider.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 16,
            compact ? 12 : 14,
            compact ? 10 : 12,
            compact ? 10 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (game != null) ...[
                    GameLogo(game: game, size: 22),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      '开放游戏',
                      style: textTheme.titleSmall?.copyWith(
                        color: palette.accent,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Text(
                    '${entries.length}',
                    style: textTheme.labelSmall?.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (compact && entries.isEmpty)
                Text(
                  '等待虚拟 IP / 同伴宣告…',
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textTertiary,
                  ),
                )
              else
                Expanded(
                  child: entries.isEmpty
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            '等待虚拟 IP / 同伴宣告…',
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.textTertiary,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: palette.divider.withValues(alpha: 0.35),
                          ),
                          itemBuilder: (context, i) {
                            final e = entries[i];
                            return _OpenGameTile(
                              listing: e,
                              relay: showRelay ? relays[e.key] : null,
                              showAssist: showRelay,
                              onCopy: () => _copy(context, e),
                            );
                          },
                        ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _copy(BuildContext context, OpenGameListing listing) async {
    await Clipboard.setData(ClipboardData(text: listing.endpoint));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制${listing.label}：${listing.endpoint}')),
    );
  }
}

class _OpenGameTile extends StatelessWidget {
  const _OpenGameTile({
    required this.listing,
    this.relay,
    this.showAssist = false,
    required this.onCopy,
  });

  final OpenGameListing listing;
  final LanRelayStatus? relay;
  final bool showAssist;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final relaying = relay?.isActive == true;
    const liveColor = Color(0xFF22C55E);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAssist)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: relaying
                          ? liveColor
                          : palette.textTertiary.withValues(alpha: 0.35),
                      boxShadow: relaying
                          ? [
                              BoxShadow(
                                color: liveColor.withValues(alpha: 0.55),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.label,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (listing.isSelf)
                          _chip(
                            textTheme,
                            '我',
                            colorScheme.secondaryContainer,
                            colorScheme.onSecondaryContainer,
                          ),
                        // 不再显示"房主"标签
                        if (relaying)
                          _chip(
                            textTheme,
                            '本机转发',
                            liveColor.withValues(alpha: 0.18),
                            liveColor,
                          ),
                        Text(
                          listing.ownerName,
                          style: textTheme.labelSmall?.copyWith(
                            color: palette.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      listing.endpoint,
                      style: textTheme.labelMedium?.copyWith(
                        color: palette.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if ((listing.motd ?? '').trim().isNotEmpty &&
                        listing.motd!.trim() != listing.label.trim()) ...[
                      const SizedBox(height: 2),
                      Text(
                        listing.motd!.trim(),
                        style: textTheme.labelSmall?.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.copy_rounded,
                size: 18,
                color: palette.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(
    TextTheme textTheme,
    String label,
    Color bg,
    Color fg,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
