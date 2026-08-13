import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/lan_relay_status.dart';
import 'package:astral_game/data/models/open_game_listing.dart';
import 'package:astral_game/data/services/lan_inject_guard.dart';
import 'package:astral_game/data/services/lan_payload_builders.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_rust_core/astral_rust_core.dart';
import 'package:signals/signals_core.dart';

/// 只跟「开放游戏」通道走：listing 出现 → 本机组播 + 127 转发；消失立刻关。
///
/// 仅 Windows。不监听本机组播；发现仍由房主侧 discoverer 负责，本类只消费通道目标。
class LanLocalRelay {
  RawDatagramSocket? _uniSocket;
  Timer? _tick;
  DateTime? _lastMcastLogAt;
  final Map<String, _ActiveRelay> _active = {};

  /// UI：listing.key → 本机继电器状态。
  final statuses = signal<Map<String, LanRelayStatus>>(const {});

  Future<void> sync({
    required List<OpenGameListing> remotes,
    required List<GameAssistLanGameDiscoverEntry> entries,
  }) async {
    if (!Platform.isWindows) {
      await stop();
      return;
    }
    final wanted = <String, _RelaySpec>{};
    for (final listing in remotes) {
      if (listing.isExpired) continue;
      final spec = _specFor(listing, entries);
      if (spec == null) continue;
      wanted[listing.key] = spec;
    }

    final stale = _active.keys.where((k) => !wanted.containsKey(k)).toList();
    for (final k in stale) {
      await _stopOne(_active.remove(k));
    }

    for (final spec in wanted.values) {
      final prev = _active[spec.key];
      if (prev != null && prev.spec.sameRuntime(spec)) {
        prev.spec = spec;
        continue;
      }
      if (prev != null) await _stopOne(_active.remove(spec.key));
      final next = await _startOne(spec);
      if (next != null) {
        _active[spec.key] = next;
        appLogger.i(
          '[LanRelay] 通道触发 ${spec.key} '
          'inject=${spec.inject} forward=${spec.forward} '
          'mcast=${spec.injectMulticast} loop=${spec.injectLoopback} '
          '${spec.bindHost}:${spec.gamePort} → ${spec.targetHost}:${spec.targetPort}',
        );
      }
    }

    _publishStatuses();
    _refreshInjectGuard();
    _ensureTicker();
    if (_active.values.any((e) => e.spec.injectLoopback)) {
      unawaited(_beaconOnce());
    } else if (_active.values.any((e) => e.mcastIndex != null)) {
      final now = DateTime.now();
      if (_lastMcastLogAt == null ||
          now.difference(_lastMcastLogAt!) > const Duration(seconds: 8)) {
        _lastMcastLogAt = now;
        final n = _active.values.where((e) => e.mcastIndex != null).length;
        appLogger.i('[LanRelay] 组播发送中 $n 条 → 224.0.2.60:4445');
      }
    }
  }

  Future<void> stop() async {
    _tick?.cancel();
    _tick = null;
    final all = _active.values.toList();
    _active.clear();
    _publishStatuses();
    LanInjectGuard.clear();
    for (final s in all) {
      await _stopOne(s);
    }
    _uniSocket?.close();
    _uniSocket = null;
    try {
      await stopAllMulticastSenders();
    } catch (_) {}
  }

  _RelaySpec? _specFor(
    OpenGameListing listing,
    List<GameAssistLanGameDiscoverEntry> entries,
  ) {
    final entry = _entryFor(listing, entries);
    if (entry == null) {
      appLogger.d(
        '[LanRelay] 无匹配规则，跳过 ${listing.key} adId=${listing.adId}',
      );
      return null;
    }
    final parser = (entry.parser ?? '').trim();
    final canBuild = parser.isNotEmpty && lanPayloadBuilderOf(parser) != null;
    // 有重建器就注入/转发；本机只组播，同伴再 127 单播 + TCP。
    final inject = canBuild;
    final forward = canBuild && !listing.isSelf;
    if (!inject && !forward) return null;

    final title = (listing.motd?.trim().isNotEmpty == true)
        ? listing.motd!.trim()
        : listing.label;
    Uint8List? payload;
    if (inject) {
      payload = lanPayloadBuilderOf(parser)?.call(
        title: title,
        port: listing.port,
      );
    }
    final hasPayload = payload != null && payload.isNotEmpty;
    final wantMcast = inject && hasPayload;
    final wantLoop = inject && hasPayload && !listing.isSelf;
    if (!wantMcast && !wantLoop && !forward) return null;

    return _RelaySpec(
      key: listing.key,
      inject: wantMcast || wantLoop,
      injectMulticast: wantMcast,
      injectLoopback: wantLoop,
      forward: forward,
      bindHost: '127.0.0.1',
      gamePort: listing.port,
      targetHost: listing.ipv4,
      targetPort: listing.port,
      multicast: (entry.multicast ?? '').trim(),
      multicastPort: entry.multicastPort,
      payload: payload,
    );
  }

  GameAssistLanGameDiscoverEntry? _entryFor(
    OpenGameListing listing,
    List<GameAssistLanGameDiscoverEntry> entries,
  ) {
    if (entries.isEmpty) return null;
    final adId = listing.adId.trim();
    for (final e in entries) {
      if (adId == e.id || adId.startsWith('${e.id}:')) return e;
    }
    for (final e in entries) {
      final parser = (e.parser ?? '').trim();
      if (parser.isNotEmpty && lanPayloadBuilderOf(parser) != null) return e;
    }
    for (final e in entries) {
      if ((e.multicast ?? '').trim().isNotEmpty) return e;
    }
    return entries.first;
  }

  Future<RawDatagramSocket> _uniOn(String bindHost) async {
    final existing = _uniSocket;
    if (existing != null && existing.address.address == bindHost) {
      return existing;
    }
    existing?.close();
    final socket = await RawDatagramSocket.bind(InternetAddress(bindHost), 0);
    socket.broadcastEnabled = true;
    _uniSocket = socket;
    return socket;
  }

  void _refreshInjectGuard() {
    LanInjectGuard.replaceEntries([
      for (final s in _active.values)
        if (s.spec.inject)
          (s.spec.gamePort, _motdFromPayload(s.spec.payload)),
    ]);
  }

  String _motdFromPayload(Uint8List? payload) {
    if (payload == null || payload.isEmpty) return '';
    final s = utf8.decode(payload, allowMalformed: true);
    const open = '[MOTD]';
    const close = '[/MOTD]';
    final a = s.indexOf(open);
    final b = s.indexOf(close);
    if (a >= 0 && b > a) {
      return s.substring(a + open.length, b).trim();
    }
    return s.trim();
  }

  Future<_ActiveRelay?> _startOne(_RelaySpec spec) async {
    BigInt? forwardIndex;
    if (spec.forward) {
      final listen = '${spec.bindHost}:${spec.gamePort}';
      final target = '${spec.targetHost}:${spec.targetPort}';
      try {
        forwardIndex = await createForwardServer(
          listenAddr: listen,
          forwardAddr: target,
        );
        appLogger.i('[LanRelay] TCP $listen → $target (index=$forwardIndex)');
      } catch (e) {
        appLogger.w('[LanRelay] TCP 转发失败 $listen → $target: $e');
      }
    }
    BigInt? mcastIndex;
    if (spec.injectMulticast &&
        spec.multicast.isNotEmpty &&
        spec.multicastPort > 0 &&
        spec.payload != null) {
      try {
        mcastIndex = await createMulticastSender(
          multicastAddr: spec.multicast,
          port: spec.multicastPort,
          data: spec.payload!,
          intervalMs: BigInt.from(1500),
        );
        appLogger.i(
          '[LanRelay] 组播 ${spec.multicast}:${spec.multicastPort} '
          '(index=$mcastIndex)',
        );
      } catch (e) {
        appLogger.w(
          '[LanRelay] 组播启动失败 ${spec.multicast}:${spec.multicastPort}: $e',
        );
      }
    }
    if (!spec.inject && forwardIndex == null && mcastIndex == null) return null;
    return _ActiveRelay(
      spec: spec,
      forwardIndex: forwardIndex,
      mcastIndex: mcastIndex,
      forwardOk: forwardIndex != null,
    );
  }

  Future<void> _stopOne(_ActiveRelay? session) async {
    if (session == null) return;
    final idx = session.forwardIndex;
    if (idx != null) {
      try {
        await stopForwardServer(index: idx);
      } catch (e) {
        appLogger.d('[LanRelay] 停止转发失败 index=$idx: $e');
      }
    }
    final midx = session.mcastIndex;
    if (midx != null) {
      try {
        await stopMulticastSender(index: midx);
      } catch (e) {
        appLogger.d('[LanRelay] 停止组播失败 index=$midx: $e');
      }
    }
  }

  void _publishStatuses() {
    statuses.value = {
      for (final e in _active.entries)
        e.key: LanRelayStatus(
          listingKey: e.key,
          localEndpoint: '${e.value.spec.bindHost}:${e.value.spec.gamePort}',
          remoteEndpoint:
              '${e.value.spec.targetHost}:${e.value.spec.targetPort}',
          inject: e.value.spec.inject,
          forward: e.value.forwardOk,
        ),
    };
  }

  void _ensureTicker() {
    final needLoop = _active.values.any((e) => e.spec.injectLoopback);
    if (!needLoop) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    _tick ??= Timer.periodic(const Duration(milliseconds: 1500), (_) {
      unawaited(_beaconOnce());
    });
  }

  Future<void> _beaconOnce() async {
    final specs =
        _active.values.map((e) => e.spec).where((s) => s.injectLoopback);
    if (specs.isEmpty) return;
    for (final spec in specs) {
      final payload = spec.payload;
      if (payload == null || payload.isEmpty) continue;
      try {
        final uni = await _uniOn(spec.bindHost);
        uni.send(
          payload,
          InternetAddress(spec.bindHost),
          spec.multicastPort > 0 ? spec.multicastPort : spec.gamePort,
        );
      } catch (e) {
        appLogger.w('[LanRelay] 回环注入失败 ${spec.key}: $e');
      }
    }
    final now = DateTime.now();
    if (_lastMcastLogAt == null ||
        now.difference(_lastMcastLogAt!) > const Duration(seconds: 8)) {
      _lastMcastLogAt = now;
      final mcastN =
          _active.values.where((e) => e.mcastIndex != null).length;
      if (mcastN > 0) {
        appLogger.i('[LanRelay] 组播发送中 $mcastN 条 → 224.0.2.60:4445');
      }
    }
  }
}

class _RelaySpec {
  _RelaySpec({
    required this.key,
    required this.inject,
    required this.injectMulticast,
    required this.injectLoopback,
    required this.forward,
    required this.bindHost,
    required this.gamePort,
    required this.targetHost,
    required this.targetPort,
    required this.multicast,
    required this.multicastPort,
    required this.payload,
  });

  final String key;
  final bool inject;
  final bool injectMulticast;
  final bool injectLoopback;
  final bool forward;
  final String bindHost;
  final int gamePort;
  final String targetHost;
  final int targetPort;
  final String multicast;
  final int multicastPort;
  final Uint8List? payload;

  bool sameRuntime(_RelaySpec o) =>
      inject == o.inject &&
      injectMulticast == o.injectMulticast &&
      injectLoopback == o.injectLoopback &&
      forward == o.forward &&
      bindHost == o.bindHost &&
      gamePort == o.gamePort &&
      targetHost == o.targetHost &&
      targetPort == o.targetPort &&
      multicast == o.multicast &&
      multicastPort == o.multicastPort &&
      _bytesEq(payload, o.payload);
}

class _ActiveRelay {
  _ActiveRelay({
    required this.spec,
    this.forwardIndex,
    this.mcastIndex,
    this.forwardOk = false,
  });
  _RelaySpec spec;
  final BigInt? forwardIndex;
  final BigInt? mcastIndex;
  final bool forwardOk;
}

bool _bytesEq(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
