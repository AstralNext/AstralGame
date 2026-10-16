import 'package:astral_game/config/network_constants.dart';

class SpeedTestNode {
  const SpeedTestNode({
    required this.ip,
    required this.port,
    this.name = '',
    this.province = '',
    this.city = '',
    this.operator = '',
  });

  final String ip;

  final String port;

  final String name;

  final String province;

  final String city;

  final String operator;

  String get endpoint => '$ip:$port';

  String get label {
    if (name.isNotEmpty) return name;
    if (regionLabel.isNotEmpty) return regionLabel;
    return '测速节点';
  }

  String get regionLabel {
    final String region;
    if (province.isEmpty) {
      region = city;
    } else if (city.isEmpty || city == province) {
      region = province;
    } else {
      region = '$province$city';
    }
    if (operator.isEmpty) return region;
    if (region.isEmpty) return operator;
    return '$operator · $region';
  }

  static SpeedTestNode? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final ip = (raw['hostip'] ?? '').toString().trim();
    if (ip.isEmpty) return null;
    final port = (raw['port'] ?? '').toString().trim();
    return SpeedTestNode(
      ip: ip,
      port: port.isEmpty ? '$kSpeedTestDefaultPort' : port,
      name: (raw['hostname'] ?? '').toString().trim(),
      province: (raw['pname'] ?? '').toString().trim(),
      city: (raw['location'] ?? '').toString().trim(),
      operator: (raw['oper'] ?? '').toString().trim(),
    );
  }
}
