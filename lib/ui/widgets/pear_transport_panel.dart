import 'dart:async';

import 'package:astral_game/data/services/pear_transport_service.dart';
import 'package:astral_game/src/rust/api/pear.dart';
import 'package:astral_game/ui/widgets/astral_grouped_tile.dart';
import 'package:astral_game/ui/widgets/astral_settings_section.dart';
import 'package:flutter/material.dart';

/// Holepunch Pear（HyperDHT 打洞 / 中继）组网状态面板。
///
/// 每 2 秒刷新一次：Bare 运行时 / 侧车是否就绪、房主公钥、当前组网房间的
/// 虚拟 IP、成员列表与实时流量。
/// 用于「Pear」一级 Tab：当前联机模式为 Pear 时替代服务器页。
class PearTransportPanel extends StatefulWidget {
  const PearTransportPanel({super.key});

  @override
  State<PearTransportPanel> createState() => _PearTransportPanelState();
}

class _PearTransportPanelState extends State<PearTransportPanel> {
  static const Duration _pollInterval = Duration(seconds: 2);

  final PearTransportService _pear = PearTransportService();
  Timer? _timer;
  PearStatusInfo? _status;
  PearRoomInfo? _room;
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
      final status = await _pear.status();
      final room = await _pear.roomInfo();
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

  bool get _booting =>
      _status != null && !_status!.ok && _status!.message == 'Pear 未初始化';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final room = _room;

    Widget badge(String text, {required bool ok}) => Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: ok ? scheme.primary : scheme.error,
        fontWeight: FontWeight.w600,
      ),
    );

    final runtimeOk = _status?.ok == true;

    return AstralSettingsFormCard(
      title: 'Holepunch Pear 组网',
      subtitle: '经 HyperDHT 打洞 / 中继建立虚拟局域网：为每个成员分配虚拟 IP，游戏直接局域网联机',
      rows: [
        (index, count) => AstralGroupedTile(
          icon: Icons.extension_outlined,
          label: 'Pear 运行时',
          subtitle: _runtimeSubtitle(),
          index: index,
          count: count,
          trailing: badge(
            _status == null || _booting
                ? '检测中'
                : runtimeOk
                ? '可用'
                : '不可用',
            ok: _status == null || _booting || runtimeOk,
          ),
        ),
        (index, count) => AstralGroupedTile(
          icon: Icons.vpn_key_outlined,
          label: '房主公钥',
          subtitle: _hostKeySubtitle(),
          index: index,
          count: count,
          trailing: badge(
            _status?.ready == true ? '已就绪' : '准备中',
            ok: _status?.ready == true,
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
        for (final member in room?.members ?? const <PearMemberInfo>[])
          (index, count) => AstralGroupedTile(
            icon: member.isHost
                ? Icons.workspace_premium_outlined
                : Icons.computer_rounded,
            label: member.nickname.isEmpty
                ? 'Pear-${_shortKey(member.pearKey)}'
                : member.nickname,
            subtitle:
                '${member.virtualIp} · ${member.latencyMs}ms'
                ' · ↓ ${_formatBytes(member.bytesIn)} ↑ ${_formatBytes(member.bytesOut)}',
            index: index,
            count: count,
            trailing: badge(
              member.online ? (member.isSelf ? '本机' : '在线') : '离线',
              ok: member.online,
            ),
          ),
        if (_error != null)
          (index, count) => AstralGroupedTile(
            icon: Icons.error_outline_rounded,
            label: '状态读取失败',
            subtitle: _error,
            index: index,
            count: count,
          ),
      ],
    );
  }

  String _runtimeSubtitle() {
    final error = _error;
    if (error != null) return error;
    final status = _status;
    if (status == null || _booting) return '正在启动 Pear 运行时…';
    if (!status.ok) {
      return status.message.isEmpty ? 'Bare 运行时不可用' : status.message;
    }
    return 'Bare 运行时已就绪，HyperDHT 打洞 / 中继可自动选择';
  }

  String _hostKeySubtitle() {
    final status = _status;
    if (status == null) return '尚未建立房间';
    final key = status.hostKey;
    if (key.isEmpty) return '尚未建立房间';
    return status.isHost ? '本机公钥 · $key' : '房主公钥 · $key';
  }

  String _roomSubtitle(PearRoomInfo? room) {
    if (room == null || !room.active) return '尚未创建或加入 Pear 组网房间';
    final role = room.isHost ? '房主' : '成员';
    return '$role · 虚拟 IP ${room.virtualIp} · ${room.memberCount} 人 · ${room.network}';
  }

  static String _shortKey(String key) =>
      key.length <= 12 ? key : '${key.substring(0, 12)}…';

  static String _formatBytes(BigInt bytes) {
    final value = bytes.toInt();
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) {
      return '${(value / 1024).toStringAsFixed(1)} KB';
    }
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
