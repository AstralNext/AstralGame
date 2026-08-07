import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/alcy_wallpaper_service.dart';
import 'package:astral_game/data/services/hitokoto_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/utils/client_runtime_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 联机页：空闲为风景欢迎卡 + 底部信息 + FAB；已连接为房间卡。
class DashboardHomePanel extends StatelessWidget {
  const DashboardHomePanel({
    super.key,
    required this.isConnected,
    this.username,
    this.roomDisplayName,
    this.roomRoleLabel,
    this.roomGameId,
    this.roomShortCode,
    this.isRoomHost = false,
    this.hostOnline = true,
    this.pausedRoomName,
    this.virtualIp,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onShareRoom,
    required this.onDisconnect,
    this.onResumeHost,
  });

  final bool isConnected;
  final String? username;
  final String? roomDisplayName;
  final String? roomRoleLabel;
  final String? roomGameId;
  final String? roomShortCode;
  final bool isRoomHost;
  final bool hostOnline;
  final String? pausedRoomName;
  final String? virtualIp;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;
  final VoidCallback? onResumeHost;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: isConnected
          ? _ConnectedRoomCard(
              key: const ValueKey('connected'),
              roomDisplayName: roomDisplayName ?? '房间',
              roomRoleLabel: roomRoleLabel,
              roomGameId: roomGameId,
              roomShortCode: roomShortCode,
              isRoomHost: isRoomHost,
              hostOnline: hostOnline,
              virtualIp: virtualIp,
              onShare: onShareRoom,
              onDisconnect: onDisconnect,
            )
          : _IdleHome(
              key: const ValueKey('idle'),
              username: username?.trim().isNotEmpty == true
                  ? username!.trim()
                  : 'Player',
              pausedRoomName: pausedRoomName,
              onCreate: onCreateRoom,
              onJoin: onJoinRoom,
              onResumeHost: onResumeHost,
            ),
    );
  }
}

class _IdleHome extends StatelessWidget {
  const _IdleHome({
    super.key,
    required this.username,
    this.pausedRoomName,
    required this.onCreate,
    required this.onJoin,
    this.onResumeHost,
  });

  final String username;
  final String? pausedRoomName;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback? onResumeHost;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final version = ClientRuntimeInfo.appVersion;
    final os = ClientRuntimeInfo.operatingSystemVersion;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _DailySceneryCard(username: username),
            ),
            if (pausedRoomName != null &&
                pausedRoomName!.trim().isNotEmpty &&
                onResumeHost != null) ...[
              const SizedBox(height: 12),
              AstralCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '可重新开启',
                            style: textTheme.labelMedium?.copyWith(
                              color: palette.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pausedRoomName!,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '恢复后请把新短码发给好友',
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: onResumeHost,
                      child: const Text('重新开启'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'v$version',
              style: textTheme.labelMedium?.copyWith(
                color: palette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              os,
              style: textTheme.labelSmall?.copyWith(
                color: palette.textTertiary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // 给右下角胶囊按钮留空
            const SizedBox(height: 64),
          ],
        ),
        Positioned(
          right: 0,
          bottom: 4,
          child: _CreateJoinPill(
            onCreate: onCreate,
            onJoin: onJoin,
          ),
        ),
      ],
    );
  }
}

/// 右下角创建 / 加入一体胶囊。
class _CreateJoinPill extends StatelessWidget {
  const _CreateJoinPill({
    required this.onCreate,
    required this.onJoin,
  });

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;

    return Material(
      color: palette.card,
      elevation: 3,
      shadowColor: palette.shadowSoft,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: palette.accent,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                onTap: onCreate,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_circle_outline,
                        size: 18,
                        color: palette.onAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '创建',
                        style: TextStyle(
                          color: palette.onAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onJoin,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_add_alt_1_outlined,
                      size: 18,
                      color: palette.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '加入',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailySceneryCard extends StatefulWidget {
  const _DailySceneryCard({required this.username});

  final String username;

  @override
  State<_DailySceneryCard> createState() => _DailySceneryCardState();
}

class _DailySceneryCardState extends State<_DailySceneryCard> {
  static const _fallbackAsset = 'assets/scenery/daily.jpg';

  String _title = '';
  String _subtitle = '';
  String? _wallpaperUrl;
  bool _textLoading = true;
  bool _wallpaperRequested = false;

  @override
  void initState() {
    super.initState();
    _title = '欢迎，${widget.username}';
    _subtitle = '准备好开一局了吗？';
    _loadHitokoto();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_wallpaperRequested) {
      _wallpaperRequested = true;
      _loadWallpaper();
    }
  }

  Future<void> _loadHitokoto() async {
    try {
      final quote = await getIt<HitokotoService>().fetch();
      if (!mounted) return;
      setState(() {
        _title = quote.text;
        _subtitle = quote.attribution.isNotEmpty
            ? quote.attribution
            : '欢迎，${widget.username}';
        _textLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _textLoading = false);
    }
  }

  Future<void> _loadWallpaper() async {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    try {
      final url = await getIt<AlcyWallpaperService>().fetchImageUrl(
        narrow: narrow,
      );
      if (!mounted) return;
      setState(() => _wallpaperUrl = url);
    } catch (_) {
      // 保留本地 fallback
    }
  }

  Widget _buildBackground() {
    final url = _wallpaperUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Image.asset(_fallbackAsset, fit: BoxFit.cover);
        },
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(
            _fallbackAsset,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      context.astralPalette.accent.withValues(alpha: 0.55),
                      context.astralPalette.canvas,
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    }
    return Image.asset(
      _fallbackAsset,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                context.astralPalette.accent.withValues(alpha: 0.55),
                context.astralPalette.canvas,
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00000000),
                  Color(0x66000000),
                  Color(0xB3000000),
                ],
                stops: [0.35, 0.72, 1],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 320),
              opacity: _textLoading ? 0.55 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _title,
                    style: textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      height: 1.2,
                      shadows: const [
                        Shadow(blurRadius: 12, color: Color(0x66000000)),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _subtitle,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                      height: 1.35,
                      shadows: const [
                        Shadow(blurRadius: 8, color: Color(0x66000000)),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectedRoomCard extends StatelessWidget {
  const _ConnectedRoomCard({
    super.key,
    required this.roomDisplayName,
    this.roomRoleLabel,
    this.roomGameId,
    this.roomShortCode,
    required this.isRoomHost,
    this.hostOnline = true,
    this.virtualIp,
    required this.onShare,
    required this.onDisconnect,
  });

  final String roomDisplayName;
  final String? roomRoleLabel;
  final String? roomGameId;
  final String? roomShortCode;
  final bool isRoomHost;
  final bool hostOnline;
  final String? virtualIp;
  final VoidCallback onShare;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final game = GameCatalog.byId(roomGameId);
    final code = roomShortCode?.trim() ?? '';
    final ip = virtualIp?.trim() ?? '';
    final showHostOffline = !isRoomHost && !hostOnline;

    return AstralCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHostOffline) ...[
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
                      [
                        if (game != null) game.name,
                        if (roomRoleLabel != null && roomRoleLabel!.isNotEmpty)
                          roomRoleLabel!,
                      ].join(' · '),
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
              if (isRoomHost) ...[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: onShare,
                    child: const Text('分享'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
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
