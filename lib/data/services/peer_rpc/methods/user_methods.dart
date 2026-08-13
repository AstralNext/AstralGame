import 'dart:convert';
import 'dart:typed_data';

import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/connectivity_status_service.dart';
import 'package:astral_game/data/services/firewall_service.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_router.dart';
import 'package:astral_game/utils/avatar_hash.dart';
import 'package:astral_game/utils/client_runtime_info.dart';
import 'package:get_it/get_it.dart';

/// 用户相关方法
class UserMethods {
  final AppSettingsService _settings;

  UserMethods(this._settings);

  /// 获取用户信息
  ///
  /// 除昵称、头像外附带本机环境：`os`、`osVersion`、`appName`、`appVersion`、
  /// `network`、`firewall`（Windows 专用配置文件），便于房间内共享展示。
  ///
  /// [params.avatarHash] 为对端已知 hash；相同则不回传整图。
  Future<Map<String, dynamic>> getInfo(dynamic params) async {
    final avatar = _settings.getAvatar();
    final hash = avatarContentHash(avatar);
    final knownHash = _avatarHashFromParams(params);
    final connectivity = GetIt.I.isRegistered<ConnectivityStatusService>()
        ? GetIt.I<ConnectivityStatusService>().current.value
        : NetworkKind.unknown;
    if (GetIt.I.isRegistered<FirewallService>()) {
      await GetIt.I<FirewallService>().refreshPrivateProfile();
    }
    final firewall = GetIt.I.isRegistered<FirewallService>()
        ? GetIt.I<FirewallService>().firewallWireValue()
        : 'unsupported';
    return {
      'name': _settings.getUsername(),
      'avatarHash': hash,
      'avatar': shouldSendAvatarBytes(knownHash, hash) && avatar != null
          ? base64Encode(avatar)
          : null,
      'os': ClientRuntimeInfo.operatingSystem,
      'osVersion': ClientRuntimeInfo.operatingSystemVersion,
      'appName': ClientRuntimeInfo.appName,
      'appVersion': ClientRuntimeInfo.appVersion,
      'network': connectivity.wireValue,
      'firewall': firewall,
    };
  }

  String? _avatarHashFromParams(dynamic params) {
    if (params is! Map) return null;
    final raw = params['avatarHash'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// 更新用户信息
  Future<Map<String, dynamic>> update(dynamic params) async {
    if (params is Map) {
      if (params['name'] != null) {
        await _settings.setUsername(params['name'] as String);
      }

      if (params['avatar'] != null) {
        final avatarBase64 = params['avatar'] as String;
        await _settings.setAvatar(
          Uint8List.fromList(base64Decode(avatarBase64)),
        );
      }
    }

    return {'success': true};
  }

  /// 获取所有方法
  Map<String, MethodHandler> get methods => {
        'user.getInfo': getInfo,
        'user.update': update,
      };
}
