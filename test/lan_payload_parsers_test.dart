import 'dart:typed_data';

import 'package:astral_game/data/services/lan_payload_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _writeString(String s, int maxLen) {
  final bytes = Uint8List.fromList(s.codeUnits.take(maxLen).toList());
  return Uint8List.fromList([bytes.length, ...bytes]);
}

Uint8List _fakeServerData({
  String name = 'Host',
  String map = 'Map',
  int port = 6567,
}) {
  final out = BytesBuilder();
  void putInt(int v) {
    final b = ByteData(4)..setInt32(0, v);
    out.add(b.buffer.asUint8List());
  }

  void putShort(int v) {
    final b = ByteData(2)..setInt16(0, v);
    out.add(b.buffer.asUint8List());
  }

  out.add(_writeString(name, 100));
  out.add(_writeString(map, 64));
  putInt(3);
  putInt(12);
  putInt(146);
  out.add(_writeString('official', 32));
  out.add([0]);
  putInt(0);
  out.add(_writeString('desc', 100));
  out.add(_writeString('attack', 50));
  putShort(port);
  return out.toBytes();
}

void main() {
  test('mindustry_server parser reads NetworkIO layout', () {
    final parser = lanPayloadParserOf('mindustry_server');
    expect(parser, isNotNull);
    final hit = parser!(_fakeServerData(port: 7777), fallbackPort: 6567);
    expect(hit, isNotNull);
    expect(hit!.label, 'Host');
    expect(hit.motd, 'Map');
    expect(hit.port, 7777);
  });

  test('mindustry_server parser falls back when port short is 0', () {
    final parser = lanPayloadParserOf('mindustry_server')!;
    final hit = parser(_fakeServerData(port: 0), fallbackPort: 6567);
    expect(hit!.port, 6567);
  });
}
