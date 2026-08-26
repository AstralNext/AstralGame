import 'package:astral_game/utils/logger.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:astral_game/config/constants.dart';
import 'package:astral_game/config/network_constants.dart';
import 'package:astral_game/utils/icmp_echo.dart';

const _kIcmpIsolateShutdown = 'shutdown';
const _kIcmpPoolSize = 4;

/// 进程内 ICMP Echo，不发起 TCP，也不调用系统 `ping`。
class PingUtil {
PingUtil._();

static final _pool = _IcmpIsolatePool(_kIcmpPoolSize);

static Future<int?> ping(String server) async {
final host = pingHostOf(server);
if (host == null) return null;
return pingHost(host);
}

static Future<int?> pingHost(String host) async {
final results = await pingHosts([host]);
return results[host];
}

/// 解析 DNS 后在复用的 isolate 池里 ICMP，避免每个目标都 `Isolate.run`。
static Future<Map<String, int?>> pingHosts(List<String> hosts) async {
if (hosts.isEmpty) return {};
final timeoutMs = AppConstants.pingTimeout.inMilliseconds;
final resolved = await Future.wait(hosts.map(resolvePingIpv4));
final out = <String, int?>{for (final h in hosts) h: null};
final ipToHosts = <String, List<String>>{};
for (var i = 0; i < hosts.length; i++) {
final ip = resolved[i];
if (ip == null) continue;
ipToHosts.putIfAbsent(ip, () => []).add(hosts[i]);
}
if (ipToHosts.isEmpty) return out;
final ips = ipToHosts.keys.toList();
final rtts = await Future.wait(
ips.map((ip) => _pool.ping(ip, timeoutMs)),
);
for (var i = 0; i < ips.length; i++) {
final rtt = rtts[i];
for (final host in ipToHosts[ips[i]]!) {
out[host] = rtt;
}
}
return out;
}

/// 与 [servers] 下标对齐的 RTT；无法解析的项为 `null`。
static Future<List<int?>> pingMany(List<String> servers) async {
if (servers.isEmpty) return const [];
final hosts = [for (final s in servers) pingHostOf(s)];
final unique = <String>[];
for (final h in hosts) {
if (h != null && !unique.contains(h)) unique.add(h);
}
final byHost = await pingHosts(unique);
return [for (final h in hosts) h == null ? null : byHost[h]];
}

static Future<void> close() => _pool.close();
}

/// 从服务器 URL / `host:port` 取出 ICMP 目标主机。
String? pingHostOf(String server) {
final raw = server.trim();
if (raw.isEmpty) return null;

final uri = Uri.tryParse(raw);
String? host;
if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
host = uri.host;
} else if (raw.startsWith('[')) {
final end = raw.indexOf(']');
if (end > 1) host = raw.substring(1, end);
} else {
final colon = raw.lastIndexOf(':');
if (colon > 0 && int.tryParse(raw.substring(colon + 1)) != null) {
host = raw.substring(0, colon);
} else {
host = raw;
}
}

host = host?.trim();
if (host == null || host.isEmpty) return null;
if (kUnspecifiedIpSet.contains(host) || host == '*') return null;
if (host.startsWith('-') || RegExp(r'\s').hasMatch(host)) return null;
return host;
}

Future<String?> resolvePingIpv4(String host) async {
final parsed = InternetAddress.tryParse(host);
if (parsed != null) {
return parsed.type == InternetAddressType.IPv4 ? parsed.address : null;
}
try {
final addrs =
await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
if (addrs.isNotEmpty) return addrs.first.address;
} catch (e) { appLogger.d('[PingUtil] 操作失败', error: e); }
return null;
}

void _icmpEchoIsolateMain(SendPort handshake) {
final inbox = ReceivePort();
handshake.send(inbox.sendPort);
inbox.listen((message) {
if (message == _kIcmpIsolateShutdown) {
inbox.close();
return;
}
final list = message as List<dynamic>;
final reply = list[0] as SendPort;
final ip = list[1] as String;
final timeoutMs = list[2] as int;
try {
reply.send(icmpEchoRttMsSync(ip, timeoutMs));
} catch (e) {
      appLogger.d('[PingUtil] 操作失败', error: e);
reply.send(null);

    }
});
}

class _IcmpWorker {
_IcmpWorker(this._isolate, this._send);

final Isolate _isolate;
final SendPort _send;

static Future<_IcmpWorker> spawn() async {
final ready = ReceivePort();
final isolate = await Isolate.spawn(_icmpEchoIsolateMain, ready.sendPort);
final send = await ready.first as SendPort;
ready.close();
return _IcmpWorker(isolate, send);
}

Future<int?> ping(String ip, int timeoutMs) async {
final reply = ReceivePort();
try {
_send.send(<dynamic>[reply.sendPort, ip, timeoutMs]);
final raw = await reply.first.timeout(
Duration(milliseconds: timeoutMs + 2000),
onTimeout: () => null,
);
if (raw is int) return raw;
return null;
} finally {
reply.close();
}
}

Future<void> shutdown() async {
try {
_send.send(_kIcmpIsolateShutdown);
} catch (e) { appLogger.d('[PingUtil] 操作失败', error: e); }
_isolate.kill(priority: Isolate.immediate);
}
}

class _IcmpIsolatePool {
_IcmpIsolatePool(this.size);

final int size;
final List<_IcmpWorker> _live = [];
final List<_IcmpWorker> _idle = [];
final Queue<Completer<_IcmpWorker>> _waiters = Queue();
int _spawning = 0;
bool _closed = false;

Future<int?> ping(String ip, int timeoutMs) async {
if (_closed) return null;
final worker = await _acquire();
try {
return await worker.ping(ip, timeoutMs);
} catch (e) {
      appLogger.d('[PingUtil] 操作失败', error: e);
return null;

    } finally {
_release(worker);
}
}

Future<_IcmpWorker> _acquire() async {
if (_idle.isNotEmpty) return _idle.removeLast();
if (_live.length + _spawning < size) {
_spawning++;
try {
final worker = await _IcmpWorker.spawn();
_live.add(worker);
return worker;
} finally {
_spawning--;
}
}
final waiter = Completer<_IcmpWorker>();
_waiters.add(waiter);
return waiter.future;
}

void _release(_IcmpWorker worker) {
if (_closed) {
unawaited(worker.shutdown());
return;
}
if (_waiters.isNotEmpty) {
_waiters.removeFirst().complete(worker);
return;
}
_idle.add(worker);
}

Future<void> close() async {
_closed = true;
while (_waiters.isNotEmpty) {
_waiters.removeFirst().completeError(StateError('ping pool closed'));
}
final workers = List<_IcmpWorker>.from(_live);
_live.clear();
_idle.clear();
for (final w in workers) {
await w.shutdown();
}
}
}
