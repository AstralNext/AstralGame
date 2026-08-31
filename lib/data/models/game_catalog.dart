import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 线上规则与相对路径图片基准。
const kAstralGameRulesUrl = 'https://next.astral.fan/gamerules.json';
const kAstralGameMediaBaseUrl = 'https://next.astral.fan/';

/// 可选游戏目录项（由远程 / 本地规则填充，见 [GameCatalog]）。
class GameInfo {
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
      description: rules.description,
      nameZh: rules.nameZh,
    );
  }
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
    this.description = '',
    this.nameZh = '',
  });

  final String id;
  final String name;
  final IconData icon;
  final Color color;

  /// Steam AppID（有则脚本用 `/games/steam/{id}` 解析 SGDB id）。
  final int? steamAppId;

  /// SteamGridDB 游戏 id（无 Steam 时直接用，如 Minecraft）。
  final int? sgdbGameId;

  /// 方形 icon：本地 `assets/...`、绝对 URL，或相对 `https://next.astral.fan/` 的路径。
  final String? iconAsset;

  /// 竖版封面：同 [iconAsset]。
  final String? gridAsset;

  final bool showInPicker;
  final int sort;
  final String description;

  /// 中文名；有则 [displayName] 优先用它。
  final String nameZh;

  /// 有中文名则用中文，否则英文 `name`。
  String get displayName => nameZh.trim().isNotEmpty ? nameZh.trim() : name;

  bool get hasIconAsset => iconAsset != null && iconAsset!.isNotEmpty;
  bool get hasGridAsset => gridAsset != null && gridAsset!.isNotEmpty;

  /// JSON 未写封面时，回退到按 id 推断的路径（先找本地 asset，没有再走远程 CDN）。
  String get resolvedGridAsset {
    final g = gridAsset?.trim() ?? '';
    if (g.isNotEmpty) return g;
    // 纯相对路径格式 → GameMediaImage 会先试本地 asset，失败再走远程
    return 'games/$id/grid.png';
  }

  /// 方形 icon 的解析路径（与 resolvedGridAsset 策略一致，用于 hasIconAsset 判断）。
  String get resolvedIconAsset {
    final g = iconAsset?.trim() ?? '';
    if (g.isNotEmpty) return g;
    return 'games/$id/icon.png';
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
    _items = [for (final g in catalog.games) GameInfo.fromRules(g)];
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

const _kGameIconMap = <String, IconData>{
  'terrain': Icons.terrain,
  'forest': Icons.forest,
  'ac_unit': Icons.ac_unit,
  'pets': Icons.pets,
  'precision_manufacturing': Icons.precision_manufacturing,
  'grass': Icons.grass,
  'factory': Icons.factory,
  'outdoors': Icons.outdoor_grill,
  'coronavirus': Icons.coronavirus,
  'nightlight': Icons.nightlight,
  'warning': Icons.warning_amber_rounded,
  'hardware': Icons.handyman,
  'sailing': Icons.sailing,
  'military_tech': Icons.military_tech,
  'sports_esports': Icons.sports_esports,
  'sports_esports_outlined': Icons.sports_esports_outlined,
  'videogame_asset': Icons.videogame_asset,
  'extension': Icons.extension,
};

const _kDefaultGameIcon = Icons.sports_esports_outlined;

IconData resolveGameIcon(String name) =>
    _kGameIconMap[name.trim()] ?? _kDefaultGameIcon;

/// `icon_asset` / `grid_asset`：
/// - 绝对 URL (http/https) → CachedNetworkImage（带磁盘缓存）
/// - `assets/` 开头 → Image.asset（打包资源）
/// - 其他（纯相对路径，如 `games/minecraft/icon.png`）→ **HYBRID**：
///     先尝试本地打包资源（自动加 `assets/` 前缀），
///     失败再走 `kAstralGameMediaBaseUrl + path` 的远程 CDN（带磁盘缓存）。
///   这样线上/线下 JSON 路径完全一致，同时离线兜底也能用本地包。
enum GameMediaKind { asset, network, hybrid }

class GameMediaRef {
  const GameMediaRef.asset(this.path) : kind = GameMediaKind.asset, url = null;
  const GameMediaRef.network(this.url)
    : kind = GameMediaKind.network,
      path = null;

  /// hybrid：同时持有本地 asset 路径 + 远程 URL，按顺序尝试。
  const GameMediaRef.hybrid({required this.path, required this.url})
    : kind = GameMediaKind.hybrid;

  final GameMediaKind kind;

  /// asset 路径（或 hybrid 的本地 asset 路径，带 assets/ 前缀）。
  final String? path;

  /// 完整 URL（network / hybrid 的远程地址）。
  final String? url;

  /// 将纯相对路径解析为「本地 asset 路径」和「远程 URL」。
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
    // 纯相对路径 → hybrid：
    //   本地试 assets/<path>；远端试 <baseUrl>/<path>
    final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    final resolved = s.startsWith('/')
        ? base.replace(path: s)
        : base.resolve(s);
    return GameMediaRef.hybrid(path: 'assets/$s', url: resolved.toString());
  }
}

/// 按 [GameMediaRef] 渲染图片：
/// - asset：打包资源，最快
/// - hybrid：先 asset 失败再走 network（带磁盘缓存）
/// - network：CachedNetworkImage（带磁盘缓存，关闭 app 后还在）
class GameMediaImage extends StatelessWidget {
  const GameMediaImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.placeholder,
  });

  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// 网络加载中的占位 Widget（可选，默认是空白）。
  final WidgetBuilder? placeholder;

  @override
  Widget build(BuildContext context) {
    final ref = GameMediaRef.tryParse(source);
    if (ref == null) {
      return errorBuilder?.call(context, 'empty media', StackTrace.empty) ??
          const SizedBox.shrink();
    }
    switch (ref.kind) {
      case GameMediaKind.asset:
        return Image.asset(
          ref.path!,
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: errorBuilder,
        );
      case GameMediaKind.network:
        return _cachedNetwork(url: ref.url!, errorBuilder: errorBuilder);
      case GameMediaKind.hybrid:
        // 优先本地打包 asset；加载失败再走带缓存的远程 CDN。
        return Image.asset(
          ref.path!,
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return _cachedNetwork(
              url: ref.url!,
              errorBuilder: (c, e, s) =>
                  errorBuilder?.call(c, e, s) ?? const SizedBox.shrink(),
            );
          },
        );
    }
  }

  Widget _cachedNetwork({
    required String url,
    ImageErrorWidgetBuilder? errorBuilder,
  }) {
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      placeholder: placeholder != null
          ? (context, _) => placeholder!(context)
          : null,
      errorWidget: errorBuilder != null
          ? (context, u, e) => errorBuilder(context, e, StackTrace.empty)
          : (context, u, e) => const SizedBox.shrink(),
    );
  }
}

/// 游戏方形 Logo：
/// - 用 resolvedIconAsset（优先 JSON 写的 icon_asset，否则自动推断 `games/{id}/icon.png`）
/// - GameMediaImage 会：先试本地 asset → 失败走远程 CDN（磁盘缓存）→ 再失败回退色块
class GameLogo extends StatelessWidget {
  const GameLogo({super.key, required this.game, this.size = 40});

  final GameInfo game;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.22);
    return ClipRRect(
      borderRadius: radius,
      child: GameMediaImage(
        source: game.resolvedIconAsset,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) => _fallback(radius),
      ),
    );
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: GameMediaImage(
        source: game.resolvedGridAsset,
        width: width,
        height: height,
        errorBuilder: (context, error, stackTrace) => SizedBox(
          width: width,
          height: height,
          child: GameLogo(game: game, size: width.clamp(40, height)),
        ),
      ),
    );
  }
}
