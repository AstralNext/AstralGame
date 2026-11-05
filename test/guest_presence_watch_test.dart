import 'package:astral_game/data/services/connection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;

  GuestPresenceWatch watch() => GuestPresenceWatch(clock: () => now);

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
  });

  test('无会话 / 房主自己 / 未连接时不判定离线', () {
    final w = watch();

    expect(
      w.evaluate(
        hasSession: false,
        isHostSession: true,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.idle,
    );
    now = now.add(const Duration(minutes: 1));
    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: true,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.idle,
    );
    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: false,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.idle,
    );
  });

  test('客机无远端成员超过宽限期才判定房主离线', () {
    final w = watch();

    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.waiting,
      reason: '刚开始无成员不应立刻判离线',
    );

    now = now.add(const Duration(seconds: 9));
    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.waiting,
    );

    now = now.add(const Duration(seconds: 1));
    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.offline,
      reason: '持续 10s 无成员应判定房主离线',
    );
  });

  test('仍有远端成员时长时间不误判离线', () {
    final w = watch();

    for (var i = 0; i < 10; i++) {
      expect(
        w.evaluate(
          hasSession: true,
          isHostSession: false,
          connected: true,
          hasOtherMembers: true,
        ),
        GuestPresenceAction.online,
      );
      now = now.add(const Duration(minutes: 1));
    }
  });

  test('成员重新出现会重置离线计时', () {
    final w = watch();

    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.waiting,
    );

    now = now.add(const Duration(seconds: 20));
    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: true,
        hasOtherMembers: true,
      ),
      GuestPresenceAction.online,
      reason: '成员回来即视为房主在线',
    );

    now = now.add(const Duration(seconds: 1));
    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.waiting,
      reason: '重新计时，不应沿用之前的 20s',
    );

    now = now.add(const Duration(seconds: 10));
    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.offline,
    );
  });

  test('连接中断会重置计时，恢复后需重新计满宽限期', () {
    final w = watch();

    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.waiting,
    );

    now = now.add(const Duration(seconds: 9));
    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: false,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.idle,
    );

    now = now.add(const Duration(seconds: 1));
    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.waiting,
      reason: '恢复连接后应重新计时',
    );

    now = now.add(const Duration(seconds: 9));
    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.waiting,
    );

    now = now.add(const Duration(seconds: 1));
    expect(
      w.evaluate(
        hasSession: true,
        isHostSession: false,
        connected: true,
        hasOtherMembers: false,
      ),
      GuestPresenceAction.offline,
    );
  });
}
