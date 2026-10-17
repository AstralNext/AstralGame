import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:astral_game/config/network_constants.dart';
import 'package:astral_game/data/models/speed_test_node.dart';
import 'package:astral_game/data/models/speed_test_result.dart';
import 'package:astral_game/utils/des_ecb.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:crypto/crypto.dart';

enum SpeedTestPhase { latency, download, upload }

class SpeedTestSample {
  const SpeedTestSample({
    required this.phase,
    required this.elapsed,
    required this.mbps,
  });

  final SpeedTestPhase phase;

  final Duration elapsed;

  final double mbps;
}

class SpeedTestException implements Exception {
  SpeedTestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SpeedTestService {
  List<SpeedTestNode>? _cache;
  final Random _random = Random();

  Future<List<SpeedTestNode>> fetchNodes({bool forceRefresh = false}) async {
    final cached = _cache;
    if (!forceRefresh && cached != null) return cached;

    final key = Uint8List.fromList(utf8.encode(kSpeedTestDesKey));
    if (key.length != 8) {
      throw SpeedTestException('测速节点密钥无效（必须是 8 字节）');
    }

    final url = await _fetchServerListUrl();
    appLogger.i('[SpeedTest] 节点表密文地址: $url');
    final hex = (await _getText(url, timeout: kSpeedTestFetchTimeout)).trim();
    if (hex.isEmpty) throw SpeedTestException('节点表密文为空');

    final Uint8List plain;
    try {
      plain = DesEcb.decryptPkcs5(_hexToBytes(hex), key);
    } catch (e) {
      throw SpeedTestException('节点表解密失败：$e');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(plain, allowMalformed: true));
    } catch (_) {
      throw SpeedTestException('节点表解密失败（密钥可能不正确）');
    }
    if (decoded is! List) throw SpeedTestException('节点表格式异常');

    final nodes = <SpeedTestNode>[];
    for (final raw in decoded) {
      final node = SpeedTestNode.tryParse(raw);
      if (node != null) nodes.add(node);
    }
    if (nodes.isEmpty) throw SpeedTestException('节点表为空');

    appLogger.i('[SpeedTest] 节点表已更新：${nodes.length} 个节点');
    _cache = nodes;
    return nodes;
  }

  Future<double?> probeLatency(
    SpeedTestNode node, {
    int samples = kSpeedTestProbeSamples,
    void Function(double latencyMs)? onSample,
    void Function(bool success)? onProbe,
  }) async {
    final port = int.tryParse(node.port);
    if (port == null) return null;
    double? best;
    for (var i = 0; i < samples; i++) {
      final watch = Stopwatch()..start();
      Socket? socket;
      try {
        socket = await Socket.connect(
          node.ip,
          port,
          timeout: kSpeedTestProbeTimeout,
        );
        watch.stop();
        final ms = watch.elapsedMicroseconds / 1000;
        if (best == null || ms < best) best = ms;
        onSample?.call(best);
        onProbe?.call(true);
      } catch (_) {
        onProbe?.call(false);
      } finally {
        socket?.destroy();
      }
    }
    return best;
  }

  Future<SpeedTestResult> measure(
    SpeedTestNode node, {
    Duration window = kSpeedTestWindow,
    int threads = kSpeedTestThreads,
    void Function(SpeedTestPhase phase)? onPhase,
    void Function(SpeedTestPhase phase, Duration elapsed, double mbps)?
    onSample,
    void Function(SpeedTestPhase phase, double latencyMs)? onLatency,
  }) async {
    final testStart = DateTime.now();
    final latencySamples = <SpeedTestPhase, List<double>>{
      SpeedTestPhase.latency: [],
      SpeedTestPhase.download: [],
      SpeedTestPhase.upload: [],
    };
    void record(SpeedTestPhase phase, double latencyMs) {
      latencySamples[phase]!.add(latencyMs);
      onLatency?.call(phase, latencyMs);
    }

    var probeSent = 0;
    var probeFailed = 0;
    void countProbe(bool success) {
      probeSent++;
      if (!success) probeFailed++;
    }

    onPhase?.call(SpeedTestPhase.latency);
    final latency = await probeLatency(
      node,
      onSample: (ms) => record(SpeedTestPhase.latency, ms),
      onProbe: countProbe,
    );
    if (latency == null) {
      return const SpeedTestResult.failure('节点不可达');
    }

    final imei = _randomImei();
    final String uuid;
    try {
      uuid = await _doValid(node, imei);
    } on SpeedTestException catch (e) {
      return SpeedTestResult(latencyMs: latency, error: e.message);
    }

    var probingPhase = SpeedTestPhase.download;
    final latencyProbe = _startLatencyProbe(
      node,
      (ms) => record(probingPhase, ms),
      onProbe: countProbe,
    );
    try {
      onPhase?.call(SpeedTestPhase.download);
      final download = await _measureDownload(
        node,
        uuid,
        window: window,
        threads: threads,
        onSample: onSample,
        sampleStart: testStart,
      );
      probingPhase = SpeedTestPhase.upload;
      onPhase?.call(SpeedTestPhase.upload);
      final upload = await _measureUpload(
        node,
        uuid,
        window: window,
        threads: threads,
        onSample: onSample,
        sampleStart: testStart,
      );
      if (download <= 0 && upload <= 0) {
        return SpeedTestResult(latencyMs: latency, error: '测速无数据返回');
      }
      return SpeedTestResult(
        latencyMs: latency,
        downloadLatencyMs: _medianOf(latencySamples[SpeedTestPhase.download]!),
        uploadLatencyMs: _medianOf(latencySamples[SpeedTestPhase.upload]!),
        downloadMbps: download,
        uploadMbps: upload,
        lossRate: probeSent == 0 ? null : probeFailed * 100 / probeSent,
      );
    } finally {
      latencyProbe?.cancel();
      unawaited(_release(node, uuid));
    }
  }

  Timer? _startLatencyProbe(
    SpeedTestNode node,
    void Function(double latencyMs) onRecord, {
    void Function(bool success)? onProbe,
  }) {
    var busy = false;
    return Timer.periodic(kSpeedTestLatencyProbeInterval, (_) async {
      if (busy) return;
      busy = true;
      try {
        final ms = await probeLatency(node, samples: 1, onProbe: onProbe);
        if (ms != null) onRecord(ms);
      } finally {
        busy = false;
      }
    });
  }

  static double? _medianOf(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  Timer? _startSampling({
    required SpeedTestPhase phase,
    required _ByteCounter counter,
    required DateTime sampleStart,
    required void Function(SpeedTestPhase phase, Duration elapsed, double mbps)?
    onSample,
  }) {
    if (onSample == null) return null;
    var lastBytes = 0;
    var lastAt = DateTime.now();
    return Timer.periodic(_kSampleInterval, (_) {
      final now = DateTime.now();
      final seconds = now.difference(lastAt).inMicroseconds / 1e6;
      if (seconds <= 0) return;
      final bytes = counter.total;
      final mbps = (bytes - lastBytes) * 8 / seconds / 1e6;
      lastBytes = bytes;
      lastAt = now;
      onSample(phase, now.difference(sampleStart), mbps < 0 ? 0 : mbps);
    });
  }

  Future<String> _fetchServerListUrl() async {
    final uri = Uri.parse(kSpeedTestConfigPhp).replace(
      queryParameters: {
        'province': '北京',
        'city': '北京',
        'imei': _randomImei(),
        'appname': kSpeedTestApp,
        'vercode': _kAppVersionCode,
        'type': kSpeedTestApp,
        'ipv6': '0',
      },
    );
    final body = await _getText(
      uri.toString(),
      timeout: kSpeedTestFetchTimeout,
    );

    Object? cfg;
    try {
      cfg = jsonDecode(body);
    } catch (_) {
      throw SpeedTestException('配置接口响应不是合法 JSON');
    }
    if (cfg is List) {
      for (final entry in cfg) {
        if (entry is Map && entry['name'] == 'serverlist_encrypt_url') {
          final url = (entry['filename'] ?? '').toString().trim();
          if (url.isNotEmpty) return url;
        }
      }
    }
    throw SpeedTestException('配置接口未返回 serverlist_encrypt_url');
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s'), '');
    if (clean.length.isOdd) throw const FormatException('hex 长度不是偶数');
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  String _dovalidUrl(
    SpeedTestNode node,
    String imei,
    String time,
    String token,
  ) =>
      'http://${node.ip}:${node.port}$_kDovalidPath'
      '?key=&flag=true&bandwidth=$kSpeedTestReportBandwidth'
      '&model=Android&imei=$imei&time=$time&app=$kSpeedTestApp'
      '&token=$token&pkg=$kSpeedTestPkg';

  Future<String> _doValid(SpeedTestNode node, String imei) async {
    final time = _nowSeconds();
    final token = _makeToken(imei, time, kSpeedTestReportBandwidth);
    String body;
    try {
      body = (await _getText(
        _dovalidUrl(node, imei, time, token),
        timeout: kSpeedTestDovalidTimeout,
      )).trim();
    } on SpeedTestException {
      body = (await _getText(
        _dovalidUrl(node, imei, time, ''),
        timeout: kSpeedTestDovalidTimeout,
      )).trim();
    }
    if (body.startsWith('-1')) throw SpeedTestException('节点繁忙（排队超限）');
    if (body.startsWith('0')) throw SpeedTestException('鉴权失败');
    if (body.startsWith('2')) throw SpeedTestException('参数非法（版本不符）');
    if (!body.startsWith('1') || body.length < 3) {
      throw SpeedTestException('鉴权响应异常');
    }
    return body.substring(2);
  }

  Future<void> _release(SpeedTestNode node, String uuid) async {
    try {
      final client = _newClient();
      try {
        final request = await client
            .postUrl(
              Uri.parse(
                'http://${node.ip}:${node.port}$_kDovalidPath?key=$uuid',
              ),
            )
            .timeout(kSpeedTestDovalidTimeout);
        request.contentLength = 0;
        final response = await request.close().timeout(
          kSpeedTestDovalidTimeout,
        );
        await response.drain<void>();
      } finally {
        client.close(force: true);
      }
    } catch (_) {}
  }

  Future<double> _measureDownload(
    SpeedTestNode node,
    String uuid, {
    required Duration window,
    required int threads,
    void Function(SpeedTestPhase phase, Duration elapsed, double mbps)?
    onSample,
    required DateTime sampleStart,
  }) async {
    final counter = _ByteCounter();
    final started = DateTime.now();
    final deadline = started.add(window);
    final sampler = _startSampling(
      phase: SpeedTestPhase.download,
      counter: counter,
      sampleStart: sampleStart,
      onSample: onSample,
    );
    final workers = <Future<void>>[
      for (var i = 0; i < threads.clamp(1, 16); i++)
        _downloadWorker(node, uuid, counter, deadline),
    ];

    await Future<void>.delayed(window);
    final elapsed = DateTime.now().difference(started).inMicroseconds / 1e6;
    await Future.wait(workers);
    sampler?.cancel();
    return elapsed <= 0 ? 0 : counter.total * 8 / elapsed / 1e6;
  }

  Future<void> _downloadWorker(
    SpeedTestNode node,
    String uuid,
    _ByteCounter counter,
    DateTime deadline,
  ) async {
    Socket? socket;
    Timer? timer;
    try {
      final port = int.tryParse(node.port);
      if (port == null) return;
      socket = await Socket.connect(
        node.ip,
        port,
        timeout: kSpeedTestProbeTimeout,
      );
      socket.setOption(SocketOption.tcpNoDelay, true);

      final done = Completer<void>();
      timer = Timer(deadline.difference(DateTime.now()), () {
        socket?.destroy();
        if (!done.isCompleted) done.complete();
      });

      var headerDone = false;
      final pending = <int>[];
      final subscription = socket.listen(
        (chunk) {
          if (headerDone) {
            counter.total += chunk.length;
            return;
          }
          pending.addAll(chunk);
          final bodyStart = _bodyStartIndex(pending);
          if (bodyStart < 0) return;
          headerDone = true;
          final head = String.fromCharCodes(pending.sublist(0, bodyStart));
          final ok =
              head.startsWith('HTTP/1.1 200') ||
              head.startsWith('HTTP/1.0 200');
          if (!ok) {
            socket?.destroy();
            if (!done.isCompleted) done.complete();
            return;
          }
          counter.total += pending.length - bodyStart;
          pending.clear();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );

      socket.add(utf8.encode(_downloadRequest(node, uuid)));
      await done.future;
      await subscription.cancel();
    } catch (_) {
    } finally {
      timer?.cancel();
      socket?.destroy();
    }
  }

  static String _downloadRequest(SpeedTestNode node, String uuid) =>
      'GET $_kDownloadPath?r=${_nowSeconds()}&key=$uuid HTTP/1.1\r\n'
      'Accept: */*\r\n'
      'Connection: close\r\n'
      'User-Agent: $_kDownloadUserAgent\r\n'
      'Host:${node.ip}:${node.port}\r\n'
      '\r\n';

  static int _bodyStartIndex(List<int> bytes) {
    for (var i = 3; i < bytes.length; i++) {
      if (bytes[i - 3] == 13 &&
          bytes[i - 2] == 10 &&
          bytes[i - 1] == 13 &&
          bytes[i] == 10) {
        return i + 1;
      }
    }
    return -1;
  }

  Future<double> _measureUpload(
    SpeedTestNode node,
    String uuid, {
    required Duration window,
    required int threads,
    void Function(SpeedTestPhase phase, Duration elapsed, double mbps)?
    onSample,
    required DateTime sampleStart,
  }) async {
    final counter = _ByteCounter();
    final started = DateTime.now();
    final deadline = started.add(window);
    final sampler = _startSampling(
      phase: SpeedTestPhase.upload,
      counter: counter,
      sampleStart: sampleStart,
      onSample: onSample,
    );
    final chunk = Uint8List.fromList(
      List<int>.generate(_kUploadChunkSize, (_) => _random.nextInt(256)),
    );
    final workers = <Future<void>>[
      for (var i = 0; i < threads.clamp(1, 16); i++)
        _uploadWorker(node, uuid, chunk, counter, deadline),
    ];

    await Future<void>.delayed(window);
    final elapsed = DateTime.now().difference(started).inMicroseconds / 1e6;
    await Future.wait(workers);
    sampler?.cancel();
    return elapsed <= 0 ? 0 : counter.total * 8 / elapsed / 1e6;
  }

  Future<void> _uploadWorker(
    SpeedTestNode node,
    String uuid,
    Uint8List chunk,
    _ByteCounter counter,
    DateTime deadline,
  ) async {
    Socket? socket;
    try {
      final port = int.tryParse(node.port);
      if (port == null) return;
      socket = await Socket.connect(
        node.ip,
        port,
        timeout: kSpeedTestProbeTimeout,
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.add(utf8.encode(_uploadHeader(node, uuid)));
      while (DateTime.now().isBefore(deadline)) {
        socket.add(chunk);
        counter.total += chunk.length;
        await socket.flush();
      }
    } catch (_) {
    } finally {
      socket?.destroy();
    }
  }

  static String _uploadHeader(SpeedTestNode node, String uuid) {
    final stamp = DateTime.now();
    final fileName =
        'SPEED_${stamp.year}${stamp.month.toString().padLeft(2, '0')}'
        '${stamp.day.toString().padLeft(2, '0')}_'
        '${stamp.millisecondsSinceEpoch % 1000}';
    return 'POST $_kUploadPath HTTP/1.1\r\n'
        'Connection: close\r\n'
        'Cache-Control: no-cache\r\n'
        'Charset: UTF-8\r\n'
        'Key: $uuid\r\n'
        'Content-Type: multipart/form-data;boundary=$_kUploadBoundary\r\n'
        'User-Agent: $_kUploadUserAgent\r\n'
        'Host: ${node.ip}:${node.port}\r\n'
        'Accept-Encoding: gzip\r\n'
        'Content-Length: $_kUploadContentLength\r\n'
        '\r\n'
        '--$_kUploadBoundary\r\n'
        'Content-Disposition: form-data; name="upload";filename="$fileName"\r\n'
        '\r\n';
  }

  String _randomImei() {
    final tac = _kImeiTacs[_random.nextInt(_kImeiTacs.length)];
    final serial = _random.nextInt(1000000).toString().padLeft(6, '0');
    final body = '$tac$serial';
    return '$body${_luhnCheckDigit(body)}';
  }

  static int _luhnCheckDigit(String digits) {
    var total = 0;
    final chars = digits.split('').reversed.toList();
    for (var i = 0; i < chars.length; i++) {
      var digit = int.parse(chars[i]);
      if (i.isEven) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      total += digit;
    }
    return (10 - total % 10) % 10;
  }

  static String _makeToken(String imei, String time, int bandwidth) {
    final h1 = md5.convert(utf8.encode('model=Android&imei=$imei')).toString();
    final h2 = md5
        .convert(
          utf8.encode('stime=$time&band=$bandwidth&rand=$kSpeedTestRandToken'),
        )
        .toString();
    return md5.convert(utf8.encode('$h1$h2')).toString();
  }

  static String _nowSeconds() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  static HttpClient _newClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..badCertificateCallback = (_, _, _) => true;

  static Future<String> _getText(
    String url, {
    required Duration timeout,
    String userAgent = _kConfigUserAgent,
  }) async {
    final client = _newClient();
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw SpeedTestException('HTTP ${response.statusCode}');
      }
      return await utf8.decoder.bind(response).join().timeout(timeout);
    } on SpeedTestException {
      rethrow;
    } on TimeoutException {
      throw SpeedTestException('请求超时');
    } catch (e) {
      throw SpeedTestException('请求失败：$e');
    } finally {
      client.close(force: true);
    }
  }
}

class _ByteCounter {
  int total = 0;
}

const _kConfigUserAgent = 'Mozilla/5.0';
const _kDownloadUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/100.0.4896.60 Safari/537.36';
const _kUploadUserAgent =
    'Dalvik/1.6.0 (Linux; U; Android 4.2.2; GT-I9505 Build/JDQ39)';

const _kAppVersionCode = '40408';

const _kDovalidPath = '/speed/dovalid';
const _kDownloadPath = '/speed/File(1G).dl';
const _kUploadPath = '/speed/doAnalsLoad.do';
const _kUploadBoundary = '00content0boundary00';

const _kUploadChunkSize = 128 * 1024;
const _kUploadContentLength = 900000000;

const _kSampleInterval = Duration(milliseconds: 200);

const _kImeiTacs = [
  '86309606',
  '86107500',
  '86135803',
  '86330801',
  '86293103',
  '86824303',
  '86436303',
  '86970103',
  '86114003',
  '86663003',
];
