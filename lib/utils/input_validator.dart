/// 输入验证工具类
///
/// 提供常用的输入验证方法
class InputValidator {
  InputValidator._();

  /// 验证 URL
  ///
  /// 检查是否为有效的 URL 格式
  static String? validateUrl(String? value) {
    if (value == null || value.isEmpty) {
      return '请输入地址';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      return '请输入有效的 URL';
    }
    return null;
  }

  /// 验证房间分享码：`随机码_房间名`
  static String? validateShareCode(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      return '请输入房间分享码';
    }

    const tokenChars =
        r'[23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz]';
    final tokenName = RegExp('^$tokenChars{6,20}_.+\$');
    if (!tokenName.hasMatch(v)) {
      return '分享码格式不正确，应为：随机码_房间名';
    }
    return null;
  }

  /// 验证非空字符串
  ///
  /// 检查字符串是否为空
  static String? validateNonEmpty(String? value, [String? errorMessage]) {
    if (value == null || value.trim().isEmpty) {
      return errorMessage ?? '此字段不能为空';
    }
    return null;
  }

  /// 验证端口号
  ///
  /// 检查是否为有效的端口号（1-65535）
  static String? validatePort(String? value) {
    if (value == null || value.isEmpty) {
      return '请输入端口号';
    }
    final port = int.tryParse(value);
    if (port == null || port < 1 || port > 65535) {
      return '请输入有效的端口号（1-65535）';
    }
    return null;
  }

  /// 验证 IPv4 地址
  ///
  /// 检查是否为有效的 IPv4 地址
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

  /// 验证服务器地址
  ///
  /// 检查是否为有效的服务器地址（主机名:端口）
  static String? validateServerAddress(String? value) {
    if (value == null || value.isEmpty) {
      return '请输入服务器地址';
    }
    final parts = value.split(':');
    if (parts.length != 2) {
      return '格式应为 主机名:端口';
    }
    final port = int.tryParse(parts[1]);
    if (port == null || port < 1 || port > 65535) {
      return '端口号必须在 1-65535 之间';
    }
    return null;
  }

  /// 验证用户名
  ///
  /// 检查用户名长度和格式
  static String? validateUsername(String? value, {int minLength = 1, int maxLength = 50}) {
    if (value == null || value.isEmpty) {
      return '请输入用户名';
    }
    if (value.length < minLength) {
      return '用户名至少需要 $minLength 个字符';
    }
    if (value.length > maxLength) {
      return '用户名不能超过 $maxLength 个字符';
    }
    return null;
  }
}
