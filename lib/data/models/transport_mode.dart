import 'package:astral_game/utils/runtime_platform.dart';

/// 联机模式：决定房间数据走哪一套组网驱动。
enum TransportMode {
  /// 虚拟局域网（默认，现有行为）。
  easytier,

  /// Steam 组网：经 Steam 中继建虚拟网卡，成员间虚拟 IP 直连。
  steam,
}

extension TransportModeX on TransportMode {
  String get storageValue => switch (this) {
    TransportMode.easytier => 'easytier',
    TransportMode.steam => 'steam',
  };

  String get label => switch (this) {
    TransportMode.easytier => 'EasyTier 组网',
    TransportMode.steam => 'Steam 组网',
  };

  /// 下拉列表里的短名称（避免在设置行 trailing 溢出）。
  String get menuLabel => switch (this) {
    TransportMode.easytier => 'EasyTier',
    TransportMode.steam => 'Steam',
  };

  String get description => switch (this) {
    TransportMode.easytier => '由 EasyTier 虚拟网卡组网，支持全部局域网游戏',
    TransportMode.steam => '由 Steam 中继建立虚拟局域网，为成员分配虚拟 IP（实验性）',
  };

  /// 是否需要在 Windows 上使用独立的虚拟网卡驱动（非 EasyTier）。
  bool get isTunnelTransport => this == TransportMode.steam;
}

TransportMode transportModeFromStorage(String? raw) {
  return switch (raw) {
    'steam' => TransportMode.steam,
    // Holepunch Pear 模式已移除，历史配置回落到 Steam，避免读取时崩溃或停在空态。
    'pear' => TransportMode.steam,
    _ => TransportMode.easytier,
  };
}

/// 传输模式判定所依赖的平台。
///
/// 单独建模而不是直接在判定里读 [RuntimePlatform]，是为了让「非 Windows」
/// 分支可以在测试里注入。
enum TransportPlatform {
  windows,
  macOS,
  linux,
  android,
  ios,
  other;

  /// 当前进程所在平台。
  static TransportPlatform get current => switch (
    RuntimePlatform.operatingSystem
  ) {
    'windows' => TransportPlatform.windows,
    'macos' => TransportPlatform.macOS,
    'linux' => TransportPlatform.linux,
    'android' => TransportPlatform.android,
    'ios' => TransportPlatform.ios,
    _ => TransportPlatform.other,
  };
}

/// 传输模式可用性的唯一判定入口。
///
/// 所有决定「某个模式能否出现 / 能否使用」的地方都必须经过它：设置页下拉、
/// 传输详情页、邀请与收藏解析、启动时的默认模式。以后新增平台或新增实验性
/// 能力，只改这里即可。
class TransportGate {
  const TransportGate({
    required this.platform,
    required this.experimentalSteamEnabled,
  });

  /// 读取当前运行时状态。
  factory TransportGate.current({required bool experimentalSteamEnabled}) =>
      TransportGate(
        platform: TransportPlatform.current,
        experimentalSteamEnabled: experimentalSteamEnabled,
      );

  final TransportPlatform platform;

  /// 「实验性功能」开关状态；非 Windows 上始终按关闭处理。
  final bool experimentalSteamEnabled;

  bool isAvailable(TransportMode mode) => switch (mode) {
    TransportMode.easytier => true,
    TransportMode.steam =>
      platform == TransportPlatform.windows && experimentalSteamEnabled,
  };

  /// 当前环境允许出现在选择器里的模式。
  List<TransportMode> get availableModes => [
    for (final mode in TransportMode.values)
      if (isAvailable(mode)) mode,
  ];

  /// 「实验性功能」开关本身是否可见（Steam 仅在 Windows 存在）。
  bool get canToggleExperimentalSteam =>
      platform == TransportPlatform.windows;

  /// 模式不可用时的可读原因；可用时返回 null。
  String? unavailableReason(TransportMode mode) {
    if (isAvailable(mode)) return null;
    return switch (mode) {
      TransportMode.easytier => null,
      // 非 Windows 上不出现任何 Steam 字样：用中性文案说明该模式不可用。
      TransportMode.steam => platform == TransportPlatform.windows
          ? 'Steam 组网是实验性功能，请先在「设置 → 应用」打开「实验性功能」'
          : '当前平台不支持该联机模式',
    };
  }

  /// 历史配置 / 邀请里的模式在当前环境不可用时，回落到 EasyTier。
  TransportMode fallback(TransportMode mode) =>
      isAvailable(mode) ? mode : TransportMode.easytier;
}
