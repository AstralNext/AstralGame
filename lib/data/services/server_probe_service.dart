import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:astral_game/config/constants.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/utils/ping_util.dart';

/// 一次 EasyTier 握手探测的结果。
class ServerProbeResult {
  const ServerProbeResult({required this.isEasyTier});

  /// 对端是否为 EasyTier 服务器。
  ///
  /// `null` 表示无法判断：地址不是 TCP 接入（udp/ws/wss/quic/wg），或连接失败。
  final bool? isEasyTier;
}

/// 通过 EasyTier 握手判断服务器是否为 ET 端点。
///
/// TCP 帧格式（`easytier-core`）：
/// ```
/// [4B 小端 bodyLen][16B PeerManagerHeader][protobuf HandshakeRequest]
/// ```
/// 发送一帧 `packet_type = HandShake(2)`、`magic = 0xd1e1a5e1` 的握手，
/// 若对端回包同样是 `HandShake` 且魔数匹配，即为 ET 服务器。
///
/// 软件版本、在线人数、中转能力都不在握手中，因此不读取也不展示。
class ServerProbeService {
  /// ET 握手魔数（`peer_conn.rs`：`const MAGIC: u32 = 0xd1e1a5e1`）。
  static const int easytierHandshakeMagic = 0xd1e1a5e1;

  /// ET 握手协议版本（`peer_conn.rs`：`const VERSION: u32 = 1`）。
  static const int easytierProtocolVersion = 1;

  static const int _packetTypeHandshake = 2;
  static const int _peerManagerHeaderSize = 16;
  static const int _maxBodyLength = 1 << 16;

  /// 探测用网络名。服务端对外来网络名会分配临时 peer id，可以随便填。
  static const String _probeNetworkName = 'astral-probe';

  static final Random _random = Random();

  /// 探测一次端点：能完成 ET 握手返回 `true`，明确不是返回 `false`，
  /// 无法判断（非 TCP 接入或连不上）返回 `null`。
  Future<ServerProbeResult> probe(ServerMod server) async {
    final scheme = Uri.tryParse(server.url.trim())?.scheme.toLowerCase();
    // ws/wss/quic/udp/wg 不是裸 TCP 帧，无法用这套握手判断。
    if (scheme != null && scheme.isNotEmpty && scheme != 'tcp') {
      return const ServerProbeResult(isEasyTier: null);
    }
    final target = tcpPingTargetOf(server.url);
    if (target == null) return const ServerProbeResult(isEasyTier: null);

    Socket socket;
    try {
      socket = await Socket.connect(
        target.host,
        target.port,
        timeout: AppConstants.pingTimeout,
      );
    } on SocketException {
      return const ServerProbeResult(isEasyTier: null);
    } on TimeoutException {
      return const ServerProbeResult(isEasyTier: null);
    }

    final reader = _SocketReader(socket);
    try {
      socket.add(_encodeHandshakeFrame(_randomPeerId()));
      await socket.flush();
      final lengthBytes = await reader
          .readExact(4)
          .timeout(AppConstants.pingTimeout);
      final bodyLength = ByteData.sublistView(
        lengthBytes,
      ).getUint32(0, Endian.little);
      if (bodyLength < _peerManagerHeaderSize ||
          bodyLength > _maxBodyLength) {
        return const ServerProbeResult(isEasyTier: false);
      }
      final body = await reader
          .readExact(bodyLength)
          .timeout(AppConstants.pingTimeout);
      return ServerProbeResult(isEasyTier: _isHandshakeResponse(body));
    } on TimeoutException {
      // 端口能连上但没有回 ET 握手：不是 ET 端点。
      return const ServerProbeResult(isEasyTier: false);
    } on SocketException {
      return const ServerProbeResult(isEasyTier: false);
    } finally {
      await reader.cancel();
      socket.destroy();
    }
  }

  static int _randomPeerId() => 1 + _random.nextInt(0xfffffffe);

  /// 组装一帧完整的 TCP 握手包。
  static Uint8List _encodeHandshakeFrame(int peerId) {
    final payload = BytesBuilder(copy: false);
    // HandshakeRequest: magic / my_peer_id / version / network_name / digest
    _writeUint32Field(payload, 1, easytierHandshakeMagic);
    _writeUint32Field(payload, 2, peerId);
    _writeUint32Field(payload, 3, easytierProtocolVersion);
    _writeBytesField(payload, 5, utf8.encode(_probeNetworkName));
    // 服务端会校验摘要长度为 32 字节，内容无所谓。
    _writeBytesField(payload, 6, Uint8List(32));
    final payloadBytes = payload.takeBytes();

    final bodyLength = _peerManagerHeaderSize + payloadBytes.length;
    final frame = ByteData(4 + bodyLength);
    frame.setUint32(0, bodyLength, Endian.little);
    // PeerManagerHeader（packed，16 字节）
    frame.setUint32(4, peerId, Endian.little); // from_peer_id
    frame.setUint32(8, 0, Endian.little); // to_peer_id
    frame.setUint8(12, _packetTypeHandshake);
    frame.setUint8(13, 0); // flags
    frame.setUint8(14, 1); // forward_counter
    frame.setUint8(15, 0); // reserved
    frame.setUint32(16, payloadBytes.length, Endian.little); // len

    final bytes = frame.buffer.asUint8List();
    bytes.setRange(20, 20 + payloadBytes.length, payloadBytes);
    return bytes;
  }

  /// 回包是否为 ET 握手：`packet_type == HandShake` 且 protobuf 魔数匹配。
  static bool _isHandshakeResponse(Uint8List body) {
    if (body.length < _peerManagerHeaderSize) return false;
    if (body[8] != _packetTypeHandshake) return false;
    return _readMagic(body, _peerManagerHeaderSize) == easytierHandshakeMagic;
  }

  /// 在 protobuf payload 中查找 field 1（magic）的值，跳过其他字段。
  static int? _readMagic(List<int> payload, int start) {
    var offset = start;
    while (offset < payload.length) {
      final key = _readVarint(payload, offset);
      if (key == null) return null;
      offset = key.next;
      final field = key.value >> 3;
      final wireType = key.value & 0x07;

      if (wireType == 0) {
        final value = _readVarint(payload, offset);
        if (value == null) return null;
        if (field == 1) return value.value;
        offset = value.next;
      } else if (wireType == 1) {
        offset += 8;
      } else if (wireType == 2) {
        final length = _readVarint(payload, offset);
        if (length == null) return null;
        offset = length.next + length.value;
      } else if (wireType == 5) {
        offset += 4;
      } else {
        return null;
      }
      if (offset > payload.length) return null;
    }
    return null;
  }

  static ({int value, int next})? _readVarint(List<int> data, int start) {
    var result = 0;
    var shift = 0;
    var offset = start;
    while (offset < data.length) {
      final byte = data[offset];
      result |= (byte & 0x7f) << shift;
      offset++;
      if ((byte & 0x80) == 0) return (value: result, next: offset);
      shift += 7;
      if (shift > 63) return null;
    }
    return null;
  }

  static void _writeUint32Field(BytesBuilder out, int field, int value) {
    _writeVarint(out, field << 3);
    _writeVarint(out, value);
  }

  static void _writeBytesField(BytesBuilder out, int field, List<int> value) {
    _writeVarint(out, (field << 3) | 2);
    _writeVarint(out, value.length);
    out.add(value);
  }

  static void _writeVarint(BytesBuilder out, int value) {
    var remaining = value;
    while (remaining >= 0x80) {
      out.addByte((remaining & 0x7f) | 0x80);
      remaining >>= 7;
    }
    out.addByte(remaining);
  }
}

/// 把 socket 字节流按需切片，供按帧长度读取使用。
class _SocketReader {
  _SocketReader(Socket socket) : _iterator = StreamIterator<Uint8List>(socket);

  final StreamIterator<Uint8List> _iterator;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;

  Future<Uint8List> readExact(int count) async {
    final out = Uint8List(count);
    var written = 0;
    while (written < count) {
      if (_offset >= _chunk.length) {
        if (!await _iterator.moveNext()) {
          throw const SocketException('连接在探测过程中关闭');
        }
        _chunk = _iterator.current;
        _offset = 0;
        continue;
      }
      final take = min(_chunk.length - _offset, count - written);
      out.setRange(written, written + take, _chunk, _offset);
      written += take;
      _offset += take;
    }
    return out;
  }

  Future<void> cancel() => _iterator.cancel();
}
