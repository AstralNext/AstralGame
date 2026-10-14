import 'dart:io';

import 'package:astral_game/data/services/network_optimize_service.dart';
import 'package:astral_game/data/services/smart_dns_config_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// 假装网络加速栈已经装好（真实 refresh 会去跑 exe，测试里不碰）。
class _InstalledNetworkOptimize extends NetworkOptimizeService {
  @override
  Future<void> refresh() async => installed.value = true;
}

const _validConf = '''
server-name astraldns
bind 0.0.0.0:53
server-https https://223.6.6.6/dns-query#h2
''';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('smartdns_updater_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SmartDnsConfigUpdater build(
    http.Client client, {
    required List<String> deployed,
    bool deployOk = true,
  }) {
    return SmartDnsConfigUpdater(
      networkOptimize: _InstalledNetworkOptimize(),
      cacheDir: tmp,
      client: client,
      deployer: (path) async {
        deployed.add(path);
        return deployOk;
      },
    );
  }

  test('远端有更新：校验通过后部署，并写下 ETag', () async {
    final deployed = <String>[];
    final client = MockClient(
      (_) async => http.Response(_validConf, 200, headers: {'etag': '"v2"'}),
    );

    await build(client, deployed: deployed).checkAndApply();

    expect(deployed, hasLength(1));
    expect(
      File(deployed.single).readAsStringSync(),
      contains('bind 0.0.0.0:53'),
    );
    expect(
      File(p.join(tmp.path, 'smartdns.conf.remote.etag')).readAsStringSync(),
      '"v2"',
    );
  });

  test('回 304：带 If-None-Match 且不部署', () async {
    File(p.join(tmp.path, 'smartdns.conf.remote.etag')).writeAsStringSync('"v1"');
    String? sentEtag;
    final client = MockClient((req) async {
      sentEtag = req.headers['If-None-Match'];
      return http.Response('', 304);
    });
    final deployed = <String>[];

    await build(client, deployed: deployed).checkAndApply();

    expect(sentEtag, '"v1"');
    expect(deployed, isEmpty);
  });

  test('远端内容缺上游 server：拒绝部署', () async {
    final deployed = <String>[];
    final client = MockClient((_) async => http.Response('bind 0.0.0.0:53\n', 200));

    await build(client, deployed: deployed).checkAndApply();

    expect(deployed, isEmpty);
  });

  test('部署失败：不写 ETag，下次还会重试', () async {
    final deployed = <String>[];
    final client = MockClient(
      (_) async => http.Response(_validConf, 200, headers: {'etag': '"v3"'}),
    );

    await build(client, deployed: deployed, deployOk: false).checkAndApply();

    expect(deployed, hasLength(1));
    expect(
      File(p.join(tmp.path, 'smartdns.conf.remote.etag')).existsSync(),
      isFalse,
    );
  });

  group('looksLikeSmartDnsConf', () {
    test('同时有 bind 与上游 server 才通过', () {
      expect(looksLikeSmartDnsConf(_validConf), isTrue);
      expect(looksLikeSmartDnsConf('bind-tcp 0.0.0.0:53\nserver 8.8.8.8\n'), isTrue);
      // server-name 不是上游，只有 bind 时拒绝
      expect(looksLikeSmartDnsConf('server-name astraldns\nbind :53\n'), isFalse);
    });

    test('空内容 / 超长 / 含 NUL 一律拒绝', () {
      expect(looksLikeSmartDnsConf('   '), isFalse);
      expect(looksLikeSmartDnsConf('bind :53\nserver 1.1.1.1\n\u0000'), isFalse);
      expect(
        looksLikeSmartDnsConf('bind :53\nserver 1.1.1.1\n${'x' * 600000}'),
        isFalse,
      );
    });
  });
}
