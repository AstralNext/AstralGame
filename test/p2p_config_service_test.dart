import 'package:astral_game/config/network_constants.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/p2p_config_service.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late P2PConfigService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = P2PConfigService(AppSettingsService(prefs), ServerState());
  });

  test('DHCP 打开时写初始网段 CIDR，而不是裸 true', () {
    final toml = service.buildTomlConfig('room', 'secret');

    expect(toml, contains('dhcp = "$kRoomDhcpIpv4Cidr"'));
    expect(toml, contains('dhcpv6 = "$kRoomDhcpIpv6Cidr"'));
    expect(toml, isNot(contains('dhcp = true')));
    expect(toml, isNot(contains('dhcpv6 = true')));
  });

  test('关闭 DHCP 时写 false，固定 IP 落到顶层 ipv4', () {
    final toml = service.buildTomlConfig(
      'room',
      'secret',
      isDhcp: false,
      isDhcpv6: false,
      virtualIp: '10.0.0.8',
    );

    expect(toml, contains('dhcp = false'));
    expect(toml, contains('dhcpv6 = false'));
    expect(toml, contains('ipv4 = "10.0.0.8"'));
    // 关闭 DHCP 时不应再写网段
    expect(toml, isNot(contains(kRoomDhcpIpv4Cidr)));
  });

  test('固定 IP 为空时不留 ipv4 行', () {
    final toml = service.buildTomlConfig(
      'room',
      'secret',
      isDhcp: false,
      virtualIp: '   ',
    );

    expect(toml, contains('dhcp = false'));
    expect(toml, isNot(contains('ipv4 =')));
  });
}
