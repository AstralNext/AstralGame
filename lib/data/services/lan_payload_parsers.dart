import 'dart:convert';
import 'dart:typed_data';

/// 主动探测 / 被动监听共用的载荷解析结果。
class LanPayloadHit {
  const LanPayloadHit({
    required this.port,
    required this.label,
    this.motd,
  });

  final int port;
  final String label;
  final String? motd;
}

/// 按 JSON `parser` 名分发；新游戏加解析函数即可，不必新 discoverer 类型。
typedef LanPayloadParser = LanPayloadHit? Function(
  Uint8List data, {
  required int fallbackPort,
});

final Map<String, LanPayloadParser> _lanPayloadParsers = {
  'mindustry_server': parseMindustryServerPayload,
};

LanPayloadParser? lanPayloadParserOf(String name) {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  return _lanPayloadParsers[key];
}

void registerLanPayloadParser(String name, LanPayloadParser parser) {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return;
  _lanPayloadParsers[key] = parser;
}

/// Mindustry `NetworkIO.writeServerData()`（UTF-8 长度前缀字符串 + big-endian）。
LanPayloadHit? parseMindustryServerPayload(
  Uint8List data, {
  required int fallbackPort,
}) {
  try {
    final r = _ByteReader(data);
    final name = r.readString(maxLen: 100);
    final map = r.readString(maxLen: 64);
    r.readInt32(); // players
    r.readInt32(); // wave
    r.readInt32(); // version build
    r.readString(); // vertype
    r.readByte(); // gamemode
    r.readInt32(); // player limit
    r.readString(maxLen: 100); // description
    r.readString(maxLen: 50); // modeName
    final portShort = r.readInt16();
    final port = portShort != 0 ? portShort : fallbackPort;
    if (port <= 0 || port > 65535) return null;
    return LanPayloadHit(
      port: port,
      label: name.isNotEmpty ? name : 'Mindustry',
      motd: map.isEmpty ? null : map,
    );
  } catch (_) {
    return null;
  }
}

class _ByteReader {
  _ByteReader(this.bytes);
  final Uint8List bytes;
  int _o = 0;

  int readByte() {
    if (_o >= bytes.length) throw StateError('eof');
    return bytes[_o++];
  }

  int readInt16() {
    final b0 = readByte();
    final b1 = readByte();
    var v = (b0 << 8) | b1;
    if (v > 0x7fff) v -= 0x10000;
    return v;
  }

  int readInt32() {
    final b0 = readByte();
    final b1 = readByte();
    final b2 = readByte();
    final b3 = readByte();
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
  }

  String readString({int maxLen = 32}) {
    final len = readByte() & 0xff;
    if (len > maxLen || _o + len > bytes.length) {
      throw StateError('bad string');
    }
    final slice = bytes.sublist(_o, _o + len);
    _o += len;
    return utf8.decode(slice, allowMalformed: true);
  }
}
