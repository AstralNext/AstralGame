import 'package:astral_game/utils/logger.dart';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/utils/runtime_platform.dart';
import 'package:ffi/ffi.dart';

/// 进程内 ICMP Echo，返回 RTT 毫秒。不调用系统 `ping`。
int? icmpEchoRttMsSync(String ipv4, int timeoutMs) {
final parsed = InternetAddress.tryParse(ipv4);
if (parsed == null || parsed.type != InternetAddressType.IPv4) return null;
final timeout = timeoutMs < 1 ? 1 : timeoutMs;
if (RuntimePlatform.isWindows) {
return _icmpEchoWindows(parsed.rawAddress, timeout);
}
return _icmpEchoPosix(parsed.rawAddress, timeout);
}

int icmpChecksum(List<int> data) {
var sum = 0;
final n = data.length;
for (var i = 0; i + 1 < n; i += 2) {
sum += (data[i] << 8) | data[i + 1];
}
if (n.isOdd) sum += data[n - 1] << 8;
while (sum > 0xFFFF) {
sum = (sum & 0xFFFF) + (sum >> 16);
}
return (~sum) & 0xFFFF;
}

Uint8List buildIcmpEchoRequest({
required int id,
required int seq,
required List<int> payload,
}) {
final buf = Uint8List(8 + payload.length);
buf[0] = 8;
buf[1] = 0;
buf[4] = (id >> 8) & 0xFF;
buf[5] = id & 0xFF;
buf[6] = (seq >> 8) & 0xFF;
buf[7] = seq & 0xFF;
buf.setRange(8, buf.length, payload);
final csum = icmpChecksum(buf);
buf[2] = (csum >> 8) & 0xFF;
buf[3] = csum & 0xFF;
return buf;
}

// --- Windows: Iphlpapi IcmpSendEcho（无需管理员，无需 ping.exe） ---

final class _IcmpEchoReply extends Struct {
@Uint32()
external int address;
@Uint32()
external int status;
@Uint32()
external int roundTripTime;
@Uint16()
external int dataSize;
@Uint16()
external int reserved;
external Pointer<Void> data;
@Uint8()
external int ttl;
@Uint8()
external int tos;
@Uint8()
external int flags;
@Uint8()
external int optionsSize;
external Pointer<Void> optionsData;
}

typedef _IcmpCreateFileNative = IntPtr Function();
typedef _IcmpCreateFileDart = int Function();
typedef _IcmpCloseHandleNative = Int32 Function(IntPtr);
typedef _IcmpCloseHandleDart = int Function(int);
typedef _IcmpSendEchoNative = Uint32 Function(
IntPtr handle,
Uint32 dest,
Pointer<Void> request,
Uint16 requestSize,
Pointer<Void> options,
Pointer<Void> reply,
Uint32 replySize,
Uint32 timeout,
);
typedef _IcmpSendEchoDart = int Function(
int handle,
int dest,
Pointer<Void> request,
int requestSize,
Pointer<Void> options,
Pointer<Void> reply,
int replySize,
int timeout,
);

int? _icmpEchoWindows(List<int> ipv4, int timeoutMs) {
final dest = ipv4[0] | (ipv4[1] << 8) | (ipv4[2] << 16) | (ipv4[3] << 24);
final dll = DynamicLibrary.open('iphlpapi.dll');
final create =
dll.lookupFunction<_IcmpCreateFileNative, _IcmpCreateFileDart>(
'IcmpCreateFile',
);
final close =
dll.lookupFunction<_IcmpCloseHandleNative, _IcmpCloseHandleDart>(
'IcmpCloseHandle',
);
final send = dll.lookupFunction<_IcmpSendEchoNative, _IcmpSendEchoDart>(
'IcmpSendEcho',
);

final handle = create();
if (handle == 0 || handle == -1) return null;

const payloadLen = 32;
const replySize = 256;
final request = calloc<Uint8>(payloadLen);
final reply = calloc<Uint8>(replySize);
try {
for (var i = 0; i < payloadLen; i++) {
request[i] = 0x61;
}
final n = send(
handle,
dest,
request.cast(),
payloadLen,
nullptr,
reply.cast(),
replySize,
timeoutMs,
);
if (n == 0) return null;
final echo = reply.cast<_IcmpEchoReply>().ref;
if (echo.status != 0) return null;
return echo.roundTripTime;
} finally {
close(handle);
calloc.free(request);
calloc.free(reply);
}
}

// --- POSIX: SOCK_DGRAM + IPPROTO_ICMP（Linux/Android/macOS 无特权 ICMP） ---

final class _Pollfd extends Struct {
@Int32()
external int fd;
@Int16()
external int events;
@Int16()
external int revents;
}

typedef _SocketNative = Int32 Function(Int32, Int32, Int32);
typedef _SocketDart = int Function(int, int, int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);
typedef _SendtoNative = IntPtr Function(
Int32,
Pointer<Void>,
IntPtr,
Int32,
Pointer<Void>,
Uint32,
);
typedef _SendtoDart = int Function(
int,
Pointer<Void>,
int,
int,
Pointer<Void>,
int,
);
typedef _RecvfromNative = IntPtr Function(
Int32,
Pointer<Void>,
IntPtr,
Int32,
Pointer<Void>,
Pointer<Uint32>,
);
typedef _RecvfromDart = int Function(
int,
Pointer<Void>,
int,
int,
Pointer<Void>,
Pointer<Uint32>,
);
typedef _PollNative = Int32 Function(Pointer<_Pollfd>, IntPtr, Int32);
typedef _PollDart = int Function(Pointer<_Pollfd>, int, int);

DynamicLibrary _libc() {
if (RuntimePlatform.isAndroid) {
return DynamicLibrary.open('libc.so');
}
if (RuntimePlatform.isLinux) {
try {
return DynamicLibrary.open('libc.so.6');
} catch (e) {
      appLogger.d('[IcmpEcho] 操作失败', error: e);
return DynamicLibrary.process();

    }
}
return DynamicLibrary.process();
}

int? _icmpEchoPosix(List<int> ipv4, int timeoutMs) {
const afInet = 2;
const sockDgram = 2;
const ipprotoIcmp = 1;
const pollin = 1;

final libc = _libc();
final socket = libc.lookupFunction<_SocketNative, _SocketDart>('socket');
final close = libc.lookupFunction<_CloseNative, _CloseDart>('close');
final sendto = libc.lookupFunction<_SendtoNative, _SendtoDart>('sendto');
final recvfrom =
libc.lookupFunction<_RecvfromNative, _RecvfromDart>('recvfrom');
final poll = libc.lookupFunction<_PollNative, _PollDart>('poll');

final fd = socket(afInet, sockDgram, ipprotoIcmp);
if (fd < 0) return null;

const seq = 1;
final id = DateTime.now().microsecondsSinceEpoch & 0xFFFF;
final cookie = [
id & 0xFF,
(id >> 8) & 0xFF,
seq & 0xFF,
0xA5,
];
final pkt = buildIcmpEchoRequest(id: id, seq: seq, payload: cookie);

final sa = calloc<Uint8>(16);
final pktPtr = calloc<Uint8>(pkt.length);
final recvBuf = calloc<Uint8>(256);
final pfd = calloc<_Pollfd>();
try {
if (RuntimePlatform.isMacOS || RuntimePlatform.isIOS) {
sa[0] = 16;
sa[1] = afInet;
} else {
sa[0] = afInet;
sa[1] = 0;
}
sa[4] = ipv4[0];
sa[5] = ipv4[1];
sa[6] = ipv4[2];
sa[7] = ipv4[3];
for (var i = 0; i < pkt.length; i++) {
pktPtr[i] = pkt[i];
}

final sent = sendto(
fd,
pktPtr.cast(),
pkt.length,
0,
sa.cast(),
16,
);
if (sent < 0) return null;

final sw = Stopwatch()..start();
while (true) {
final left = timeoutMs - sw.elapsedMilliseconds;
if (left <= 0) return null;
pfd.ref.fd = fd;
pfd.ref.events = pollin;
pfd.ref.revents = 0;
final pr = poll(pfd, 1, left);
if (pr <= 0) return null;
final n = recvfrom(fd, recvBuf.cast(), 256, 0, nullptr, nullptr);
if (n < 8) continue;
final data = recvBuf.asTypedList(n);
final rtt = _parseEchoReply(data, seq: seq, cookie: cookie);
if (rtt != null) return sw.elapsedMilliseconds;
}
} finally {
close(fd);
calloc.free(sa);
calloc.free(pktPtr);
calloc.free(recvBuf);
calloc.free(pfd);
}
}

int? _parseEchoReply(
Uint8List data, {
required int seq,
required List<int> cookie,
}) {
var off = 0;
if (data.length >= 20 && (data[0] >> 4) == 4) {
off = (data[0] & 0x0F) * 4;
}
if (data.length < off + 8 + cookie.length) return null;
if (data[off] != 0) return null;
final replySeq = (data[off + 6] << 8) | data[off + 7];
if (replySeq != seq) return null;
for (var i = 0; i < cookie.length; i++) {
if (data[off + 8 + i] != cookie[i]) return null;
}
return 0;
}
