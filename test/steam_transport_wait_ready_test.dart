import 'dart:async';

import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:astral_game/src/rust/api/steam.dart';
import 'package:flutter_test/flutter_test.dart';

SteamStatusInfo _status({
  bool ok = true,
  bool loggedOn = true,
  bool relayReady = false,
  String persona = '',
  String message = '',
}) => SteamStatusInfo(
  ok: ok,
  loggedOn: loggedOn,
  steamId: '76561198000000000',
  persona: persona,
  relayReady: relayReady,
  roomActive: false,
  isHost: false,
  virtualIp: '',
  memberCount: 0,
  message: message,
);

void main() {
  test('初始快照已就绪时立即返回，不订阅事件', () async {
    var subscribed = false;
    final result = await awaitSteamReady(
      readStatus: () async => _status(relayReady: true, persona: 'ready'),
      subscribeStatus: () {
        subscribed = true;
        return const Stream<SteamStatusInfo>.empty();
      },
      timeout: const Duration(seconds: 1),
    );

    expect(result.persona, 'ready');
    expect(subscribed, isFalse, reason: '已就绪时不应再订阅状态事件');
  });

  test('只有就绪事件能完成等待，且只完成一次', () async {
    final controller = StreamController<SteamStatusInfo>();
    var reads = 0;
    final future = awaitSteamReady(
      readStatus: () async {
        reads++;
        return _status(persona: 'initial');
      },
      subscribeStatus: () => controller.stream,
      timeout: const Duration(seconds: 5),
    );

    await Future<void>.delayed(Duration.zero);
    controller.add(_status(persona: 'not-ready-1'));
    controller.add(_status(ok: false, loggedOn: false, persona: 'not-ready-2'));

    var completed = false;
    unawaited(future.then((_) => completed = true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(completed, isFalse, reason: '未就绪事件不应完成等待');

    controller.add(_status(relayReady: true, persona: 'first-ready'));
    controller.add(_status(relayReady: true, persona: 'second-ready'));

    final result = await future;
    expect(result.persona, 'first-ready', reason: '应以首个就绪事件完成');
    expect(reads, 1, reason: '就绪路径不应触发超时回读');
    await controller.close();
  });

  test('超时后回读一次最新快照并取消订阅', () async {
    var canceled = false;
    final controller = StreamController<SteamStatusInfo>(
      onCancel: () => canceled = true,
    );
    var reads = 0;

    final result = await awaitSteamReady(
      readStatus: () async {
        reads++;
        return _status(persona: 'snapshot-$reads');
      },
      subscribeStatus: () => controller.stream,
      timeout: const Duration(milliseconds: 50),
    );

    expect(result.persona, 'snapshot-2', reason: '超时应回读一次最新快照');
    expect(reads, 2, reason: '仅初始快照 + 超时兜底各一次');
    expect(canceled, isTrue, reason: '返回前必须取消状态订阅');
    await controller.close();
  });

  test('Steam 未初始化时快速失败，不等待超时', () async {
    var subscribed = false;
    final stopwatch = Stopwatch()..start();

    final result = await awaitSteamReady(
      readStatus: () async =>
          _status(ok: false, loggedOn: false, message: 'SteamAPI 初始化失败'),
      subscribeStatus: () {
        subscribed = true;
        return const Stream<SteamStatusInfo>.empty();
      },
      timeout: const Duration(seconds: 30),
    );

    stopwatch.stop();
    expect(result.ok, isFalse);
    expect(subscribed, isFalse, reason: '快速失败无需订阅事件');
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });
}
