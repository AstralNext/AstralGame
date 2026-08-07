import 'package:flutter/painting.dart';

/// Material 3 圆角令牌。
class AppRadius {
  AppRadius._();
  static final brSmall = BorderRadius.all(Radius.circular(16));
  static final brMedium = BorderRadius.all(Radius.circular(18));
  static final brLarge = BorderRadius.all(Radius.circular(20));
}

/// MD3 设计规范 - 状态颜色（语义色）
class AppColors {
  AppColors._();
  static const Color online = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFEF5350);
  static const Color info = Color(0xFF2196F3);
}

/// 应用常量定义
class AppConstants {
  AppConstants._();

  // 默认 IP 地址
  static const String defaultVirtualIp = '';

  // 网络相关
  static const Duration pollingInterval = Duration(seconds: 3);
  static const Duration pingTimeout = Duration(seconds: 5);
  static const int maxPingLatencyMs = 800;

  // 分享码/房间码 显示长度（用于 UI 截断预览）
  static const int uuidDisplayLength = 8;

  /// 加入历史最多保留条数（最新在前，按分享码去重）。
  static const int maxJoinHistoryEntries = 15;

  // 主机名过滤（中继节点不进成员列表）
  static const String publicServerHostname = 'PublicServer';

  // GitHub 更新检测（https://github.com/AstralNext/AstralGame/releases）
  static const String githubOwner = 'AstralNext';
  static const String githubRepo = 'AstralGame';
  static const String githubReleasesUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases?per_page=20';
  static const String githubReleasesPage =
      'https://github.com/$githubOwner/$githubRepo/releases';
  static const String githubRepoPage =
      'https://github.com/$githubOwner/$githubRepo';
  static const String githubIssuesPage =
      'https://github.com/$githubOwner/$githubRepo/issues';
}
