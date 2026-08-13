/// 表单校验（VPN 路由等）。
class InputValidator {
  InputValidator._();

  /// 验证 IPv4 地址（可带 `/prefix`）。
  static String? validateIPv4(String? value) {
    if (value == null || value.isEmpty) {
      return '请输入 IP 地址';
    }
    final parts = value.split('/');
    if (parts.length > 2) {
      return '无效的 IP 地址格式';
    }

    final ipPart = parts[0];
    if (ipPart.isEmpty) {
      return '请输入 IP 地址';
    }

    final octets = ipPart.split('.');
    if (octets.length != 4) {
      return 'IPv4 地址必须包含 4 个八位组';
    }

    for (final octet in octets) {
      try {
        final octetValue = int.parse(octet);
        if (octetValue < 0 || octetValue > 255) {
          return '每个八位组必须在 0-255 之间';
        }
      } catch (e) {
        return '无效的 IP 地址';
      }
    }

    if (parts.length == 2) {
      final maskPart = parts[1];
      if (maskPart.isEmpty) {
        return '请输入子网掩码';
      }
      try {
        final mask = int.parse(maskPart);
        if (mask < 0 || mask > 32) {
          return '子网掩码必须在 0-32 之间';
        }
      } catch (e) {
        return '无效的子网掩码';
      }
    }

    return null;
  }

  /// 验证 CIDR（必须带前缀，如 `192.168.1.0/24`）。
  static String? validateCidr(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      return '请输入网段，例如 192.168.1.0/24';
    }
    final parts = v.split('/');
    if (parts.length != 2) {
      return '格式应为 IP/前缀，例如 192.168.1.0/24';
    }
    return validateIPv4(v);
  }
}
