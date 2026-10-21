import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/server_probe_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('udp probe 收到 EasyTier SACK 时判定为 ET', () async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = socket.port;
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      final data = dg.data;
      if (data.length != 16) return;
      final view = ByteData.sublistView(data);
      if (view.getUint8(4) != 1) return;
      final reply = ByteData(16);
      reply.setUint32(0, view.getUint32(0, Endian.little), Endian.little);
      reply.setUint8(4, 2);
      reply.setUint8(5, 0);
      reply.setUint16(6, 8, Endian.little);
      reply.setUint64(8, view.getUint64(8, Endian.little), Endian.little);
      socket.send(reply.buffer.asUint8List(), dg.address, dg.port);
    });

    final result = await ServerProbeService().probe(
      ServerMod(name: 't', url: 'udp://127.0.0.1:$port'),
    );
    expect(result.isEasyTier, isTrue);
    expect(result.latencyMs, isNotNull);

    await sub.cancel();
    socket.close();
  });
}
