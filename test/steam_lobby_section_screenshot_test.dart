import 'dart:io';
import 'dart:ui' as ui;

import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:astral_game/src/rust/api/steam.dart';
import 'package:astral_game/ui/widgets/steam_lobby_list_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _game = GameInfo(
  id: 'stardew',
  name: 'Stardew Valley',
  nameZh: '星露谷物语',
  icon: Icons.agriculture_rounded,
  color: Color(0xFF7BA05B),
);

const _otherGame = GameInfo(
  id: 'terraria',
  name: 'Terraria',
  nameZh: '泰拉瑞亚',
  icon: Icons.forest_rounded,
  color: Color(0xFF8B6B3D),
);

SteamLobbyInfo _room({
  required String id,
  required String name,
  required int players,
  int capacity = 8,
  String gate = kSteamLobbyGateBasic,
  String version = kSteamLobbyProtocolVersion,
  bool joinable = true,
}) {
  return SteamLobbyInfo(
    lobbyId: id,
    gameId: _game.id,
    name: name,
    gate: gate,
    version: version,
    hostSteamId: '76561198000000000',
    players: players,
    capacity: capacity,
    joinable: joinable,
  );
}

void main() {
  setUpAll(() async {
    // 测试环境默认 Ahem 字体，中文和图标会变成方块；用系统黑体和 SDK 图标字体替代。
    await _loadFont('Noto Sans', r'C:\Windows\Fonts\simhei.ttf');
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      await _loadFont(
        'MaterialIcons',
        '$flutterRoot\\bin\\cache\\artifacts\\material_fonts\\materialicons-regular.otf',
      );
    }
  });

  testWidgets('导出房间列表三种验收截图', (tester) async {
    final scenarios = <String, List<SteamLobbyInfo>>{
      'rooms': [
        _room(id: '1', name: '星露谷 · 小木屋', players: 2),
        _room(id: '2', name: '泰拉瑞亚 · 开荒', players: 4),
        _room(id: '3', name: '深岩银河 · 挖矿队', players: 1, capacity: 4),
      ],
      'empty': const [],
      'mixed': [
        _room(
          id: '4',
          name: '星露谷 · 需要口令',
          players: 5,
          gate: kSteamLobbyGateDouble,
        ),
        _room(id: '5', name: '星露谷 · 周末农场', players: 8),
        _room(
          id: '6',
          name: '星露谷 · 旧版本房间',
          players: 3,
          version: 'old',
          joinable: false,
        ),
        _room(id: '7', name: '星露谷 · 已关闭', players: 2, joinable: false),
        _room(
          id: '8',
          name: '星露谷 · 新人房',
          players: 3,
          gate: kSteamLobbyGateOpen,
        ),
      ],
    };

    for (final entry in scenarios.entries) {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AstralGameTheme.defaultTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 760,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: SteamLobbyListView(
                      catalog: const [_game, _otherGame],
                      game: _game,
                      rooms: entry.value,
                      loading: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, boundaryKey, entry.key);
    }
  });
}

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/evidence')..createSync(recursive: true);
    File(
      '${dir.path}/steam-lobby-$name.png',
    ).writeAsBytesSync(data!.buffer.asUint8List());
  });
}
