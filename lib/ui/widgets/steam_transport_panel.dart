import 'dart:async';
import 'dart:io';

import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/src/rust/api/steam.dart';
import 'package:astral_game/ui/widgets/app_toast.dart';
import 'package:astral_game/ui/widgets/astral_grouped_tile.dart';
import 'package:astral_game/ui/widgets/astral_settings_section.dart';
import 'package:astral_game/ui/widgets/error_state.dart';
import 'package:astral_game/ui/widgets/steam_lobby_browser_dialog.dart';
import 'package:flutter/material.dart';

/// Steam 组网（SDR 虚拟局域网）状态面板。
///
/// 每 2 秒刷新一次：Steam 登录 / SteamID / SDR 中继是否就绪、当前组网房间的
/// 虚拟 IP、成员列表与实时流量。
/// 用于「Steam」一级 Tab：当前联机模式为 Steam 时替代服务器页。
class SteamTransportPanel extends StatefulWidget {
  const SteamTransportPanel({super.key});

  @override
  State<SteamTransportPanel> createState() => _SteamTransportPanelState();
}

class _SteamTransportPanelState extends State<SteamTransportPanel> {
  static const Duration _pollInterval = Duration(seconds: 2);

  final SteamTransportService _steam = SteamTransportService();
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final room = _room;
    if (_error != null) {
      return ErrorState(
        icon: Icons.cloud_off_rounded,
        title: 'Steam 状态读取失败',
        message: _error,
        onRetry: _refresh,
      );
    }

    Widget badge(String text, {required bool ok}) => Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: ok ? scheme.primary : scheme.error,
        fontWeight: FontWeight.w600,
      ),
    );

    return AstralSettingsFormCard(
      title: 'Steam 组网',
      subtitle: '经 Steam 中继建立虚拟局域网：为每个成员分配虚拟 IP，游戏直接局域网联机',
      rows: [
        (index, count) => AstralGroupedTile(
          icon: Icons.person_outline_rounded,
          label: 'Steam 账号',
          subtitle: _accountSubtitle(),
          index: index,
          count: count,
          trailing: badge(
            _status?.loggedOn == true ? '已登录' : '未登录',
            ok: _status?.loggedOn == true,
          ),
        ),
        (index, count) => AstralGroupedTile(
          icon: Icons.cloud_done_outlined,
          label: 'SDR 中继',
          subtitle: _relaySubtitle(),
          index: index,
          count: count,
          trailing: badge(
            _status?.relayReady == true ? '已就绪' : '准备中',
            ok: _status?.relayReady == true,
          ),
        ),
        (index, count) => AstralGroupedTile(
          icon: Icons.lan_outlined,
          label: '组网房间',
          subtitle: _roomSubtitle(room),
          index: index,
          count: count,
          trailing: badge(
            room?.active == true ? '已组网' : '未组网',
            ok: room?.active == true,
          ),
        ),
        if (room?.active == true || _debugEnabled)
          (index, count) => AstralGroupedTile(
            icon: Icons.monitor_heart_outlined,
            label: '诊断：大厅信息',
            subtitle: _diagSubtitle(),
            index: index,
            count: count,
            onTap: _showLobbyDiag,
          ),
        if (room?.active == true && room?.isHost == true)
          (index, count) => AstralGroupedTile(
            icon: Icons.person_add_alt_1_outlined,
            label: '邀请好友',
            subtitle: _inviteSubtitle(),
            index: index,
            count: count,
            onTap: _inviteFriends,
          ),
        if (room?.active == true && room?.isHost == true && _debugEnabled)
          (index, count) => AstralGroupedTile(
            icon: Icons.bug_report_outlined,
            label: '诊断：幽灵成员清理',
            subtitle: '注入离线超过宽限期的成员并跑一次真实 prune',
            index: index,
            count: count,
            onTap: _ghostProbe,
          ),
        if (_debugEnabled)
          (index, count) => AstralGroupedTile(
            icon: Icons.bug_report_outlined,
            label: '诊断：客人侧宽限过滤',
            subtitle: '注入离线超宽限期的房主并跑真实 prune，验证 roster 被清空',
            index: index,
            count: count,
            onTap: _guestRosterProbe,
          ),
        for (final member in (room?.members ?? const <SteamMemberInfo>[])
            // 离线成员不渲染（本机除外）；宽限期结束后 Rust 侧会真正摘除。
            .where((m) => m.online || m.isSelf))
          (index, count) => AstralGroupedTile(
            icon: member.isHost
                ? Icons.workspace_premium_outlined
                : Icons.computer_rounded,
            label: member.nickname.isEmpty
                ? 'Steam-${member.steamId}'
                : member.nickname,
            subtitle:
                '${member.virtualIp} · ${member.latencyMs}ms'
                '${member.isSelf || !member.online ? '' : ' · ${member.viaRelay ? '中转' : '直连'}'}'
                ' · ↓ ${_formatBytes(member.bytesIn)} ↑ ${_formatBytes(member.bytesOut)}',
            index: index,
            count: count,
            trailing: badge(
              member.online ? (member.isSelf ? '本机' : '在线') : '离线',
              ok: member.online,
            ),
          ),
      ],
    );
  }

  /// 仅在 `ASTRAL_STEAM_DEBUG=1` 启动时显示诊断入口。
  static final bool _debugEnabled = () {
    final raw = Platform.environment['ASTRAL_STEAM_DEBUG']?.trim().toLowerCase();
    return raw == '1' || raw == 'true' || raw == 'yes';
  }();

  Future<void> _ghostProbe() async {
    String message;
    try {
      message = await _steam.debugGhostProbe();
    } catch (e) {
      message = '诊断失败：$e';
    }
    if (!mounted) return;
    showAppToast(context, message);
    await _refresh();
  }

  Future<void> _guestRosterProbe() async {
    String message;
    try {
      message = await _steam.debugGuestRosterProbe();
    } catch (e) {
      message = '诊断失败：$e';
    }
    if (!mounted) return;
    showAppToast(context, message);
    await _refresh();
  }

  Future<void> _showLobbyDiag() async {
    final SteamLobbyDiag diag;
    try {
      diag = await _steam.lobbyDiag();
    } catch (e) {
      if (mounted) showAppToast(context, '读取大厅诊断失败：$e');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: astralDialogBarrierColor,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        Widget row(String label, String value, {bool ok = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  label,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: SelectableText(
                  value.isEmpty ? '—' : value,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: ok ? null : scheme.error,
                  ),
                ),
              ),
            ],
          ),
        );
        return AlertDialog(
          title: const Text('大厅诊断'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row('大厅 id', diag.lobbyId),
                row('ag_game', diag.gameId),
                row('ag_ver', diag.version),
                row('ag_gate', diag.gate),
                row('可加入', diag.joinable ? '是' : '否', ok: diag.joinable),
                row('成员', '${diag.members} / ${diag.capacity}'),
                row(
                  '角色',
                  diag.lobbyId.isEmpty ? '未建房' : (diag.isHost ? '房主' : '成员'),
                ),
                row(
                  '覆盖层',
                  diag.overlayEnabled ? '已开启' : '未开启',
                  ok: diag.overlayEnabled,
                ),
                if (diag.overlayHint.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    diag.overlayHint,
                    style: TextStyle(color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        );
      },
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
          await _openLobbySearch();
        },
      ),
    );
    await _refresh();
  }

  /// 覆盖层不可用时的替代路径：直接进大厅搜房。
  Future<void> _openLobbySearch() async {
    await getIt<GameAssistRulesService>().ensureLocalLoaded();
    if (!mounted) return;
    final catalog = GameCatalog.pickerItems;
    if (catalog.isEmpty) {
      showAppToast(context, '游戏目录未加载');
      return;
    }
    final ActiveRoomSession? session = await showSteamLobbyBrowser(
      context,
      connection: getIt<ConnectionService>(),
      catalog: catalog,
    );
    if (!mounted || session == null) return;
    showAppToast(context, '已加入「${session.gameName}」房间');
  }

  String _inviteSubtitle() {
    final diag = _diag;
    if (diag == null) return '通过 Steam 好友列表邀请（正在检测覆盖层状态…）';
    if (!diag.overlayEnabled) {
      return '覆盖层未开启：可直接邀请 SteamID 好友，或让对方搜索房间';
    }
    return '可直接邀请 SteamID 好友；也可唤起 Steam 邀请面板';
  }

  String _diagSubtitle() {
    final diag = _diag;
    if (diag == null) return '未读取到大厅信息';
    if (diag.lobbyId.isEmpty) {
      return diag.overlayHint.isEmpty ? '当前没有 Steam 大厅' : diag.overlayHint;
    }
    return '大厅 ${diag.lobbyId} · ${diag.joinable ? '可加入' : '已关闭加入'}'
        ' · ${diag.members}/${diag.capacity} 人';
  }

  String _accountSubtitle() {
    final status = _status;
    if (status == null) return '正在启动 Steam 接口…';
    if (!status.ok) {
      return status.message.isEmpty ? 'Steam 未初始化' : status.message;
    }
    final persona = status.persona.isEmpty ? 'Steam 玩家' : status.persona;
    return '$persona · ${status.steamId}';
  }

  String _relaySubtitle() {
    final status = _status;
    if (status == null) return '正在检测 SDR 中继网络…';
    if (!status.ok) return 'Steam 未就绪，中继不可用';
    if (status.relayReady) return '中继 / 直连由 Steam 自动选择，无需手动配置';
    return status.message.isEmpty ? '正在获取中继网络…' : status.message;
  }

  String _roomSubtitle(SteamRoomInfo? room) {
    if (room == null || !room.active) return '尚未创建或加入 Steam 组网房间';
    final role = room.isHost ? '房主' : '成员';
    return '$role · 虚拟 IP ${room.virtualIp} · ${room.memberCount} 人 · ${room.network}';
  }

  static String _formatBytes(BigInt bytes) {
    final value = bytes.toInt();
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) {
      return '${(value / 1024).toStringAsFixed(1)} KB';
    }
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
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
                          '仍可直接输入好友 SteamID 邀请；或让对方在「加入 → 搜索房间」里找到你的房间。'
                    : '可直接输入好友 SteamID 邀请（不依赖覆盖层）；也可唤起 Steam 原生邀请面板。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: warning ? scheme.onErrorContainer : scheme.onSurfaceVariant,
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
          child: const Text('去搜索房间'),
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
