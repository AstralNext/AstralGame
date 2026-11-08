import 'dart:async';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/src/rust/api/steam.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/astral_status_dot.dart';
import 'package:astral_game/ui/widgets/error_state.dart';
import 'package:astral_game/ui/widgets/steam_lobby_list_section.dart';
import 'package:flutter/material.dart';

/// Steam 组网（SDR 虚拟局域网）状态面板。
///
/// 每 2 秒刷新一次登录 / SDR 就绪 / 组网状态，顶部只有一行只读状态；
/// 账号、中继、房间与成员的详细信息归到设置页的 Steam 分区。
/// 用于「Steam」一级 Tab：当前联机模式为 Steam 时替代服务器页。
class SteamTransportPanel extends StatefulWidget {
  const SteamTransportPanel({super.key});

  @override
  State<SteamTransportPanel> createState() => _SteamTransportPanelState();
}

class _SteamTransportPanelState extends State<SteamTransportPanel> {
  static const Duration _pollInterval = Duration(seconds: 2);

  final SteamTransportService _steam = SteamTransportService();
  final GlobalKey<SteamLobbyListSectionState> _lobbyListKey =
      GlobalKey<SteamLobbyListSectionState>();
  Timer? _timer;
  SteamStatusInfo? _status;
  SteamRoomInfo? _room;
  SteamLobbyDiag? _diag;
  String? _error;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final status = await _steam.status();
      final room = await _steam.roomInfo();
      SteamLobbyDiag? diag;
      if (room.active) {
        try {
          diag = await _steam.lobbyDiag();
        } catch (_) {
          // 诊断是附加信息，失败不影响主面板。
          diag = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _room = room;
        _diag = diag;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    if (_error != null) {
      return ErrorState(
        icon: Icons.cloud_off_rounded,
        title: 'Steam 状态读取失败',
        message: _error,
        onRetry: _refresh,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusStrip(context, room),
        const SizedBox(height: AppDimensions.sectionGap),
        Expanded(
          child: SteamLobbyListSection(
            key: _lobbyListKey,
            connection: getIt<ConnectionService>(),
            roomActive: room?.active == true,
            onJoined: () => unawaited(_refresh()),
            // 邀请只对房主有意义；非房主时头部不出现该入口。
            onInvite: (room?.active == true && room?.isHost == true)
                ? _inviteFriends
                : null,
          ),
        ),
      ],
    );
  }

  /// 32px 只读状态条：账号短名 + 三个状态点，不可点击、不可展开。
  Widget _buildStatusStrip(BuildContext context, SteamRoomInfo? room) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final status = _status;
    final accountName = (status?.persona.trim().isNotEmpty ?? false)
        ? status!.persona.trim()
        : 'Steam 账号';
    final loggedIn = status?.loggedOn == true;
    final relayReady = status?.relayReady == true;
    final inRoom = room?.active == true;

    Widget separator() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 2,
        height: 2,
        decoration: BoxDecoration(
          color: palette.textTertiary,
          shape: BoxShape.circle,
        ),
      ),
    );

    return AstralCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  accountName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              separator(),
              if (status == null)
                Text(
                  '正在连接 Steam…',
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                )
              else ...[
                AstralStatusLine(
                  tone: loggedIn
                      ? AstralStatusTone.ready
                      : AstralStatusTone.unavailable,
                  text: loggedIn ? '已登录' : '未登录',
                ),
                separator(),
                AstralStatusLine(
                  tone: relayReady
                      ? AstralStatusTone.ready
                      : AstralStatusTone.unavailable,
                  text: relayReady ? 'SDR 就绪' : 'SDR 准备中',
                ),
                separator(),
                AstralStatusLine(
                  tone: inRoom
                      ? AstralStatusTone.ready
                      : AstralStatusTone.unavailable,
                  text: inRoom ? '已组网' : '未组网',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _inviteFriends() async {
    SteamLobbyDiag? diag;
    try {
      diag = await _steam.lobbyDiag();
    } catch (_) {
      diag = _diag;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: astralDialogBarrierColor,
      builder: (dialogContext) => _InviteFriendDialog(
        steam: _steam,
        overlayEnabled: diag?.overlayEnabled ?? false,
        onSearchRooms: () async {
          Navigator.pop(dialogContext);
          // 房间列表常驻在状态条下方，这里只触发一次刷新。
          await _lobbyListKey.currentState?.refresh();
        },
      ),
    );
    await _refresh();
  }
}

/// 邀请好友弹窗：优先用 SteamID 直接邀请（不依赖覆盖层），
/// 覆盖层可用时才提供原生邀请面板作为兜底，并始终给出搜房替代路径。
class _InviteFriendDialog extends StatefulWidget {
  const _InviteFriendDialog({
    required this.steam,
    required this.overlayEnabled,
    required this.onSearchRooms,
  });

  final SteamTransportService steam;
  final bool overlayEnabled;
  final Future<void> Function() onSearchRooms;

  @override
  State<_InviteFriendDialog> createState() => _InviteFriendDialogState();
}

class _InviteFriendDialogState extends State<_InviteFriendDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _show(String message, {required bool isError}) {
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  Future<void> _inviteBySteamId() async {
    final id = _controller.text.trim();
    if (!RegExp(r'^\d{17}$').hasMatch(id)) {
      _show('请输入 17 位 SteamID64（在好友资料页复制）', isError: true);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final text = await widget.steam.inviteFriend(id);
      if (!mounted) return;
      _show(text, isError: false);
    } catch (e) {
      if (!mounted) return;
      _show('邀请失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPanel() async {
    if (!widget.overlayEnabled) {
      _show('需要开启 Steam 覆盖层才能邀请好友', isError: true);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final text = await widget.steam.openInviteDialog();
      if (!mounted) return;
      _show(text, isError: false);
    } catch (e) {
      if (!mounted) return;
      _show('无法打开 Steam 邀请面板：$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warning = !widget.overlayEnabled;
    return AlertDialog(
      title: const Text('邀请好友'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: warning
                    ? scheme.errorContainer.withValues(alpha: 0.4)
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                warning
                    ? '需要开启 Steam 覆盖层才能邀请好友'
                          '（Steam → 设置 → 游戏中 → 启用 Steam 覆盖层）。\n'
                          '仍可直接输入好友 SteamID 邀请；或让对方在 Steam 页下方的「房间列表」里找到你的房间。'
                    : '可直接输入好友 SteamID 邀请（不依赖覆盖层）；也可唤起 Steam 原生邀请面板。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: warning
                      ? scheme.onErrorContainer
                      : scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '好友 SteamID64',
                hintText: '17 位数字',
              ),
              onSubmitted: (_) => _inviteBySteamId(),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _messageIsError ? scheme.error : scheme.primary,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : widget.onSearchRooms,
          child: const Text('查看房间列表'),
        ),
        TextButton(
          onPressed: _busy || !widget.overlayEnabled ? null : _openPanel,
          child: const Text('打开邀请面板'),
        ),
        FilledButton(
          onPressed: _busy ? null : _inviteBySteamId,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('直接邀请'),
        ),
      ],
    );
  }
}
