import 'dart:async';

import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:astral_game/src/rust/api/steam.dart';
import 'package:astral_game/ui/widgets/astral_grouped_tile.dart';
import 'package:astral_game/ui/widgets/astral_settings_section.dart';
import 'package:astral_game/ui/widgets/error_state.dart';
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
      if (!mounted) return;
      setState(() {
        _status = status;
        _room = room;
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
        for (final member in room?.members ?? const <SteamMemberInfo>[])
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
