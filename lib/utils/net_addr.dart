/// `224.0.2.60:4445` → host + port。
({String host, int port})? parseHostPort(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  final i = s.lastIndexOf(':');
  if (i <= 0 || i == s.length - 1) return (host: s, port: 0);
  final port = int.tryParse(s.substring(i + 1).trim());
  if (port == null || port <= 0 || port > 65535) {
    return (host: s, port: 0);
  }
  return (host: s.substring(0, i).trim(), port: port);
}

/// 去掉 CIDR，得到纯地址；空或未指定地址则 null。
String? stripCidrHost(
  String? raw, {
  Set<String> unspecified = const {'0.0.0.0', '::'},
}) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  final slash = s.indexOf('/');
  if (slash >= 0) s = s.substring(0, slash).trim();
  if (s.isEmpty || unspecified.contains(s)) return null;
  return s;
}

/// 去掉 CIDR，得到纯 IPv4；无效则 null。
String? stripIpv4Host(String? raw) =>
    stripCidrHost(raw, unspecified: const {'0.0.0.0'});
