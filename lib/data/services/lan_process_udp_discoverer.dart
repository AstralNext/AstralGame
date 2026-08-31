import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/services/lan_game_discoverers.dart';
import 'package:astral_game/data/services/scfa_discovery_beacon.dart';
import 'package:astral_game/data/services/scfa_lan_codec.dart';
import 'package:astral_game/data/services/windows_game_process.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/runtime_platform.dart';

/// `process_udp`：按进程名 / 窗口标题找游戏，取其 UDP 对战口。
///
/// FA 驭空开房不听 15000；本发现器额外挂 [ScfaDiscoveryBeacon] 代答 LAN 搜索。
class ProcessUdpDiscoverer extends LanGameDiscoverer {
@override
String get type => 'process_udp';

bool _beaconMine = false;
int? _lastLobbyPort;

@override
Future<void> start(GameAssistLanGameDiscoverEntry entry) async {
if ((entry.parser ?? '').trim().toLowerCase() == 'scfa_lan') {
await ScfaDiscoveryBeacon.instance.start(
port: entry.beaconPort > 0 ? entry.beaconPort : 15000,
);
_beaconMine = true;
}
}

@override
Future<void> stop() async {
_lastLobbyPort = null;
if (_beaconMine) {
await ScfaDiscoveryBeacon.instance.stop();
_beaconMine = false;
}
}

@override
Future<List<DiscoveredGameHit>> poll(
GameAssistLanGameDiscoverEntry entry,
) async {
if (!RuntimePlatform.isWindows) return const [];
final procs = await listWindowsGameProcesses(
exeNames: entry.process.isNotEmpty
? entry.process
: const ['game.exe', 'forgedalliance.exe', 'supremecommander.exe'],
windowNeedles: entry.window.isNotEmpty
? entry.window
: const ['Forged Alliance', 'Supreme Commander'],
);
if (procs.isEmpty) return const [];

final searcher = ScfaDiscoveryBeacon.instance.searcherPorts;
final beaconPort = ScfaDiscoveryBeacon.instance.isRunning
? ScfaDiscoveryBeacon.instance.port
: (entry.beaconPort > 0 ? entry.beaconPort : 15000);
final out = <int, DiscoveredGameHit>{};

final scfa = (entry.parser ?? '').trim().toLowerCase() == 'scfa_lan';
for (final p in procs) {
final map = await _mapFromNearbyLogs(p.path);
final candidates = [
for (final port in p.udpPorts)
if (port > 0 &&
port != beaconPort &&
!searcher.contains(port) &&
!isNonLobbyUdpPort(port))
port,
];
final probedByPort = <int, ScfaLanInfo>{};
if (scfa && candidates.isNotEmpty) {
final rows = await Future.wait([
for (final port in candidates)
_probeLobby(port).then((info) => (port, info)),
]);
for (final (port, info) in rows) {
if (info != null) probedByPort[port] = info;
}
}
final lobbyPorts = scfa
? selectScfaLobbyPorts(
udpPorts: candidates,
probedOk: probedByPort.keys.toSet(),
lastLobbyPort: _lastLobbyPort,
)
: candidates;
if (scfa) {
final skipped = [
for (final port in candidates)
if (!lobbyPorts.contains(port)) port,
];
if (skipped.isNotEmpty) {
appLogger.d('[LanDiscover] process_udp skip peer ports=${skipped.join(",")}');
}
if (lobbyPorts.isNotEmpty) {
final prev = _lastLobbyPort;
_lastLobbyPort =
(prev != null && lobbyPorts.contains(prev)) ? prev : lobbyPorts.first;
}
}
for (final port in lobbyPorts) {
final probed = probedByPort[port];
final mapName = (probed?.mapName.isNotEmpty == true)
? probed!.mapName
: (map ?? '');
final label = (probed != null && probed.gameName.isNotEmpty)
? probed.gameName
: (entry.label.trim().isNotEmpty ? entry.label : 'Forged Alliance');
out[port] = DiscoveredGameHit(
port: port,
label: label,
motd: mapName.isEmpty ? null : mapName,
parser: (entry.parser ?? '').trim().isEmpty ? null : entry.parser,
);
}
}

if (out.isNotEmpty) {
appLogger.d(
'[LanDiscover] process_udp hits='
'${out.values.map((h) => '${h.port}/${h.motd ?? "-"}').join(",")}',
);
}
return out.values.toList(growable: false);
}
}

/// scfa_lan 选大厅口。驭空对战口经常不回 LAN 探测，失败不能当成「连接口」。
///
/// 优先：探测成功的口 → 上次已确认的大厅 → 只剩一个候选就用它。
/// 玩家加入后多出来、又探不到的口再丢掉。
List<int> selectScfaLobbyPorts({
required Iterable<int> udpPorts,
required Set<int> probedOk,
int? lastLobbyPort,
}) {
final live = [
for (final p in udpPorts)
if (p > 0) p,
];
if (live.isEmpty) return const [];
final probed = [for (final p in live) if (probedOk.contains(p)) p];
if (probed.isNotEmpty) return probed;
final last = lastLobbyPort;
if (last != null && live.contains(last)) return [last];
if (live.length == 1) return live;
return const [];
}

/// 进程常顺带开的系统 / 平台 UDP，不是房间对战口。
///
/// 5353 = mDNS（Bonjour / Steam 本地发现），Steam 注入进 `game.exe` 后会时开时关。
bool isNonLobbyUdpPort(int port) {
if (port < 1024) return true;
switch (port) {
case 1900: // SSDP
case 3478: // STUN
case 4380: // Steam
case 5353: // mDNS
case 5355: // LLMNR
case 19302: // Google STUN
case 27036: // Steam
return true;
default:
return false;
}
}

Future<ScfaLanInfo?> _probeLobby(int port) async {
RawDatagramSocket? socket;
try {
socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
socket.readEventsEnabled = true;
socket.send(
Uint8List.fromList(scfaLanLoudProbe),
InternetAddress.loopbackIPv4,
port,
);
socket.send(
Uint8List.fromList(scfaLanVanillaProbe),
InternetAddress.loopbackIPv4,
port,
);
final deadline = DateTime.now().add(const Duration(milliseconds: 220));
while (DateTime.now().isBefore(deadline)) {
final dg = socket.receive();
if (dg != null && dg.data.isNotEmpty) {
final parsed = parseScfaLanReply(dg.data, fallbackPort: port);
if (parsed != null) return parsed;
}
await Future<void>.delayed(const Duration(milliseconds: 40));
}
} catch (e) {
      appLogger.d('[UdpDiscover] 操作失败', error: e);

    } finally {
socket?.close();
}
return null;
}

Future<String?> _mapFromNearbyLogs(String exePath) async {
if (exePath.isEmpty) return null;
try {
final exe = File(exePath);
final dirs = <Directory>[
exe.parent,
Directory('${exe.parent.path}\\log'),
];
final localApp = Platform.environment['LOCALAPPDATA'];
if (localApp != null && localApp.isNotEmpty) {
dirs.add(Directory('$localApp\\Gas Powered Games'));
}
final files = <File>[];
for (final dir in dirs) {
if (!dir.existsSync()) continue;
await for (final ent in dir.list(followLinks: false)) {
if (ent is! File) continue;
final name = ent.uri.pathSegments.isEmpty
? ''
: ent.uri.pathSegments.last.toLowerCase();
if (name.endsWith('.log') || name.endsWith('log.txt')) {
files.add(ent);
}
}
}
files.sort(
(a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
);
final scenarioRe = RegExp(
r'(scmp_\d+|x1mp_\d+)',
caseSensitive: false,
);
for (final f in files.take(6)) {
final text = await f.readAsString();
final m = scenarioRe.firstMatch(text);
if (m == null) continue;
final name = scfaMapNameFromScenario(m.group(0)!);
if (name.isNotEmpty) return name;
}
} catch (e) { appLogger.d('[UdpDiscover] 操作失败', error: e); }
return null;
}
