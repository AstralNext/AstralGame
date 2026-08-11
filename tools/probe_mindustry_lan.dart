import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/services/lan_payload_parsers.dart';

Future<void> main() async {
  final probe = Uint8List.fromList([0xfe, 0x01]);
  final parser = lanPayloadParserOf('mindustry_server')!;
  final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  sock.broadcastEnabled = true;
  sock.readEventsEnabled = true;

  print('local ephemeral ${sock.address.address}:${sock.port}');

  final hits = <String>[];
  final sub = sock.listen((event) {
    if (event != RawSocketEvent.read) return;
    while (true) {
      final dg = sock.receive();
      if (dg == null || dg.data.isEmpty) break;
      final parsed = parser(dg.data, fallbackPort: 6567);
      final line =
          '<< ${dg.address.address}:${dg.port} len=${dg.data.length} -> $parsed';
      print(line);
      if (parsed != null) {
        hits.add('${parsed.label}:${parsed.port}');
      }
    }
  });

  void send(InternetAddress a, int p) {
    final n = sock.send(probe, a, p);
    print('>> fe01 -> ${a.address}:$p sent=$n');
  }

  send(InternetAddress.loopbackIPv4, 6567);
  send(InternetAddress('255.255.255.255'), 6567);
  send(InternetAddress('227.2.7.7'), 20151);

  await Future<void>.delayed(const Duration(milliseconds: 1500));
  await sub.cancel();
  sock.close();
  print(hits.isNotEmpty
      ? 'DART_DISCOVERY_OK hits=${hits.toSet()}'
      : 'DART_DISCOVERY_FAIL');
  exit(hits.isNotEmpty ? 0 : 1);
}
