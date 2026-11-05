import 'package:astral_game/utils/runtime_platform.dart';

/// 联机模式：决定房间数据走哪一套组网驱动。
enum TransportMode {
  /// 虚拟局域网（默认，现有行为）。
  easytier,

  /// Steam 组网：经 Steam 中继建虚拟网卡，成员间虚拟 IP 直连。
  steam,

  /// Holepunch Pear 组网：经 HyperDHT 打洞 / 中继建虚拟局域网。
  pear,
}

extension TransportModeX on TransportMode {
  String get storageValue => switch (this) {
    TransportMode.easytier => 'easytier',
    TransportMode.steam => 'steam',
    TransportMode.pear => 'pear',
  };

  String get label => switch (this) {
    TransportMode.easytier => 'EasyTier 组网',
    TransportMode.steam => 'Steam 组网',
    TransportMode.pear => 'Holepunch Pear 组网',
  };

  /// 下拉列表里的短名称（避免在设置行 trailing 溢出）。
  String get menuLabel => switch (this) {
    TransportMode.easytier => 'EasyTier',
    TransportMode.steam => 'Steam',
    TransportMode.pear => 'Pear',
  };

  String get description => switch (this) {
    TransportMode.easytier => '由 EasyTier 虚拟网卡组网，支持全部局域网游戏',
    TransportMode.steam => '由 Steam 中继建立虚拟局域网，为成员分配虚拟 IP（实验性）',
    TransportMode.pear =>
      '由 Holepunch HyperDHT 打洞 / 中继建立虚拟局域网，为成员分配虚拟 IP（实验性）',
  };

  /// 是否需要在 Windows 上使用独立的虚拟网卡驱动（非 EasyTier）。
  bool get isTunnelTransport =>
      this == TransportMode.steam || this == TransportMode.pear;

  /// 当前平台是否支持该模式。
  bool get isSupported =>
      this == TransportMode.easytier || RuntimePlatform.isWindows;
}

TransportMode transportModeFromStorage(String? raw) {
  return switch (raw) {
    'steam' => TransportMode.steam,
    'pear' => TransportMode.pear,
    _ => TransportMode.easytier,
  };
}

/// Steam / Pear 驱动目前仅在 Windows 提供（桌面端才有对应运行时）。
bool get isTunnelTransportSupported => RuntimePlatform.isWindows;
