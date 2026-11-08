import 'dart:async';
import 'dart:io';

import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/services/steam_selftest_service.dart';
import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/src/rust/api/steam.dart';
import 'package:astral_game/ui/widgets/app_toast.dart';
import 'package:astral_game/ui/widgets/astral_grouped_tile.dart';
import 'package:astral_game/ui/widgets/astral_settings_section.dart';
import 'package:astral_game/ui/widgets/astral_status_dot.dart';
import 'package:astral_game/utils/error_text.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:flutter/material.dart';

/// 设置页「Steam」分区：SteamID、SDR 中继、组网房间与成员。
///
/// Steam Tab 顶栏只保留一行只读状态，这里承接原来折在展开区里的全部细节；
/// 诊断入口做成卡片下方的次要按钮。
class SteamSettingsSection extends StatefulWidget {
  const SteamSettingsSection({super.key});

  @override
  State<SteamSettingsSection> createState() => _SteamSettingsSectionState();
}

class _SteamSettingsSectionState extends State<SteamSettingsSection> {
  static const Duration _pollInterval = Duration(seconds: 2);

  final SteamTransportService _steam = SteamTransportService();
  Timer? _timer;
  SteamStatusInfo? _status;
  SteamRoomInfo? _room;
  bool _refreshing = false;
  bool _selfTestRunning = false;
  String _selfTestStatus = '';

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
      if (!mounted) return;
      setState(() {
        _status = status;
        _room = room;
      });
    } catch (e) {
      appLogger.w('[Settings][Steam] 状态读取失败: $e');
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final room = _room;
    Widget tone(AstralStatusTone value, String text) =>
        AstralStatusLine(tone: value, text: text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AstralSettingsFormCard(
          title: 'Steam',
          subtitle: '账号、SDR 中继与组网房间',
          rows: [
            (index, count) => AstralGroupedTile(
              icon: Icons.person_outline_rounded,
              label: 'Steam 账号',
              subtitle: _accountSubtitle(),
              index: index,
              count: count,
              trailing: tone(
                status?.loggedOn == true
                    ? AstralStatusTone.ready
                    : AstralStatusTone.unavailable,
                status?.loggedOn == true ? '已登录' : '未登录',
              ),
            ),
            (index, count) => AstralGroupedTile(
              icon: Icons.cloud_done_outlined,
              label: 'SDR 中继',
              subtitle: _relaySubtitle(),
              index: index,
              count: count,
              trailing: tone(
                status?.relayReady == true
                    ? AstralStatusTone.ready
                    : AstralStatusTone.unavailable,
                status?.relayReady == true ? '已就绪' : '准备中',
              ),
            ),
            (index, count) => AstralGroupedTile(
              icon: Icons.lan_outlined,
              label: '组网房间',
              subtitle: _roomSubtitle(room),
              index: index,
              count: count,
              trailing: tone(
                room?.active == true
                    ? AstralStatusTone.ready
                    : AstralStatusTone.unavailable,
                room?.active == true ? '已组网' : '未组网',
              ),
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
            if (_debugEnabled)
              (index, count) => AstralGroupedTile(
                icon: Icons.play_circle_outline_rounded,
                label: '自检：房主跑一遍',
                subtitle: _selfTestSubtitle(
                  '自动建房 → 等客人 → 校验握手 → 导出日志到桌面',
                ),
                index: index,
                count: count,
                onTap: _canRunSelfTest ? () => _runSelfTest(host: true) : null,
              ),
            if (_debugEnabled)
              (index, count) => AstralGroupedTile(
                icon: Icons.play_circle_outline_rounded,
                label: '自检：客人跑一遍',
                subtitle: _selfTestSubtitle(_guestSelfTestIdle()),
                index: index,
                count: count,
                onTap: _canRunSelfTest ? () => _runSelfTest(host: false) : null,
              ),
            for (final member
                in (room?.members ?? const <SteamMemberInfo>[])
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
                trailing: tone(
                  member.online
                      ? AstralStatusTone.ready
                      : AstralStatusTone.unavailable,
                  member.online ? (member.isSelf ? '本机' : '在线') : '离线',
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _showLobbyDiag,
            icon: const Icon(Icons.monitor_heart_outlined, size: 18),
            label: const Text('诊断：大厅信息'),
          ),
        ),
      ],
    );
  }

  /// 仅在 `ASTRAL_STEAM_DEBUG=1` 启动时显示诊断入口。
  static final bool _debugEnabled = () {
    final raw = Platform.environment['ASTRAL_STEAM_DEBUG']
        ?.trim()
        .toLowerCase();
    return raw == '1' || raw == 'true' || raw == 'yes';
  }();

  Future<void> _ghostProbe() async {
    String message;
    try {
      message = await _steam.debugGhostProbe();
    } catch (e) {
      appLogger.w('[Settings][Steam] 幽灵成员诊断失败: $e');
      message = '诊断失败：${errorText(e)}';
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
      appLogger.w('[Settings][Steam] 客人侧宽限诊断失败: $e');
      message = '诊断失败：${errorText(e)}';
    }
    if (!mounted) return;
    showAppToast(context, message);
    await _refresh();
  }

  /// 自检只在未组网时可用：房间活跃时先离开，避免打断用户正在用的联机。
  bool get _canRunSelfTest => !_selfTestRunning && _room?.active != true;

  String _selfTestSubtitle(String idle) {
    if (_selfTestRunning) {
      return _selfTestStatus.isEmpty ? '正在准备…' : _selfTestStatus;
    }
    if (_room?.active == true) return '请先离开当前组网房间再运行自检';
    return idle;
  }

  String _guestSelfTestIdle() {
    final lobbyId = getIt<SettingsState>().steamSelfTestLobbyId?.trim() ?? '';
    if (lobbyId.isEmpty) return '自动搜房 → 加入 → 校验握手 → 导出日志到桌面';
    return '加入脚本指定的大厅 $lobbyId → 校验握手 → 导出日志到桌面';
  }

  Future<void> _runSelfTest({required bool host}) async {
    setState(() {
      _selfTestRunning = true;
      _selfTestStatus = '正在准备…';
    });
    SteamSelfTestResult? result;
    String? error;
    try {
      result = await SteamSelfTestService().run(
        host: host,
        targetLobbyId: host
            ? null
            : getIt<SettingsState>().steamSelfTestLobbyId,
        onProgress: (message) {
          if (!mounted) return;
          setState(() => _selfTestStatus = message);
        },
      );
    } catch (e) {
      appLogger.w('[Settings][Steam] 自检失败: $e');
      error = errorText(e);
    }
    if (!mounted) return;
    setState(() {
      _selfTestRunning = false;
      _selfTestStatus = '';
    });
    if (error != null) {
      showAppToast(context, '自检失败：$error');
    } else if (result != null) {
      showAppToast(context, '${result.summary}：${result.path}');
    }
    await _refresh();
  }

  Future<void> _showLobbyDiag() async {
    final SteamLobbyDiag diag;
    try {
      diag = await _steam.lobbyDiag();
    } catch (e) {
      appLogger.w('[Settings][Steam] 读取大厅诊断失败: $e');
      if (mounted) showAppToast(context, '读取大厅诊断失败：${errorText(e)}');
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
                  Text(diag.overlayHint, style: TextStyle(color: scheme.error)),
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
