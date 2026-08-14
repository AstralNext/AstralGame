import 'dart:async';
import 'dart:io';

/// 本机 UDP 随机口 ↔ 房主虚拟 IP:大厅口。FA 大厅是 UDP，不能走 TCP 转发。
class ScfaUdpRelay {
  ScfaUdpRelay._(this._socket, this._target, this._targetPort);

  final RawDatagramSocket _socket;
  final InternetAddress _target;
  final int _targetPort;
  StreamSubscription<RawSocketEvent>? _sub;
  InternetAddress? _client;
  int? _clientPort;

  int get port => _socket.port;

  static Future<ScfaUdpRelay?> start({
    required String targetHost,
    required int targetPort,
  }) async {
    if (targetPort <= 0 || targetPort > 65535) return null;
    final ip = targetHost.trim();
    if (ip.isEmpty) return null;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.readEventsEnabled = true;
      final relay = ScfaUdpRelay._(
        socket,
        InternetAddress(ip),
        targetPort,
      );
      relay._sub = socket.listen(relay._onEvent);
      return relay;
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _socket.close();
    _client = null;
    _clientPort = null;
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    while (true) {
      final dg = _socket.receive();
      if (dg == null) break;
      _forward(dg);
    }
  }

  void _forward(Datagram dg) {
    final fromTarget =
        dg.address.address == _target.address && dg.port == _targetPort;
    if (fromTarget) {
      final client = _client;
      final port = _clientPort;
      if (client == null || port == null) return;
      try {
        _socket.send(dg.data, client, port);
      } catch (_) {}
      return;
    }
    _client = dg.address;
    _clientPort = dg.port;
    try {
      _socket.send(dg.data, _target, _targetPort);
    } catch (_) {}
  }
}
