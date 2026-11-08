import 'dart:io';
import 'dart:ui' as ui;

import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:astral_game/src/rust/api/steam.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/astral_status_dot.dart';
import 'package:astral_game/ui/widgets/section_header.dart';
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
  String gameId = 'stardew',
}) {
  return SteamLobbyInfo(
    lobbyId: id,
    gameId: gameId,
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

  testWidgets('导出房间列表验收截图', (tester) async {
    final scenarios =
        <
          ({
            String name,
            GameInfo? game,
            SteamLobbyGateFilter gate,
            List<SteamLobbyInfo> rooms,
            double width,
            double height,
            double scale,
          })
        >[
          // 「全部」：跨游戏、跨门槛混排。
          (
            name: 'mixed',
            game: null,
            gate: SteamLobbyGateFilter.all,
            width: 760,
            height: 520,
            scale: 2,
            rooms: [
              _room(id: '1', name: '小木屋', players: 2),
              _room(
                id: '2',
                name: '开荒',
                players: 4,
                gameId: _otherGame.id,
              ),
              _room(
                id: '3',
                name: '需要口令',
                players: 5,
                gate: kSteamLobbyGateDouble,
              ),
              _room(id: '4', name: '周末农场', players: 8),
              _room(
                id: '5',
                name: '旧版本房间',
                players: 3,
                version: 'old',
                joinable: false,
                gameId: _otherGame.id,
              ),
              _room(
                id: '6',
                name: '新人房',
                players: 3,
                gate: kSteamLobbyGateOpen,
              ),
            ],
          ),
          (
            name: 'empty',
            game: null,
            gate: SteamLobbyGateFilter.all,
            width: 760,
            height: 520,
            scale: 2,
            rooms: const [],
          ),
          // 切到具体游戏标签。
          (
            name: 'terraria',
            game: _otherGame,
            gate: SteamLobbyGateFilter.all,
            width: 760,
            height: 520,
            scale: 2,
            rooms: [
              _room(
                id: '7',
                name: '开荒',
                players: 4,
                gameId: _otherGame.id,
              ),
              _room(
                id: '8',
                name: '硬核生存',
                players: 6,
                gameId: _otherGame.id,
              ),
            ],
          ),
          // 门槛筛选切到「需要口令」：只剩 basic / double 的房间。
          (
            name: 'secured',
            game: null,
            gate: SteamLobbyGateFilter.secured,
            width: 760,
            height: 520,
            scale: 2,
            rooms: [
              _room(id: '9', name: '小木屋', players: 2),
              _room(
                id: '10',
                name: '开荒',
                players: 4,
                gameId: _otherGame.id,
              ),
              _room(
                id: '11',
                name: '周末农场',
                players: 8,
                gate: kSteamLobbyGateOpen,
              ),
              _room(
                id: '12',
                name: '需要口令',
                players: 5,
                gate: kSteamLobbyGateDouble,
              ),
            ],
          ),
          // 小锁近景：3 倍像素，只留三行。
          (
            name: 'lock-detail',
            game: null,
            gate: SteamLobbyGateFilter.all,
            width: 560,
            height: 208,
            scale: 3,
            rooms: [
              _room(
                id: '13',
                name: '需要口令',
                players: 5,
                gate: kSteamLobbyGateDouble,
              ),
              _room(id: '14', name: '开荒', players: 4),
              _room(
                id: '15',
                name: '新人房',
                players: 3,
                gate: kSteamLobbyGateOpen,
              ),
            ],
          ),
        ];

    for (final scenario in scenarios) {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AstralGameTheme.defaultTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: scenario.width,
                height: scenario.height,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: SteamLobbyListView(
                      catalog: const [_game, _otherGame],
                      selectedGame: scenario.game,
                      gateFilter: scenario.gate,
                      rooms: scenario.rooms,
                      loading: false,
                      onSelectGame: (_) {},
                      onSelectGate: (_) {},
                      onRefresh: () {},
                      onInvite: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, boundaryKey, scenario.name, scenario.scale);
    }
  });

  testWidgets('导出两颗绿点并排近景', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AstralGameTheme.defaultTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: const _GreenDotsCard(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, boundaryKey, 'greens');
  });
}

/// 两颗绿点的并排近景：上半是列表里的真实 8px 尺寸，下半放大 4 倍便于核对色值。
class _GreenDotsCard extends StatelessWidget {
  const _GreenDotsCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    Widget item(AstralStatusTone tone, double size, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AstralStatusDot(tone: tone, size: size, semanticLabel: label),
          const SizedBox(width: 8),
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
          ),
        ],
      );
    }

    Widget row(String caption, double size) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 84,
              child: Text(
                caption,
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
            item(AstralStatusTone.ready, size, '可加入'),
            const SizedBox(width: 32),
            item(AstralStatusTone.secured, size, '需要口令'),
          ],
        ),
      );
    }

    return AstralCard(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: '两种绿', tone: SectionHeaderTone.muted),
          row('8px 实际', 8),
          Divider(height: 1, thickness: 1, color: palette.divider),
          row('4× 放大', 32),
        ],
      ),
    );
  }
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
  String name, [
  double pixelRatio = 2,
]) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/evidence')..createSync(recursive: true);
    File(
      '${dir.path}/steam-lobby-$name.png',
    ).writeAsBytesSync(data!.buffer.asUint8List());
  });
}
