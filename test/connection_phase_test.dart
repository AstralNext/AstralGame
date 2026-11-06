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

    test('传输就绪前断开：linking → disconnecting → idle，不会误报已连接', () {
      final roomState = RoomState()..connection.beginLinking();
      expect(roomState.isConnected.value, isFalse);

      roomState.connection.beginDisconnecting();
      expect(roomState.connection.phase, ConnectionPhase.disconnecting);
      expect(roomState.isConnected.value, isFalse);

      roomState.connection.reset();
      expect(roomState.connection.phase, ConnectionPhase.idle);
      expect(roomState.isConnected.value, isFalse);
    });

    test('断线重连：connected → linking → connected，中间态不误报已连接', () {
      final roomState = RoomState()..connection.markConnected();
      expect(roomState.isConnected.value, isTrue);

      roomState.connection.beginLinking();
      expect(roomState.connection.phase, ConnectionPhase.linking);
      expect(roomState.isConnected.value, isFalse);
      expect(roomState.connection.lastFailure, isNull);

      roomState.connection.markConnected();
      expect(roomState.isConnected.value, isTrue);
    });

    test('单一权威状态：isConnected 严格等于 phase == connected', () {
      for (final phase in ConnectionPhase.values) {
        final roomState = _roomInPhase(phase);
        expect(roomState.connection.phase, phase);
        expect(
          roomState.isConnected.value,
          phase == ConnectionPhase.connected,
          reason: 'phase=$phase 时派生值必须与映射表一致',
        );
      }
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

/// 通过合法迁移把状态机推到目标阶段，避免测试直接改 signal 绕过约束。
RoomState _roomInPhase(ConnectionPhase phase) {
  final roomState = RoomState();
  switch (phase) {
    case ConnectionPhase.idle:
      break;
    case ConnectionPhase.linking:
      roomState.connection.beginLinking();
    case ConnectionPhase.connected:
      roomState.connection.beginLinking();
      roomState.connection.markConnected();
    case ConnectionPhase.disconnecting:
      roomState.connection.beginLinking();
      roomState.connection.beginDisconnecting();
  }
  return roomState;
}
