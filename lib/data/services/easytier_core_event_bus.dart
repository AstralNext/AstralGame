import 'dart:async';

import 'package:astral_game/src/rust/api/p2p.dart' show CoreLogEventC;

/// EasyTier 内核事件总线。
///
/// Rust 侧 `subscribe_core_logs` 的 sink 是全局唯一的（重复订阅会顶掉前一个），
/// 因此由 DI 统一订阅一次，再经此总线广播给需要监听的模块（连接健康检查等）。
class EasyTierCoreEventBus {
  final StreamController<CoreLogEventC> _controller =
      StreamController<CoreLogEventC>.broadcast();

  /// 最近事件环形缓冲。
  ///
  /// `tun device ready` / `peer connection added` 往往在实例刚启动时就已发出，
  /// 而健康检查要等实例 Running 后才开始监听，直接订阅会漏掉这些已经发生的事件，
  /// 只能退化成轮询（最长多等一整个轮询周期）。晚到的监听方先用
  /// [recentEventsFor] 补看，能立刻判定就绪。
  static const int _recentLimit = 128;
  final List<CoreLogEventC> _recent = [];

  /// 所有实例的内核事件；监听方可按 `instanceId` 过滤。
  Stream<CoreLogEventC> get events => _controller.stream;

  /// 订阅之前该实例已发生的最近事件（按发生顺序）。
  List<CoreLogEventC> recentEventsFor(String instanceId) =>
      _recent.where((e) => e.instanceId == instanceId).toList();

  void add(CoreLogEventC event) {
    _recent.add(event);
    if (_recent.length > _recentLimit) {
      _recent.removeRange(0, _recent.length - _recentLimit);
    }
    if (!_controller.isClosed) _controller.add(event);
  }

  Future<void> dispose() => _controller.close();
}
