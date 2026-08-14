import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/services/scfa_lan_codec.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/net_addr.dart';

class ScfaLanAnnounce {
  const ScfaLanAnnounce({
    required this.title,
    required this.lobbyPort,
    this.mapName,
    this.hostedBy,
    this.ipv4,
  });

  final String title;
  final int lobbyPort;
  final String? mapName;
  final String? hostedBy;
  /// 回包源 / KV Address：本机房主用虚拟 IP；远端房间留空（用 15000 听口来源 IP + 随机转发口）。
  final String? ipv4;
}

/// 本机 UDP 15000：替 FA 主机回答 LAN 搜索（驭空开房不听此口）。
class ScfaDiscoveryBeacon {
  ScfaDiscoveryBeacon._();
  static final ScfaDiscoveryBeacon instance = ScfaDiscoveryBeacon._();

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  int _port = 0;
  List<ScfaLanAnnounce> _ads = const [];
  final Map<int, DateTime> _localProbePorts = {};
  /// 按回包源 IP 缓存 socket（本机 VIP / 127.0.0.1 可并存）。
  final Map<String, RawDatagramSocket> _replyByIp = {};

  bool get isRunning => _socket != null;
  int get port => _port;

  /// 最近几秒内对本口发过探测的本地源端口（搜索端，不是开房口）。
  Set<int> get searcherPorts {
    final now = DateTime.now();
    _localProbePorts.removeWhere(
      (_, at) => now.difference(at) > const Duration(seconds: 6),
    );
    return _localProbePorts.keys.toSet();
  }

  Future<void> start({int port = 15000}) async {
    if (!Platform.isWindows) return;
    if (_socket != null && _port == port) return;
    await stop();
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;
      _socket = socket;
      _port = port;
      _sub = socket.listen(_onEvent);
      appLogger.i('[ScfaBeacon] 已听 UDP :$port');
    } catch (e) {
      appLogger.w('[ScfaBeacon] 绑定 :$port 失败: $e');
    }
  }

  void publish(List<ScfaLanAnnounce> ads) {
    _ads = [
      for (final a in ads)
        if (a.lobbyPort > 0 && a.lobbyPort <= 65535) a,
    ];
    final ips = <String>{
      for (final a in _ads)
        if ((stripIpv4Host(a.ipv4) ?? '').isNotEmpty) stripIpv4Host(a.ipv4)!,
    };
    unawaited(_syncReplySockets(ips));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    for (final s in _replyByIp.values) {
      s.close();
    }
    _replyByIp.clear();
    _port = 0;
    _ads = const [];
    _localProbePorts.clear();
  }

  Future<void> _syncReplySockets(Set<String> ips) async {
    final stale = _replyByIp.keys.where((k) => !ips.contains(k)).toList();
    for (final k in stale) {
      _replyByIp.remove(k)?.close();
    }
    for (final ip in ips) {
      if (_replyByIp.containsKey(ip)) continue;
      try {
        RawDatagramSocket? sock;
        if (_port > 0) {
          try {
            sock = await RawDatagramSocket.bind(
              InternetAddress(ip),
              _port,
            );
          } catch (_) {
            sock = null;
          }
        }
        sock ??= await RawDatagramSocket.bind(InternetAddress(ip), 0);
        sock.broadcastEnabled = true;
        _replyByIp[ip] = sock;
        appLogger.i('[ScfaBeacon] 回包源 $ip:${sock.port}');
      } catch (e) {
        appLogger.d('[ScfaBeacon] 绑定回包源 $ip 失败: $e');
      }
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final listen = _socket;
    if (listen == null) return;
    while (true) {
      final dg = listen.receive();
      if (dg == null) break;
      _handle(listen, dg);
    }
  }

  void _handle(RawDatagramSocket listen, Datagram dg) {
    if (!isScfaLanProbe(dg.data)) return;
    final ip = dg.address.address;
    final local = ip == '127.0.0.1' ||
        ip == '::1' ||
        ip.startsWith('192.168.') ||
        ip.startsWith('10.') ||
        ip.startsWith('172.');
    if (local) {
      _localProbePorts[dg.port] = DateTime.now();
    }
    if (_ads.isEmpty) return;
    final kind = dg.data[0];
    for (final ad in _ads) {
      final bindIp = stripIpv4Host(ad.ipv4) ?? '';
      final out = (bindIp.isNotEmpty ? _replyByIp[bindIp] : null) ?? listen;
      final reply = buildScfaLanReply(
        requestKind: kind,
        title: ad.title,
        lobbyPort: ad.lobbyPort,
        hostedBy: ad.hostedBy ?? '',
        mapName: ad.mapName ?? '',
        address: bindIp.isNotEmpty ? bindIp : (ad.ipv4 ?? '').trim(),
      );
      if (reply == null || reply.isEmpty) continue;
      try {
        out.send(reply, dg.address, dg.port);
      } catch (e) {
        appLogger.d('[ScfaBeacon] 回包失败 ${dg.address.address}:${dg.port}: $e');
      }
    }
  }
}
