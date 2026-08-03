import 'dart:convert';
import 'dart:io';

import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';

class ServerPersistenceService {
  static const _fileName = 'servers.json';

  Future<String> get _filePath async {
    final dir = await getApplicationSupportDirectory();
    return path_lib.join(dir.path, _fileName);
  }

  Future<List<ServerMod>> loadServers() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);
      if (!await file.exists()) {
        return [];
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return [];
      }
      final list = jsonDecode(content) as List;
      int maxId = 0;
      final servers = list
          .map((e) {
            final server = ServerMod.fromJson(e as Map<String, dynamic>);
            if (server.id > maxId) {
              maxId = server.id;
            }
            return server;
          })
          .toList();
      // 确保 nextId 大于所有已存在的 ID，防止 ID 冲突
      ServerMod.setNextId(maxId + 1);
      return servers;
    } catch (e) {
      return [];
    }
  }

  Future<void> saveServers(List<ServerMod> servers) async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);
      final json = jsonEncode(servers.map((s) => s.toJson()).toList());
      await file.writeAsString(json);
    } catch (e, stackTrace) {
      appLogger.e('[ServerPersistenceService] 保存服务器失败: $e', error: e, stackTrace: stackTrace);
    }
  }
}