import 'package:astral_game/data/services/open_games_service.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_router.dart';

/// 开放游戏：经 ET 隧道同步列表。
class GameMethods {
  GameMethods(this._openGames);

  final OpenGamesService _openGames;

  Map<String, MethodHandler> get methods => {
        'game.listOpen': listOpen,
        // notify 也注册空 handler，实际由 OpenGamesService 的 listener 处理。
        'game.advertiseOpen': advertiseOpen,
      };

  Future<Map<String, dynamic>> listOpen(dynamic params) async {
    return {
      'gameId': _openGames.roomGameId,
      'ads': _openGames.localAdsWire(),
    };
  }

  Future<void> advertiseOpen(dynamic params) async {
    // 列表合并在 OpenGamesService.notify listener。
  }
}
