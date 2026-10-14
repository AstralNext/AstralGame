import 'dart:convert';
import 'dart:io';

import 'package:astral_game/config/network_constants.dart';
import 'package:astral_game/data/services/network_optimize_service.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Windows：把远端 `smartdns.conf` 同步到已安装的 SmartDNS 服务。
///
/// 对齐游戏规则目录的做法——磁盘 ETag + `If-None-Match`，只有远端确实变了才
/// 交给 `auto_dns_binder deploy-conf` 重新部署并重启服务（binder 侧带备份+回滚）。
/// 任何一步失败都保留本地配置：拉配置失败绝不能让网络优化本身失效。
class SmartDnsConfigUpdater {
  SmartDnsConfigUpdater({
    required NetworkOptimizeService networkOptimize,
    Directory? cacheDir,
    http.Client? client,
    Future<bool> Function(String path)? deployer,
  })  : _networkOptimize = networkOptimize,
        _cacheDir = cacheDir,
        _client = client ?? http.Client(),
        _deployer = deployer;

  static const _confName = 'smartdns.conf.remote';
  static const _etagName = 'smartdns.conf.remote.etag';

  final NetworkOptimizeService _networkOptimize;
  final Directory? _cacheDir;
  final http.Client _client;
  final Future<bool> Function(String path)? _deployer;

  void close() => _client.close();

  /// 启动时调用一次：拉远端配置并部署；未启用网络加速时直接跳过。
  Future<void> checkAndApply() async {
    if (!RuntimePlatform.isWindows) return;
    try {
      await _networkOptimize.refresh();
      if (!_networkOptimize.installed.value) {
        appLogger.d('[SmartDns] 未启用网络加速，跳过配置同步');
        return;
      }

      final etag = await _readEtag();
      final res = await _client
          .get(
            Uri.parse(kSmartDnsConfUrl),
            headers: {
              if (etag != null && etag.isNotEmpty) 'If-None-Match': etag,
            },
          )
          .timeout(kSmartDnsConfTimeout);

      if (res.statusCode == 304) {
        appLogger.d('[SmartDns] 远端配置未变化');
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        appLogger.w('[SmartDns] 远端 HTTP ${res.statusCode}，保留本地配置');
        return;
      }

      final text = utf8.decode(res.bodyBytes);
      if (!looksLikeSmartDnsConf(text)) {
        appLogger.w('[SmartDns] 远端配置未通过校验，放弃部署');
        return;
      }

      final file = await _writeLocal(text);
      if (file == null) return;

      if (!await _deploy(file.path)) {
        appLogger.w('[SmartDns] 部署失败（binder 已回滚），保留本地配置');
        return;
      }

      await _writeEtag(res.headers['etag']);
      appLogger.i('[SmartDns] 已下发远端配置');
    } catch (e) {
      appLogger.w('[SmartDns] 配置同步失败: $e');
    }
  }

  Future<bool> _deploy(String path) async {
    final custom = _deployer;
    if (custom != null) return custom(path);

    final exe = findBinderExe();
    if (exe == null) {
      appLogger.w('[SmartDns] 找不到 auto_dns_binder.exe');
      return false;
    }
    final result = await Process.run(exe, ['deploy-conf', path]);
    final stdout = result.stdout.toString().trim();
    final stderr = result.stderr.toString().trim();
    if (stdout.isNotEmpty) appLogger.i('[SmartDns] $stdout');
    if (result.exitCode != 0) {
      appLogger.w(
        '[SmartDns] deploy-conf 退出码 ${result.exitCode}: '
        '${stderr.isNotEmpty ? stderr : stdout}',
      );
      return false;
    }
    return true;
  }

  Future<File?> _writeLocal(String text) async {
    final dir = _cacheDir;
    if (dir == null) return null;
    try {
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, _confName));
      await file.writeAsString(text, flush: true);
      return file;
    } catch (e) {
      appLogger.w('[SmartDns] 写入本地配置失败: $e');
      return null;
    }
  }

  File? get _etagFile {
    final dir = _cacheDir;
    if (dir == null) return null;
    return File(p.join(dir.path, _etagName));
  }

  Future<String?> _readEtag() async {
    final file = _etagFile;
    if (file == null || !file.existsSync()) return null;
    try {
      final value = (await file.readAsString()).trim();
      return value.isEmpty ? null : value;
    } catch (e) {
      appLogger.w('[SmartDns] 读取 ETag 失败: $e');
      return null;
    }
  }

  Future<void> _writeEtag(String? etag) async {
    final file = _etagFile;
    if (file == null) return;
    try {
      await file.writeAsString(etag?.trim() ?? '', flush: true);
    } catch (e) {
      appLogger.w('[SmartDns] 写入 ETag 失败: $e');
    }
  }
}

/// 远端配置的最低可信度检查。
///
/// DNS 配置写坏的代价是整机域名解析不了，所以远端内容必须同时具备
/// 监听（`bind` / `bind-tcp`）和上游（`server*`）两类指令才允许下发。
bool looksLikeSmartDnsConf(String text) {
  if (text.trim().isEmpty) return false;
  if (text.length > 512 * 1024) return false;
  if (text.contains('\u0000')) return false;
  final hasBind = RegExp(r'^[ \t]*bind(-tcp)?\s', multiLine: true).hasMatch(text);
  final hasUpstream =
      RegExp(r'^[ \t]*server(-https|-tls|-tcp|-udp)?\s+\S', multiLine: true)
          .hasMatch(text);
  return hasBind && hasUpstream;
}
