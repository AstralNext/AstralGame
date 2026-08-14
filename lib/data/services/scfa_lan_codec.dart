import 'dart:convert';
import 'dart:typed_data';

/// Supreme Commander / Forged Alliance LAN 发现包。
///
/// 探测：`6e 03 00`（原版）或 `8c 03 00`（驭空 / LEM）。
/// 应答：kind+1 + 长度 + 头 + KV（HostedBy / GameName / ProductCode / 地图…）。
const scfaLanVanillaProbe = [0x6E, 0x03, 0x00];
const scfaLanLoudProbe = [0x8C, 0x03, 0x00];

class ScfaLanInfo {
  const ScfaLanInfo({
    required this.lobbyPort,
    required this.gameName,
    this.hostedBy = '',
    this.mapName = '',
    this.scenarioFile = '',
    this.productCode = 'SC1',
    this.playerCount = 1,
    this.kind = 0x8D,
    this.address = '',
  });

  final int lobbyPort;
  final String gameName;
  final String hostedBy;
  final String mapName;
  final String scenarioFile;
  final String productCode;
  final int playerCount;
  final int kind;
  /// 对战 IP（KV `Address`）。引擎主要仍用来源 IP。
  final String address;
}

bool isScfaLanProbe(List<int> data) {
  if (data.length < 3) return false;
  return (data[0] == 0x6E || data[0] == 0x8C) &&
      data[1] == 0x03 &&
      data[2] == 0x00;
}

int scfaLanReplyKind(int requestKind) =>
    requestKind == 0x6E || requestKind == 0x8C ? requestKind + 1 : 0x8D;

Uint8List? buildScfaLanReply({
  required int requestKind,
  required String title,
  required int lobbyPort,
  String hostedBy = '',
  String mapName = '',
  String scenarioFile = '',
  String productCode = 'SC1',
  String address = '',
}) {
  if (lobbyPort <= 0 || lobbyPort > 65535) return null;
  final kind = scfaLanReplyKind(requestKind);
  final host = hostedBy.trim().isEmpty ? 'Player' : hostedBy.trim();
  final name = title.trim().isEmpty ? host : title.trim();
  final scenario = scenarioFile.trim().isNotEmpty
      ? scenarioFile.trim()
      : _scenarioForMap(mapName);
  final ip = address.trim();

  final scenarioOrDefault = scenario.isNotEmpty
      ? scenario
      : '/maps/scmp_039/scmp_039_scenario.lua';
  final options = BytesBuilder(copy: false)
    ..add(_kvStr('TeamLock', 'locked'))
    ..add(_kvStr('CheatsEnabled', 'false'))
    ..add(_kvBool('AllowObservers', true))
    ..add(_kvStr('Victory', 'demoralization'))
    ..add(_kvStr('PrebuiltUnits', 'Off'))
    ..add(_kvStr('CivilianAlliance', 'enemy'))
    ..add(_kvStr('Timeouts', '3'))
    ..add(_kvStr('NoRushOption', 'Off'))
    ..add(_kvStr('TeamSpawn', 'random'))
    ..add(_kvStr('ScenarioFile', scenarioOrDefault))
    ..add(_kvStr('UnitCap', '500'))
    ..add(_kvStr('GameSpeed', 'normal'))
    ..add(_kvStr('FogOfWar', 'explored'));

  final body = BytesBuilder(copy: false)
    ..add(_kvStr('HostedBy', host))
    ..add(_kvBlock('Options', options.takeBytes()))
    ..add(_kvStr('GameName', name))
    ..add(_kvStr('ProductCode', productCode.trim().isEmpty ? 'SC1' : productCode));
  if (ip.isNotEmpty) {
    body.add(_kvStr('Address', ip));
  }
  body.add(_kvFloat('PlayerCount', 1));
  body.add([0x05]);

  final extra = Uint8List(7)
    ..[0] = 0x0B
    ..[1] = 0x01
    ..[2] = 0x00
    ..[3] = 0x02
    ..[4] = lobbyPort & 0xFF
    ..[5] = (lobbyPort >> 8) & 0xFF
    ..[6] = 0x04;
  final payload = body.takeBytes();
  final length = 3 + extra.length + payload.length;
  final out = Uint8List(length)
    ..[0] = kind
    ..[1] = length & 0xFF
    ..[2] = (length >> 8) & 0xFF
    ..setRange(3, 10, extra)
    ..setRange(10, length, payload);
  return out;
}

ScfaLanInfo? parseScfaLanReply(Uint8List data, {int fallbackPort = 0}) {
  if (data.length < 10) return null;
  final kind = data[0];
  if (kind != 0x6F && kind != 0x8D) return null;
  final lobbyPort = data[7] | (data[8] << 8);
  final port = (lobbyPort > 0 && lobbyPort <= 65535) ? lobbyPort : fallbackPort;
  if (port <= 0) return null;

  final fields = _parseKv(data.sublist(10));
  final scenario = (fields['ScenarioFile'] ?? '').trim();
  final map = scfaMapNameFromScenario(scenario);
  return ScfaLanInfo(
    lobbyPort: port,
    gameName: (fields['GameName'] ?? '').trim(),
    hostedBy: (fields['HostedBy'] ?? '').trim(),
    mapName: map,
    scenarioFile: scenario,
    productCode: (fields['ProductCode'] ?? 'SC1').trim(),
    playerCount: int.tryParse(fields['PlayerCount'] ?? '') ?? 1,
    kind: kind,
    address: (fields['Address'] ?? '').trim(),
  );
}

String scfaMapNameFromScenario(String scenario) {
  final m = RegExp(r'(scmp_\d+|x1mp_\d+)', caseSensitive: false).firstMatch(scenario);
  if (m == null) return '';
  return _kMapNames[m.group(1)!.toLowerCase()] ?? m.group(1)!;
}

String _scenarioForMap(String mapName) {
  final needle = mapName.trim().toLowerCase();
  if (needle.isEmpty) return '';
  for (final e in _kMapNames.entries) {
    if (e.value.toLowerCase() == needle) {
      return '/maps/${e.key}/${e.key}_scenario.lua';
    }
  }
  final id = RegExp(r'(scmp_\d+|x1mp_\d+)', caseSensitive: false).firstMatch(mapName);
  if (id != null) {
    final key = id.group(1)!.toLowerCase();
    return '/maps/$key/${key}_scenario.lua';
  }
  return '';
}

final _kMapNames = <String, String>{
  'scmp_001': 'Burial Mounds',
  'scmp_009': "Seton's Clutch",
  'scmp_012': 'Theta Passage',
  'scmp_034': 'High Noon',
  'scmp_039': 'Four-Corners',
  'x1mp_001': 'Loki',
  'x1mp_005': 'Desert',
};

Uint8List _kvStr(String key, String value) {
  final k = utf8.encode(key);
  final v = utf8.encode(value);
  return Uint8List.fromList([0x01, ...k, 0x00, 0x01, ...v, 0x00]);
}

Uint8List _kvBool(String key, bool value) {
  final k = utf8.encode(key);
  return Uint8List.fromList([0x01, ...k, 0x00, 0x03, value ? 1 : 0]);
}

Uint8List _kvFloat(String key, double value) {
  final k = utf8.encode(key);
  final n = ByteData(4)..setFloat32(0, value, Endian.little);
  return Uint8List.fromList([0x01, ...k, 0x00, 0x00, ...n.buffer.asUint8List()]);
}

Uint8List _kvBlock(String key, Uint8List inner) {
  final k = utf8.encode(key);
  return Uint8List.fromList([0x01, ...k, 0x00, 0x04, ...inner, 0x05]);
}

Map<String, String> _parseKv(Uint8List data) {
  final out = <String, String>{};
  var i = 0;
  while (i < data.length) {
    final marker = data[i++];
    if (marker == 0x00 || marker == 0x04 || marker == 0x05) continue;
    if (marker != 0x01) continue;
    final key = _readCString(data, i);
    if (key == null) break;
    i = key.$2;
    if (i >= data.length) break;
    final vm = data[i++];
    if (vm == 0x01) {
      final val = _readCString(data, i);
      if (val == null) break;
      out[key.$1] = val.$1;
      i = val.$2;
    } else if (vm == 0x03) {
      if (i >= data.length) break;
      out[key.$1] = data[i++] == 1 ? 'true' : 'false';
    } else if (vm == 0x00 && i + 4 <= data.length) {
      final f = ByteData.sublistView(data, i, i + 4).getFloat32(0, Endian.little);
      out[key.$1] = f.round().toString();
      i += 4;
    } else if (vm == 0x04) {
      continue;
    }
  }
  return out;
}

(String, int)? _readCString(Uint8List data, int start) {
  var i = start;
  while (i < data.length && data[i] != 0) {
    i++;
  }
  if (i >= data.length) return null;
  return (utf8.decode(data.sublist(start, i), allowMalformed: true), i + 1);
}
