import 'package:astral_game/data/state/connection_phase.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionStateController', () {
    test('正常连接：idle → linking → connected → disconnecting → idle', () {
      final controller = ConnectionStateController();
      expect(controller.phase, ConnectionPhase.idle);

      controller.beginLinking();
      expect(controller.phase, ConnectionPhase.linking);

      controller.markConnected();
      expect(controller.phase, ConnectionPhase.connected);

      controller.beginDisconnecting();
      expect(controller.phase, ConnectionPhase.disconnecting);

      controller.reset();
      expect(controller.phase, ConnectionPhase.idle);
    });

    test('连接中取消：linking 直接回到 idle', () {
      final controller = ConnectionStateController()..beginLinking();
      controller.reset();
      expect(controller.phase, ConnectionPhase.idle);
    });

    test('连接失败：reset 记录 lastFailure，下次连接开始时清空', () {
      final controller = ConnectionStateController()..beginLinking();
      final error = StateError('boom');

      controller.reset(failure: error);
      expect(controller.phase, ConnectionPhase.idle);
      expect(controller.lastFailure, same(error));

      controller.beginLinking();
      expect(controller.lastFailure, isNull);
    });

    test('空闲时 beginDisconnecting 不会制造 disconnecting 阶段', () {
      final controller = ConnectionStateController();
      controller.beginDisconnecting();
      expect(controller.phase, ConnectionPhase.idle);
    });
  });

  group('RoomState.isConnected 派生值', () {
    test('只有 connected 阶段为 true，其余阶段均为 false', () {
      final roomState = RoomState();
      expect(roomState.isConnected.value, isFalse);

      roomState.connection.beginLinking();
      expect(roomState.isConnected.value, isFalse);

      roomState.connection.markConnected();
      expect(roomState.isConnected.value, isTrue);

      roomState.connection.beginDisconnecting();
      expect(roomState.isConnected.value, isFalse);

      roomState.connection.reset();
      expect(roomState.isConnected.value, isFalse);
    });
  });
}
