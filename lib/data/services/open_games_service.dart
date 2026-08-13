import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/open_game_listing.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/lan_game_discoverers.dart';
import 'package:astral_game/data/services/lan_local_relay.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_client.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_router.dart';
import 'package:astral_game/utils/lan_title_template.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:signals/signals_core.dart';

/// 局域网游戏发现 + 经 EasyTier peer-RPC 向房间同步「开放游戏」列表。
///
/// 发现方式由 [LanGameDiscovererRegistry] 按 JSON `type` 分发，与 ET 宣告解耦。
class OpenGamesService {
  OpenGamesService(
    this._rules,
    this._nodes,
    this._rpc,
    this._router,
    this._settings,
  );

  final GameAssistRulesService _rules;
  final NodeManagementService _nodes;
  final PeerRpcClient _rpc;
  final PeerRpcRouter _router;
  final AppSettingsService _settings;

  final listings = signal<List<OpenGameListing>>(const []);
  final LanLocalRelay _localRelay = LanLocalRelay();

  /// 通道目标在本机的 127 转发 / 组播注入状态（UI 绿点）。
  late final relayStatuses = _localRelay.statuses;

  String? _roomGameId;
  bool _isHost = false;
  GameAssistLanGameDiscoverConfig? _config;
  Timer? _tick;
  EffectCleanup? _nodesEffect;
  final Set<int> _pulledPeers = {};
  bool _listening = false;
  List<LocalOpenGameAd> _lastLocalAds = const [];
  String _roomGameName = '';

  bool get isActive => _roomGameId != null;
  String? get roomGameId => _roomGameId;

  List<Map<String, dynamic>> localAdsWire() {
    return _lastLocalAds.map((e) => e.toWire()).toList(growable: false);
  }

  Future<void> startForRoom({
    required String gameId,
    required bool isHost,
  }) async {
    await stop();
    await _rules.ensureLoaded();
    final game = await _rules.gameRules(gameId);
    final cfg = game?.lanGameDiscoverFor(GameAssistRulesService.platformKey);
    if (cfg == null || !cfg.enabled || cfg.entries.isEmpty) {
      appLogger.d('[OpenGames] 未启用 lan_game_discover game=$gameId');
      return;
    }
    if (cfg.hostOnly && !isHost) {
      appLogger.d('[OpenGames] host_only：本机不宣告，仍接收列表');
    }

    _roomGameId = gameId;
    _isHost = isHost;
    _config = cfg;
    _roomGameName = (game?.name.trim().isNotEmpty == true)
        ? game!.name.trim()
        : gameId;
    _ensureNotifyListener();

    if (Platform.isWindows) {
      await LanGameDiscovererRegistry.instance.startAll(cfg.entries);
    }

    _nodesEffect = effect(() {
      final nodes = _nodes.userNodes.value;
      unawaited(_onNodesChanged(nodes));
    });

    final interval = Duration(milliseconds: cfg.intervalMs.clamp(2000, 60000));
    _tick = Timer.periodic(interval, (_) => unawaited(_tickOnce()));
    await _tickOnce();
    appLogger.i(
      '[OpenGames] 已启动 game=$gameId host=$isHost '
      'entries=${cfg.entries.length} types='
      '${cfg.entries.map((e) => e.type).toSet().join(",")}',
    );
  }

  Future<void> stop() async {
    _tick?.cancel();
    _tick = null;
    _nodesEffect?.call();
    _nodesEffect = null;
    _pulledPeers.clear();
    _roomGameId = null;
    _config = null;
    _isHost = false;
    _lastLocalAds = const [];
    listings.value = const [];
    _roomGameName = '';
    await _syncLocalRelay();
    await LanGameDiscovererRegistry.instance.stopAll();
  }

  void _ensureNotifyListener() {
    if (_listening) return;
    _listening = true;
    _router.addNotificationListener(_onNotify);
  }

  void _onNotify(String channel, dynamic params, int fromPeerId) {
    if (channel != 'game.advertiseOpen') return;
    if (_roomGameId == null) return;
    _ingestAds(
      fromPeerId: fromPeerId,
      params: params,
      ownerName: _ownerNameForPeer(fromPeerId),
    );
  }

  Future<void> _onNodesChanged(List<EnhancedNodeInfo> nodes) async {
    if (_roomGameId == null || !_rpc.isBound) return;
    for (final n in nodes) {
      if (n.peerId <= 0) continue;
      if (_pulledPeers.contains(n.peerId)) continue;
      _pulledPeers.add(n.peerId);
      try {
        final res = await _rpc.call(n.peerId, 'game.listOpen');
        _ingestAds(
          fromPeerId: n.peerId,
          params: res,
          ownerName: n.displayName,
        );
      } catch (e) {
        appLogger.d('[OpenGames] listOpen peer=${n.peerId} 失败: $e');
      }
    }
  }

  Future<void> _tickOnce() async {
    _pruneExpired();
    final cfg = _config;
    final gameId = _roomGameId;
    if (cfg == null || gameId == null) return;

    final shouldAnnounce = !cfg.hostOnly || _isHost;
    final ads = shouldAnnounce
        ? await _buildLocalAdsAsync()
        : const <LocalOpenGameAd>[];
    _lastLocalAds = ads;

    final myName = _settings.getUsername().trim().isEmpty
        ? '我'
        : _settings.getUsername().trim();
    final selfListings = [
      for (final ad in ads)
        OpenGameListing(
          key: 'self:${ad.entry.id}:${ad.port}',
          fromPeerId: 0,
          ownerName: myName,
          roomGameId: gameId,
          adId: '${ad.entry.id}:${ad.port}',
          label: ad.label,
          ipv4: ad.ipv4,
          port: ad.port,
          motd: ad.motd,
          expiresAt: DateTime.now().add(
            Duration(milliseconds: cfg.ttlMs.clamp(3000, 120000)),
          ),
          isSelf: true,
          isRoomHost: _isHost,
        ),
    ];
    _replaceSelfListings(selfListings);

    if (!_rpc.isBound) return;
    final payload = {
      'gameId': gameId,
      'ads': ads.map((e) => e.toWire()).toList(),
    };
    final peers = _nodes.userNodes.value;
    for (final n in peers) {
      if (n.peerId <= 0) continue;
      try {
        await _rpc.notify(n.peerId, 'game.advertiseOpen', params: payload);
      } catch (e) {
        appLogger.d('[OpenGames] advertise → ${n.peerId} 失败: $e');
      }
    }
  }

  Future<List<LocalOpenGameAd>> _buildLocalAdsAsync() async {
    final cfg = _config;
    final gameId = _roomGameId;
    if (cfg == null || gameId == null) return const [];
    final ip = stripIpv4Host(_nodes.myVirtualIpv4.value);
    if (ip == null) return const [];
    final raw = await LanGameDiscovererRegistry.instance.collectAds(
      entries: cfg.entries,
      roomGameId: gameId,
      virtualIp: ip,
    );
    final player = _settings.getUsername().trim();
    return [
      for (final ad in raw) _rewriteLocalAdTitle(ad, player: player),
    ];
  }

  LocalOpenGameAd _rewriteLocalAdTitle(
    LocalOpenGameAd ad, {
    required String player,
  }) {
    final template = ad.entry.paramString('title_template');
    if (template == null) return ad;
    final title = applyLanTitleTemplate(
      template,
      player: player.isEmpty ? 'Player' : player,
      game: _roomGameName.isEmpty ? ad.entry.label : _roomGameName,
      label: ad.label,
      motd: ad.motd ?? '',
    );
    if (title.isEmpty) return ad;
    return LocalOpenGameAd(
      entry: ad.entry,
      ipv4: ad.ipv4,
      roomGameId: ad.roomGameId,
      port: ad.port,
      label: title,
      motd: title,
    );
  }

  Future<void> _syncLocalRelay() async {
    final cfg = _config;
    final remotes = cfg == null
        ? const <OpenGameListing>[]
        : listings.value.where((e) => !e.isSelf && !e.isExpired).toList();
    try {
      if (cfg == null || remotes.isEmpty) {
        await _localRelay.stop();
        return;
      }
      await _localRelay.sync(remotes: remotes, entries: cfg.entries);
    } catch (e) {
      appLogger.d('[OpenGames] 本机注入同步失败: $e');
    }
  }

  void _ingestAds({
    required int fromPeerId,
    required dynamic params,
    required String ownerName,
  }) {
    final cfg = _config;
    final roomGameId = _roomGameId;
    if (cfg == null || roomGameId == null) return;
    if (params is! Map) return;
    final map = Map<String, dynamic>.from(params);
    final remoteGame = '${map['gameId'] ?? ''}'.trim();
    if (remoteGame.isNotEmpty && remoteGame != roomGameId) return;

    final rawAds = map['ads'];
    final list = <Map<String, dynamic>>[];
    if (rawAds is List) {
      for (final e in rawAds) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    } else if (map.containsKey('adId') || map.containsKey('port')) {
      list.add(map);
    }
    if (list.isEmpty) {
      _clearPeerListings(fromPeerId);
      return;
    }

    const isHostPeer = false;

    final parsed = <OpenGameListing>[];
    for (final raw in list) {
      final item = OpenGameListing.fromWire(
        fromPeerId: fromPeerId,
        ownerName: ownerName,
        raw: raw,
        ttlMs: cfg.ttlMs,
        isSelf: false,
        isRoomHost: isHostPeer,
      );
      if (item == null) continue;
      if (item.roomGameId.isNotEmpty && item.roomGameId != roomGameId) continue;
      parsed.add(
        item.roomGameId.isEmpty
            ? OpenGameListing(
                key: item.key,
                fromPeerId: item.fromPeerId,
                ownerName: item.ownerName,
                roomGameId: roomGameId,
                adId: item.adId,
                label: item.label,
                ipv4: item.ipv4,
                port: item.port,
                motd: item.motd,
                expiresAt: item.expiresAt,
                isSelf: false,
                isRoomHost: item.isRoomHost,
              )
            : item,
      );
    }
    _replacePeerListings(fromPeerId, parsed);
  }

  /// 用本机最新探测结果整表替换 self 条目（空则立即消失）。
  void _replaceSelfListings(List<OpenGameListing> selfAds) {
    _setListings(_sorted([
      ...listings.value.where((e) => !e.isSelf),
      ...selfAds,
    ]));
  }

  void _clearPeerListings(int peerId) {
    final next = listings.value.where((e) => e.fromPeerId != peerId).toList();
    if (next.length != listings.value.length) {
      _setListings(_sorted(next));
    }
  }

  void _replacePeerListings(int peerId, List<OpenGameListing> incoming) {
    _setListings(_sorted([
      ...listings.value.where((e) => e.fromPeerId != peerId),
      ...incoming.where((e) => !e.isExpired),
    ]));
  }

  void _pruneExpired() {
    final next = listings.value.where((e) => !e.isExpired).toList();
    if (next.length != listings.value.length) {
      _setListings(_sorted(next));
    }
  }

  /// 开放游戏列表是唯一真相：出现 → 开组播/转发；消失/退房 → 立刻关。
  void _setListings(List<OpenGameListing> next) {
    listings.value = next;
    unawaited(_syncLocalRelay());
  }

  List<OpenGameListing> _sorted(Iterable<OpenGameListing> items) {
    final list = items.toList();
    list.sort((a, b) {
      if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
      if (a.isRoomHost != b.isRoomHost) return a.isRoomHost ? -1 : 1;
      final c = a.label.compareTo(b.label);
      if (c != 0) return c;
      return a.endpoint.compareTo(b.endpoint);
    });
    return list;
  }

  String _ownerNameForPeer(int peerId) {
    for (final n in _nodes.userNodes.value) {
      if (n.peerId == peerId) return n.displayName;
    }
    return 'Peer $peerId';
  }
}
