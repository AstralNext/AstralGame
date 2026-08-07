import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:flutter/material.dart';

/// 线上规则与相对路径图片基准。
const kAstralGameRulesUrl = 'https://astral.fan/gamerules.json';
const kAstralGameMediaBaseUrl = 'https://astral.fan/';

/// 可选游戏目录项（由远程 / 本地规则填充，见 [GameCatalog]）。
class GameInfo {
  const GameInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.steamAppId,
    this.sgdbGameId,
    this.iconAsset,
    this.gridAsset,
    this.showInPicker = true,
    this.sort = 100,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color color;

  /// Steam AppID（有则脚本用 `/games/steam/{id}` 解析 SGDB id）。
  final int? steamAppId;

  /// SteamGridDB 游戏 id（无 Steam 时直接用，如 Minecraft）。
  final int? sgdbGameId;

  /// 方形 icon：本地 `assets/...`、绝对 URL，或相对 `https://astral.fan/` 的路径。
  final String? iconAsset;

  /// 竖版封面：同 [iconAsset]。
  final String? gridAsset;

  final bool showInPicker;
  final int sort;

  bool get hasIconAsset => iconAsset != null && iconAsset!.isNotEmpty;
  bool get hasGridAsset => gridAsset != null && gridAsset!.isNotEmpty;

  factory GameInfo.fromRules(GameAssistGameRules rules) {
    return GameInfo(
      id: rules.id,
      name: rules.name,
      icon: resolveGameIcon(rules.iconName),
      color: parseGameColor(rules.colorHex),
      steamAppId: rules.steamAppId,
      sgdbGameId: rules.sgdbGameId,
      iconAsset: rules.iconAsset,
      gridAsset: rules.gridAsset,
      showInPicker: rules.showInPicker,
      sort: rules.sort,
    );
  }
}

/// 游戏目录：运行时由 [GameAssistRulesService] 注入。
class GameCatalog {
  static List<GameInfo> _items = const [];

  static List<GameInfo> get items => List<GameInfo>.unmodifiable(_items);

  /// 创建房间选择器列表（尊重 `show_in_picker`）。
  static List<GameInfo> get pickerItems =>
      _items.where((g) => g.showInPicker).toList(growable: false);

  static void applyFromRules(GameAssistRulesCatalog catalog) {
    _items = [
      for (final g in catalog.games) GameInfo.fromRules(g),
    ];
  }

  static GameInfo? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final g in _items) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// 需要从 SteamGridDB 拉取封面的条目（供下载脚本对照）。
  static Iterable<GameInfo> get coverFetchTargets =>
      _items.where((g) => g.steamAppId != null || g.sgdbGameId != null);
}

Color parseGameColor(String raw) {
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) hex = 'FF$hex';
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return const Color(0xFF6B7280);
  return Color(value);
}

IconData resolveGameIcon(String name) {
  switch (name.trim()) {
    case 'terrain':
      return Icons.terrain;
    case 'forest':
      return Icons.forest;
    case 'ac_unit':
      return Icons.ac_unit;
    case 'pets':
      return Icons.pets;
    case 'sports_esports':
      return Icons.sports_esports;
    case 'sports_esports_outlined':
      return Icons.sports_esports_outlined;
    case 'videogame_asset':
      return Icons.videogame_asset;
    case 'extension':
      return Icons.extension;
    default:
      return Icons.sports_esports_outlined;
  }
}

/// `icon_asset` / `grid_asset`：本地 asset、绝对 URL，或相对站点路径。
enum GameMediaKind { asset, network }

class GameMediaRef {
  const GameMediaRef.asset(this.path) : kind = GameMediaKind.asset, url = null;
  const GameMediaRef.network(this.url) : kind = GameMediaKind.network, path = null;

  final GameMediaKind kind;
  final String? path;
  final String? url;

  static GameMediaRef? tryParse(
    String? raw, {
    String baseUrl = kAstralGameMediaBaseUrl,
  }) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return GameMediaRef.network(s);
    }
    if (lower.startsWith('assets/')) {
      return GameMediaRef.asset(s);
    }
    final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    final resolved = s.startsWith('/')
        ? base.replace(path: s)
        : base.resolve(s);
    return GameMediaRef.network(resolved.toString());
  }
}

/// 按 [GameMediaRef] 渲染图片（asset 或网络）。
class GameMediaImage extends StatelessWidget {
  const GameMediaImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final ref = GameMediaRef.tryParse(source);
    if (ref == null) {
      return errorBuilder?.call(context, 'empty media', StackTrace.empty) ??
          const SizedBox.shrink();
    }
    if (ref.kind == GameMediaKind.network) {
      return Image.network(
        ref.url!,
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: errorBuilder,
      );
    }
    return Image.asset(
      ref.path!,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
}

/// 游戏方形 Logo：优先 icon_asset，否则色块 + Material 图标。
class GameLogo extends StatelessWidget {
  const GameLogo({
    super.key,
    required this.game,
    this.size = 40,
  });

  final GameInfo game;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.22);
    if (game.hasIconAsset) {
      return ClipRRect(
        borderRadius: radius,
        child: GameMediaImage(
          source: game.iconAsset!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _fallback(radius),
        ),
      );
    }
    return _fallback(radius);
  }

  Widget _fallback(BorderRadius radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: game.color.withValues(alpha: 0.18),
        borderRadius: radius,
        border: Border.all(color: game.color.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Icon(game.icon, size: size * 0.52, color: game.color),
    );
  }
}

/// 竖版封面；无资源时回退 Logo。
class GameGridCover extends StatelessWidget {
  const GameGridCover({
    super.key,
    required this.game,
    this.width = 72,
    this.height = 108,
    this.borderRadius = 10,
  });

  final GameInfo game;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!game.hasGridAsset) {
      return SizedBox(
        width: width,
        height: height,
        child: GameLogo(game: game, size: width.clamp(40, height)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: GameMediaImage(
        source: game.gridAsset!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => SizedBox(
          width: width,
          height: height,
          child: GameLogo(game: game, size: width.clamp(40, height)),
        ),
      ),
    );
  }
}
