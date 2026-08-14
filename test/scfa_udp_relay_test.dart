import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/services/scfa_udp_relay.dart';
import 'package:flutter_test/flutter_test.dart';

StreamSubscription<RawSocketEvent> _onRead(
  RawDatagramSocket socket,
  void Function(Datagram dg) onDatagram,
) {
  return socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    while (true) {
      final dg = socket.receive();
      if (dg == null) break;
      onDatagram(dg);
    }
  });
}

void main() {
  test('scfa udp relay forwards lobby datagrams both ways', () async {
    final host = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    host.readEventsEnabled = true;
    addTearDown(host.close);

    final relay = await ScfaUdpRelay.start(
      targetHost: '127.0.0.1',
      targetPort: host.port,
    );
    expect(relay, isNotNull);
    addTearDown(relay!.close);

    final client = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    client.readEventsEnabled = true;
    addTearDown(client.close);

    final toHost = Completer<Datagram>();
    final toClient = Completer<Datagram>();
    final subs = <StreamSubscription<RawSocketEvent>>[
      _onRead(host, (dg) {
        if (!toHost.isCompleted) toHost.complete(dg);
      }),
      _onRead(client, (dg) {
        if (!toClient.isCompleted) toClient.complete(dg);
      }),
    ];
    addTearDown(() async {
      for (final s in subs) {
        await s.cancel();
      }
    });

    client.send(
      Uint8List.fromList(const [1, 2, 3]),
      InternetAddress.loopbackIPv4,
      relay.port,
    );
    final hosted = await toHost.future.timeout(const Duration(seconds: 2));
    expect(hosted.data, [1, 2, 3]);

    host.send(
      Uint8List.fromList(const [9, 8]),
      hosted.address,
      hosted.port,
    );
    final echoed = await toClient.future.timeout(const Duration(seconds: 2));
    expect(echoed.data, [9, 8]);
  });
}
