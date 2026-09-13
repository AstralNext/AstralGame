import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/services/share_code_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

RoomInvitePayload get _payload => const RoomInvitePayload(
  gameId: 'stardew',
  gameName: '星露谷',
  networkName: 'ag_test',
  networkSecret: 'secret',
  peers: [],
);

http.Response _okCreate() => http.Response(
  '{"code":"ABC123","admin_token":"t","expires_at":""}',
  200,
);

void main() {
  test('连续 3 次瞬时失败后熔断，create 不再发请求', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('boom', 500);
    });
    final svc = ShareCodeService(client: client);
    addTearDown(svc.close);

    for (var i = 0; i < 3; i++) {
      await expectLater(svc.create(_payload), throwsShareCodeException);
    }
    expect(requests, 3);

    // 第 4 次直接短路，不再撞网络
    await expectLater(svc.create(_payload), throwsShareCodeException);
    expect(requests, 3);
  });

  test('非瞬时失败（429）不计入熔断', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('slow down', 429);
    });
    final svc = ShareCodeService(client: client);
    addTearDown(svc.close);

    for (var i = 0; i < 5; i++) {
      await expectLater(svc.create(_payload), throwsShareCodeException);
    }
    // 429 说明服务活着，5 次全部真实发出、从不短路
    expect(requests, 5);
  });

  test('成功重置计数', () async {
    var requests = 0;
    var fail = true;
    final client = MockClient((_) async {
      requests++;
      return fail ? http.Response('boom', 503) : _okCreate();
    });
    final svc = ShareCodeService(client: client);
    addTearDown(svc.close);

    await expectLater(svc.create(_payload), throwsShareCodeException);
    await expectLater(svc.create(_payload), throwsShareCodeException);
    fail = false;
    final ok = await svc.create(_payload);
    expect(ok.code, 'ABC123');
    fail = true;
    // 计数已被成功清零：再来 2 次失败仍不到阈值
    await expectLater(svc.create(_payload), throwsShareCodeException);
    await expectLater(svc.create(_payload), throwsShareCodeException);
    expect(requests, 5);
  });

  test('熔断到期后半开放行，成功后关闭', () async {
    var now = DateTime(2026);
    var requests = 0;
    var fail = true;
    final client = MockClient((_) async {
      requests++;
      return fail ? http.Response('boom', 500) : _okCreate();
    });
    final svc = ShareCodeService(client: client, clock: () => now);
    addTearDown(svc.close);

    for (var i = 0; i < 3; i++) {
      await expectLater(svc.create(_payload), throwsShareCodeException);
    }
    // 熔断中：短路不发请求
    await expectLater(svc.create(_payload), throwsShareCodeException);
    expect(requests, 3);

    // 冷却结束：半开放行真实请求并成功
    now = now.add(ShareCodeService.breakerCooldown + const Duration(seconds: 1));
    fail = false;
    final ok = await svc.create(_payload);
    expect(ok.code, 'ABC123');
    expect(requests, 4);

    // 成功已关闭熔断：后续请求正常放行
    final ok2 = await svc.create(_payload);
    expect(ok2.code, 'ABC123');
    expect(requests, 5);
  });

  test('fetch 在熔断期间仍放行（显式加入意图）', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('boom', 500);
    });
    final svc = ShareCodeService(client: client);
    addTearDown(svc.close);

    for (var i = 0; i < 3; i++) {
      await expectLater(svc.create(_payload), throwsShareCodeException);
    }
    expect(requests, 3);

    // 熔断中 fetch 仍真实发出请求
    await expectLater(svc.fetch('ABC123'), throwsShareCodeException);
    expect(requests, 4);
  });
}

/// 便捷匹配器：断言抛出 [ShareCodeException]。
final throwsShareCodeException =
    throwsA(isA<ShareCodeException>());
