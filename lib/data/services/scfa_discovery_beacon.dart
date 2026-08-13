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
  /// EasyTier 虚拟 IP；15000 回包从此地址发出，游戏用这个 IP 连大厅。
  final String? ipv4;
}

/// 本机 UDP 15000：替 FA 主机回答 LAN 搜索（驭空开房不听此口）。
class ScfaDiscoveryBeacon {
  ScfaDiscoveryBeacon._();
  static final ScfaDiscoveryBeacon instance = ScfaDiscoveryBeacon._();

  RawDatagramSocket? _socket;
  RawDatagramSocket? _replySocket;
  StreamSubscription<RawSocketEvent>? _sub;
  int _port = 0;
  String _replyBind = '';
  List<ScfaLanAnnounce> _ads = const [];
  final Map<int, DateTime> _localProbePorts = {};

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
    final ip = stripIpv4Host(
      _ads.map((a) => a.ipv4).firstWhere(
            (s) => (s ?? '').trim().isNotEmpty,
            orElse: () => null,
          ),
    );
    unawaited(_ensureReplySocket(ip));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    _replySocket?.close();
    _replySocket = null;
    _port = 0;
    _replyBind = '';
    _ads = const [];
    _localProbePorts.clear();
  }

  Future<void> _ensureReplySocket(String? ipv4) async {
    final ip = (ipv4 ?? '').trim();
    if (ip.isEmpty) {
      _replySocket?.close();
      _replySocket = null;
      _replyBind = '';
      return;
    }
    if (_replyBind == ip && _replySocket != null) return;
    _replySocket?.close();
    _replySocket = null;
    _replyBind = '';
    try {
      // 尽量绑虚拟 IP:15000，让游戏看到来源就是大厅发现口。
      RawDatagramSocket? sock;
      if (_port > 0) {
        try {
          sock = await RawDatagramSocket.bind(
            InternetAddress(ip),
            _port,
            reuseAddress: true,
          );
        } catch (_) {
          sock = null;
        }
      }
      sock ??= await RawDatagramSocket.bind(InternetAddress(ip), 0);
      sock.broadcastEnabled = true;
      _replySocket = sock;
      _replyBind = ip;
      appLogger.i('[ScfaBeacon] 回包源 $ip:${sock.port}');
    } catch (e) {
      appLogger.d('[ScfaBeacon] 绑定回包源 $ip 失败: $e');
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
    final out = _replySocket ?? listen;
    for (final ad in _ads) {
      final reply = buildScfaLanReply(
        requestKind: kind,
        title: ad.title,
        lobbyPort: ad.lobbyPort,
        hostedBy: ad.hostedBy ?? '',
        mapName: ad.mapName ?? '',
        address: (ad.ipv4 ?? _replyBind).trim(),
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
