import 'package:signals/signals_core.dart';

/// 连接阶段：全应用唯一权威的连接状态。
///
/// UI 不再根据「有没有 session」「实例是否启动」各自推导，只读 phase 及其派生值。
enum ConnectionPhase {
  /// 没有房间会话，也没有传输层对象。
  idle,

  /// 会话已建立，传输尚未可用（授权、启动实例、等 TUN/VPN/SDR、校验服务器连通）。
  linking,

  /// 传输真正可用。
  connected,

  /// 正在拆连接。
  disconnecting,
}

/// 驱动 [ConnectionPhase] 的最小状态机。
///
/// 只负责状态迁移，不持有任何业务对象；由 `ConnectionService` 驱动、
/// 由 `RoomState` 持有，UI 通过 `RoomState.connection` 读取。
class ConnectionStateController {
  final phaseSignal = signal<ConnectionPhase>(ConnectionPhase.idle);

  /// 最近一次失败原因，仅用于日志/诊断；失败后 phase 会回到 [ConnectionPhase.idle]。
  final lastFailureSignal = signal<Object?>(null);

  ConnectionPhase get phase => phaseSignal.value;

  Object? get lastFailure => lastFailureSignal.value;

  /// 进入连接流程。重复调用不会重置已有阶段（由调用方负责防重）。
  void beginLinking() {
    lastFailureSignal.value = null;
    phaseSignal.value = ConnectionPhase.linking;
  }

  void markConnected() {
    phaseSignal.value = ConnectionPhase.connected;
  }

  void beginDisconnecting() {
    if (phaseSignal.value != ConnectionPhase.idle) {
      phaseSignal.value = ConnectionPhase.disconnecting;
    }
  }

  /// 回到空闲；[failure] 非空时记录失败原因供日志使用。
  void reset({Object? failure}) {
    if (failure != null) {
      lastFailureSignal.value = failure;
    }
    phaseSignal.value = ConnectionPhase.idle;
  }
}
