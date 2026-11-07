import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/services/shortcut_service.dart';
import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/src/rust/api/steam.dart';

/// 双机自检结果：报告一定落盘，成功与否看 [success]。
class SteamSelfTestResult {
  const SteamSelfTestResult({
    required this.path,
    required this.success,
    required this.summary,
  });

  final String path;
  final bool success;
  final String summary;
}

/// 双机自检：两台机器各点一次，自动建房/找房、握手、采集并导出日志。
///
/// 自检使用固定游戏标识 `astral-selftest` 和固定口令，不复用用户房间，
/// 跑完自动离开大厅。日志写到桌面，文件名带角色与时间戳。
class SteamSelfTestService {
  SteamSelfTestService({SteamTransportService? transport})
    : _steam = transport ?? SteamTransportService();

  static const String gameId = 'astral-selftest';
  static const String joinToken = 'astral-selftest-v1';
  static const String _logName = 'astral-steam-debug.log';

  final SteamTransportService _steam;

  /// 等待客人 / 搜索房主的超时。测试环境可用 `ASTRAL_SELFTEST_WAIT_SECS` 缩短。
  static Duration get _waitTimeout {
    final raw = int.tryParse(
      Platform.environment['ASTRAL_SELFTEST_WAIT_SECS']?.trim() ?? '',
    );
    final secs = (raw ?? 120).clamp(5, 300);
    return Duration(seconds: secs);
  }

  /// 跑一次自检。[host] 为真时建房等客人，否则搜房并加入。
  ///
  /// [targetLobbyId] 只对客人有效：由脚本粘贴的大厅 id，填了就直连该大厅，
  /// 留空则按固定游戏标识搜房。
  Future<SteamSelfTestResult> run({
    required bool host,
    String? targetLobbyId,
    required void Function(String message) onProgress,
  }) async {
    final startedAt = DateTime.now();
    final room = await _steam.roomInfo();
    if (room.active) {
      throw StateError('请先离开当前组网房间再运行自检');
    }

    // 调试日志只由 Rust 侧写；没有开调试开关时不会有任何事件，报告会缺关键
    // 证据，所以先按环境变量判定，而不是要求文件已存在（首个事件发生前文件
    // 可能还没创建）。
    final debugEnabled = const {'1', 'true', 'yes'}.contains(
      (Platform.environment['ASTRAL_STEAM_DEBUG'] ?? '').trim().toLowerCase(),
    );
    if (!debugEnabled) {
      throw StateError('请用 ASTRAL_STEAM_DEBUG=1 启动后重试');
    }

    final logFile = File('${Directory.systemTemp.path}\\$_logName');
    // 记录起点，报告只包含本次自检期间产生的事件。
    final logStart = logFile.existsSync()
        ? (await logFile.readAsString()).length
        : 0;

    var success = false;
    String? failure;
    var lobbyId = '';
    try {
      if (host) {
        onProgress('正在创建自检房…');
        final info = await _steam.createLobby(
          gameId: gameId,
          name: 'Astral 双机自检房',
          gate: kSteamLobbyGateBasic,
          maxMembers: 8,
          joinToken: joinToken,
          nickname: '自检房主',
        );
        lobbyId = info.lobbyId;
        onProgress('自检房已创建，等待客人加入…（最长 ${_waitTimeout.inSeconds} 秒）');
        final joined = await _waitGuest(onProgress);
        if (!joined) {
          failure = '等待客人超时，未检测到客人握手';
        } else {
          onProgress('已检测到客人握手，等待 12 秒供对方导出…');
          await Future<void>.delayed(const Duration(seconds: 12));
          success = true;
        }
      } else {
        final target = targetLobbyId?.trim() ?? '';
        final joined = target.isEmpty
            ? await _searchAndJoin(onProgress)
            : await _joinKnownLobby(target, onProgress);
        lobbyId = target;
        if (!joined) {
          failure = target.isEmpty ? '未找到可加入的自检房' : '加入指定大厅失败';
        } else {
          onProgress('已加入自检房，等待握手与传输就绪…');
          await Future<void>.delayed(const Duration(seconds: 3));
          final status = await _steam.status();
          if (!status.roomActive) {
            failure = '加入后房间未保持活跃';
          } else {
            success = true;
          }
        }
      }
    } catch (e) {
      failure = '$e';
    }

    final endedAt = DateTime.now();
    final status = await _steam.status();
    final roomInfo = await _steam.roomInfo();
    SteamLobbyDiag? diag;
    try {
      diag = await _steam.lobbyDiag();
    } catch (_) {
      diag = null;
    }
    final logText = await _readLogSlice(logFile, logStart);
    final handshake = _handshakeStatus(host: host, logText: logText);
    if (success && !handshake.ok) {
      success = false;
      failure = '握手记录不完整：${handshake.detail}';
    }

    final report = _buildReport(
      host: host,
      startedAt: startedAt,
      endedAt: endedAt,
      success: success,
      failure: failure,
      lobbyId: lobbyId.isEmpty ? (diag?.lobbyId ?? '') : lobbyId,
      status: status,
      room: roomInfo,
      diag: diag,
      handshake: handshake,
      logText: logText,
    );
    final path = await _writeReport(host: host, startedAt: startedAt, report: report);

    try {
      await _steam.leaveLobby();
    } catch (_) {
      // 自检已结束，离房失败不影响报告。
    }

    return SteamSelfTestResult(
      path: path,
      success: success,
      summary: success
          ? '自检完成，日志已导出'
          : '自检结束（未通过：${failure ?? '未知原因'}），日志已导出',
    );
  }

  /// 房主侧：等一个非自己的在线成员，并确认 HELLO/WELCOME 日志出现。
  Future<bool> _waitGuest(void Function(String) onProgress) async {
    final deadline = DateTime.now().add(_waitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final room = await _steam.roomInfo();
      final hasGuest = room.members.any(
        (m) => !m.isSelf && m.online && !m.isHost,
      );
      if (hasGuest) return true;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  /// 客人侧：反复搜索自检房并加入，直到成功或超时。
  Future<bool> _searchAndJoin(void Function(String) onProgress) async {
    onProgress('正在搜索自检房…（最长 ${_waitTimeout.inSeconds} 秒）');
    final deadline = DateTime.now().add(_waitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      List<SteamLobbyInfo> found;
      try {
        found = await _steam.searchLobbies(gameId);
      } catch (_) {
        found = const [];
      }
      if (found.isNotEmpty) {
        final lobby = found.first;
        onProgress('找到自检房 ${lobby.lobbyId}，正在加入…');
        try {
          await _steam.joinLobby(
            lobbyId: lobby.lobbyId,
            gameId: gameId,
            joinToken: joinToken,
            nickname: '自检客人',
          );
          return true;
        } catch (e) {
          onProgress('加入失败，重试中：$e');
        }
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  /// 客人侧：脚本里粘贴了大厅 id 时直接加入该大厅（不再搜房）。
  Future<bool> _joinKnownLobby(
    String lobbyId,
    void Function(String) onProgress,
  ) async {
    onProgress('正在加入指定大厅 $lobbyId…');
    try {
      await _steam.joinLobby(
        lobbyId: lobbyId,
        gameId: gameId,
        joinToken: joinToken,
        nickname: '自检客人',
      );
      return true;
    } catch (e) {
      onProgress('加入失败：$e');
      return false;
    }
  }

  Future<String> _readLogSlice(File file, int start) async {
    if (!file.existsSync()) return '';
    final text = await file.readAsString();
    if (start >= text.length) return '';
    return text.substring(start);
  }

  ({bool ok, String detail}) _handshakeStatus({
    required bool host,
    required String logText,
  }) {
    final hello = host
        ? logText.contains('hello_ok')
        : logText.contains('hello_sent');
    final welcome = host
        ? logText.contains('welcome_sent')
        : logText.contains('welcome ');
    if (hello && welcome) {
      return (ok: true, detail: 'HELLO/WELCOME 均已记录');
    }
    return (
      ok: false,
      detail: 'hello=${hello ? '有' : '无'} welcome=${welcome ? '有' : '无'}',
    );
  }

  String _buildReport({
    required bool host,
    required DateTime startedAt,
    required DateTime endedAt,
    required bool success,
    required String? failure,
    required String lobbyId,
    required SteamStatusInfo status,
    required SteamRoomInfo room,
    required SteamLobbyDiag? diag,
    required ({bool ok, String detail}) handshake,
    required String logText,
  }) {
    final gameHint = diag != null && diag.gameId.isNotEmpty
        ? '（ag_game=${diag.gameId}）'
        : '';
    final overlayText = diag == null
        ? '未知'
        : (diag.overlayEnabled ? '已开启' : '未开启');
    final inviteText = diag == null
        ? '未知'
        : (diag.inviteDialogCalled ? '调用过' : '未调用');
    final b = StringBuffer()
      // 结论区：5 行以内，纯文本，方便直接判断，不必读事件流。
      ..writeln('===== 结论 =====')
      ..writeln('结果: ${success ? '成功' : '失败（${failure ?? '未知'}）'}')
      ..writeln(
        '角色: ${host ? '房主' : '客人'} | 大厅 id: '
        '${lobbyId.isEmpty ? '—' : lobbyId}$gameHint',
      )
      ..writeln(
        '进房: ${room.active ? '是' : '否'} | 成员: ${room.memberCount} 人 | '
        '传输: ${status.relayReady ? 'SDR 就绪' : 'SDR 未就绪'}'
        ' · ${room.active ? '隧道活跃' : '隧道未激活'}',
      )
      ..writeln('覆盖层: $overlayText | 邀请面板: $inviteText')
      ..writeln('===== 明细 =====')
      ..writeln('Astral Steam 双机自检')
      ..writeln('角色: ${host ? '房主' : '客人'}')
      ..writeln('开始: ${_fmt(startedAt)}')
      ..writeln('结束: ${_fmt(endedAt)}')
      ..writeln('结果: ${success ? '成功' : '失败（${failure ?? '未知'}）'}')
      ..writeln('模式: Steam 大厅搜房（走大厅: 是）')
      ..writeln('大厅 id: ${lobbyId.isEmpty ? '—' : lobbyId}')
      ..writeln('ag_game: ${diag?.gameId ?? '—'}')
      ..writeln('ag_ver: ${diag?.version ?? '—'}')
      ..writeln('ag_gate: ${diag?.gate ?? '—'}')
      ..writeln('joinable: ${diag == null ? '—' : (diag.joinable ? '是' : '否')}')
      ..writeln('成员: ${room.memberCount}/${diag?.capacity ?? 0}')
      ..writeln('传输: ${status.relayReady ? 'SDR 中继已就绪' : 'SDR 中继未就绪'}'
          ' · ${room.active ? '隧道房间活跃' : '隧道房间未激活'}')
      ..writeln('Steam: ${status.loggedOn ? '已登录' : '未登录'}'
          ' ${status.persona} ${status.steamId}'.trimRight())
      ..writeln('覆盖层: ${diag == null ? '未知' : (diag.overlayEnabled ? '已开启' : '未开启')}')
      ..writeln('邀请面板: ${diag == null ? '未知' : (diag.inviteDialogCalled ? '本次房间内调用过' : '未调用')}')
      ..writeln('握手: ${handshake.ok ? '已确认（${handshake.detail}）' : '未确认（${handshake.detail}）'}')
      ..writeln()
      ..writeln('成员列表:');
    if (room.members.isEmpty) {
      b.writeln('  （无）');
    } else {
      for (final m in room.members) {
        b.writeln(
          '  - ${m.steamId} ${m.nickname} '
          'self=${m.isSelf} host=${m.isHost} online=${m.online} '
          'vip=${m.virtualIp} latency=${m.latencyMs}ms '
          'via_relay=${m.viaRelay}',
        );
      }
    }
    b
      ..writeln()
      ..writeln('HELLO / WELCOME / KICK / BYE 事件:');
    final events = logText
        .split('\n')
        .where(
          (line) =>
              line.contains('hello_') ||
              line.contains('welcome') ||
              line.contains('kick') ||
              line.contains('bye'),
        )
        .toList();
    if (events.isEmpty) {
      b.writeln('  （无）');
    } else {
      for (final line in events) {
        b.writeln('  $line');
      }
    }
    if (diag?.overlayHint.isNotEmpty == true) {
      b
        ..writeln()
        ..writeln('覆盖层说明: ${diag!.overlayHint}');
    }
    b
      ..writeln()
      ..writeln('--- 引擎事件（本次自检期间）---')
      ..write(logText);
    return b.toString();
  }

  Future<String> _writeReport({
    required bool host,
    required DateTime startedAt,
    required String report,
  }) async {
    final desktop = getIt<ShortcutService>().desktopDirectory();
    if (desktop == null || desktop.isEmpty) {
      throw StateError('找不到桌面目录，无法导出自检日志');
    }
    final name =
        'astral-steam-selftest-${host ? 'host' : 'guest'}-${_stamp(startedAt)}.log';
    final file = File('$desktop\\$name');
    await file.writeAsString(report, flush: true);
    return file.path;
  }

  static String _fmt(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  static String _stamp(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}-'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  static String _two(int v) => v.toString().padLeft(2, '0');
}
