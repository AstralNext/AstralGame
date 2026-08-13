import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/lan_relay_status.dart';
import 'package:astral_game/data/models/open_game_listing.dart';
import 'package:astral_game/data/services/lan_payload_builders.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_rust_core/astral_rust_core.dart';
import 'package:signals/signals_core.dart';

/// 只跟「开放游戏」通道走：listing 出现 → 本机组播 + 127 转发；消失立刻关。
///
/// 不监听本机组播。发现仍由房主侧 discoverer 负责；本类只消费通道里的目标。
class LanLocalRelay {
  RawDatagramSocket? _socket;
  Timer? _tick;
  final Map<String, _ActiveRelay> _active = {};

  /// UI：listing.key → 本机继电器状态。
  final statuses = signal<Map<String, LanRelayStatus>>(const {});

  Future<void> sync({
    required List<OpenGameListing> remotes,
    required List<GameAssistLanGameDiscoverEntry> entries,
  }) async {
    final wanted = <String, _RelaySpec>{};
    for (final listing in remotes) {
      if (listing.isSelf || listing.isExpired) continue;
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
          '${spec.bindHost}:${spec.gamePort} → ${spec.targetHost}:${spec.targetPort}',
        );
      }
    }

    _publishStatuses();
    _ensureTicker();
    if (_active.values.any((e) => e.spec.inject)) {
      unawaited(_beaconOnce());
    }
  }

  Future<void> stop() async {
    _tick?.cancel();
    _tick = null;
    final all = _active.values.toList();
    _active.clear();
    _publishStatuses();
    for (final s in all) {
      await _stopOne(s);
    }
    _socket?.close();
    _socket = null;
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
    final inject = entry.paramBool('inject_local', canBuild);
    final forward = entry.paramBool('forward_local', canBuild);
    if (!inject && !forward) return null;

    final bind = entry.paramString('inject_bind') ?? '127.0.0.1';
    final title = (listing.motd?.trim().isNotEmpty == true)
        ? listing.motd!.trim()
        : listing.label;
    Uint8List? payload;
    if (inject && canBuild) {
      payload = lanPayloadBuilderOf(parser)?.call(
        title: title,
        port: listing.port,
      );
    }
    return _RelaySpec(
      key: listing.key,
      inject: inject && payload != null && payload.isNotEmpty,
      forward: forward,
      bindHost: bind,
      gamePort: listing.port,
      targetHost: listing.ipv4,
      targetPort: listing.port,
      multicast: (entry.multicast ?? '').trim(),
      multicastPort: entry.multicastPort ?? 0,
      injectMode: (entry.paramString('inject_mode') ?? 'both').toLowerCase(),
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

  Future<RawDatagramSocket> _socketOn(String bindHost) async {
    final existing = _socket;
    if (existing != null && existing.address.address == bindHost) {
      return existing;
    }
    existing?.close();
    final socket = await RawDatagramSocket.bind(
      InternetAddress(bindHost),
      0,
    );
    socket.broadcastEnabled = true;
    _socket = socket;
    return socket;
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
    if (!spec.inject && forwardIndex == null) return null;
    return _ActiveRelay(
      spec: spec,
      forwardIndex: forwardIndex,
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
    final needInject = _active.values.any((e) => e.spec.inject);
    if (!needInject) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    _tick ??= Timer.periodic(const Duration(milliseconds: 1500), (_) {
      unawaited(_beaconOnce());
    });
  }

  Future<void> _beaconOnce() async {
    final specs = _active.values.map((e) => e.spec).where((s) => s.inject);
    if (specs.isEmpty) return;
    for (final spec in specs) {
      final payload = spec.payload;
      if (payload == null || payload.isEmpty) continue;
      try {
        final socket = await _socketOn(spec.bindHost);
        final mode = spec.injectMode;
        if (mode == 'loopback' || mode == 'both') {
          socket.send(
            payload,
            InternetAddress(spec.bindHost),
            spec.multicastPort > 0 ? spec.multicastPort : spec.gamePort,
          );
        }
        if ((mode == 'multicast' || mode == 'both') &&
            spec.multicast.isNotEmpty &&
            spec.multicastPort > 0) {
          try {
            socket.send(
              payload,
              InternetAddress(spec.multicast),
              spec.multicastPort,
            );
          } catch (_) {}
        }
      } catch (e) {
        appLogger.d('[LanRelay] 注入失败 ${spec.key}: $e');
      }
    }
  }
}

class _RelaySpec {
  _RelaySpec({
    required this.key,
    required this.inject,
    required this.forward,
    required this.bindHost,
    required this.gamePort,
    required this.targetHost,
    required this.targetPort,
    required this.multicast,
    required this.multicastPort,
    required this.injectMode,
    required this.payload,
  });

  final String key;
  final bool inject;
  final bool forward;
  final String bindHost;
  final int gamePort;
  final String targetHost;
  final int targetPort;
  final String multicast;
  final int multicastPort;
  final String injectMode;
  final Uint8List? payload;

  bool sameRuntime(_RelaySpec o) =>
      inject == o.inject &&
      forward == o.forward &&
      bindHost == o.bindHost &&
      gamePort == o.gamePort &&
      targetHost == o.targetHost &&
      targetPort == o.targetPort &&
      multicast == o.multicast &&
      multicastPort == o.multicastPort &&
      injectMode == o.injectMode &&
      _bytesEq(payload, o.payload);
}

class _ActiveRelay {
  _ActiveRelay({
    required this.spec,
    this.forwardIndex,
    this.forwardOk = false,
  });
  _RelaySpec spec;
  final BigInt? forwardIndex;
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
