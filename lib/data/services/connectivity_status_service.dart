import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:signals/signals_core.dart';

import 'package:astral_game/utils/logger.dart';

/// 跨平台网络承载类型，便于在 RPC / UI 层做归一化。
/// 与 `connectivity_plus` 的 [`ConnectivityResult`] 一一对应（聚合后取主类型）。
enum NetworkKind {
  unknown,
  none,
  wifi,
  ethernet,
  mobile,
  bluetooth,
  satellite,
  other,
}

extension NetworkKindWire on NetworkKind {
  /// RPC 上报使用的稳定字符串（不要带本地化文案）。
  String get wireValue => name;

  static NetworkKind fromWire(String? raw) {
    if (raw == null || raw.isEmpty) return NetworkKind.unknown;
    for (final v in NetworkKind.values) {
      if (v.name == raw) return v;
    }
    return NetworkKind.unknown;
  }
}

/// 监听本机当前网络承载类型。
class ConnectivityStatusService {
  ConnectivityStatusService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// 当前网络类型；未启动前默认 [`NetworkKind.unknown`]。
  final current = signal<NetworkKind>(NetworkKind.unknown);

  /// 启动监听（带一次主动 check）。重复调用幂等。
  Future<void> start() async {
    if (_sub != null) return;
    try {
      final initial = await _connectivity.checkConnectivity();
      current.value = _aggregate(initial);
    } catch (e) {
      appLogger.w('[Connectivity] checkConnectivity 失败: $e');
    }
    _sub = _connectivity.onConnectivityChanged.listen(
      (event) {
        current.value = _aggregate(event);
      },
      onError: (Object e) {
        appLogger.w('[Connectivity] onConnectivityChanged 错误: $e');
      },
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// 多个并发承载（如同时插网线 + Wi-Fi）时取「优先级最高」的一种来展示。
  NetworkKind _aggregate(List<ConnectivityResult> results) {
    if (results.isEmpty) return NetworkKind.unknown;
    if (results.contains(ConnectivityResult.none)) return NetworkKind.none;
    // 优先级用于"哪根网线 / 哪种无线"这类承载介质判定；其它上层封装统一走 `_map` 的 default。
    const priority = [
      ConnectivityResult.ethernet,
      ConnectivityResult.wifi,
      ConnectivityResult.mobile,
      ConnectivityResult.bluetooth,
      // ignore: deprecated_member_use
      ConnectivityResult.other,
    ];
    for (final p in priority) {
      if (results.contains(p)) return _map(p);
    }
    // 兜底（满足较新枚举如 satellite）
    return _map(results.first);
  }

  NetworkKind _map(ConnectivityResult r) {
    switch (r) {
      case ConnectivityResult.wifi:
        return NetworkKind.wifi;
      case ConnectivityResult.ethernet:
        return NetworkKind.ethernet;
      case ConnectivityResult.mobile:
        return NetworkKind.mobile;
      case ConnectivityResult.bluetooth:
        return NetworkKind.bluetooth;
      case ConnectivityResult.none:
        return NetworkKind.none;
      case ConnectivityResult.other:
        return NetworkKind.other;
      default:
        // satellite 等较新枚举走名字匹配；未列出的统一兜底为 other。
        if (r.name == 'satellite') return NetworkKind.satellite;
        return NetworkKind.other;
    }
  }
}
