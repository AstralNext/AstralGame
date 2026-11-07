import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:flutter/material.dart';

/// 建房结果：游戏 + Steam 门槛设置（非 Steam 模式下门槛字段不生效）。
typedef CreateRoomResult = ({
  GameInfo game,
  String gate,
  String? extraPassword,
});

/// 创建房间：大弹窗列表。选中游戏后返回；取消返回 null。
Future<CreateRoomResult?> showCreateRoomDialog(
  BuildContext context, {
  required List<GameInfo> catalog,
  required void Function(String searchedName) onRequestAdapt,
  bool steamMode = false,
}) {
  return showDialog<CreateRoomResult>(
    context: context,
    barrierColor: astralDialogBarrierColor,
    builder: (context) => _CreateRoomDialog(
      catalog: catalog,
      onRequestAdapt: onRequestAdapt,
      steamMode: steamMode,
    ),
  );
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog({
    required this.catalog,
    required this.onRequestAdapt,
    this.steamMode = false,
  });

  final List<GameInfo> catalog;
  final void Function(String searchedName) onRequestAdapt;
  final bool steamMode;

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  late GameInfo _selected;
  final _searchController = TextEditingController();
  final _passwordController = TextEditingController();
  var _query = '';

  /// Steam 门槛：默认基础口令，禁止无门槛。
  var _gate = kSteamLobbyGateBasic;
  String? _gateError;

  @override
  void initState() {
    super.initState();
    _selected = widget.catalog.first;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 全公开必须显式二次确认；其余门槛直接返回。
  Future<void> _submit() async {
    final gate = _gate;
    String? extra;
    if (gate == kSteamLobbyGateDouble) {
      extra = _passwordController.text.trim();
      if (extra.isEmpty) {
        setState(() => _gateError = '额外密码不能为空');
        return;
      }
    }
    if (gate == kSteamLobbyGateOpen) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierColor: astralDialogBarrierColor,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认完全公开？'),
          content: const Text(
            '完全公开的房间不需要任何密码，任何正在搜索该游戏的人都可能进来。'
            '如果你只是和朋友联机，请改用「基础口令」或「额外密码」。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('返回修改'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('仍然完全公开'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    Navigator.pop(context, (
      game: _selected,
      gate: gate,
      extraPassword: extra,
    ));
  }

  List<GameInfo> _filtered() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.catalog;
    return widget.catalog
        .where(
          (g) =>
              g.name.toLowerCase().contains(q) ||
              g.nameZh.toLowerCase().contains(q) ||
              g.id.toLowerCase().contains(q) ||
              g.description.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  void _applyQuery(String v) {
    setState(() {
      _query = v;
      final list = _filtered();
      if (list.isNotEmpty && !list.any((g) => g.id == _selected.id)) {
        _selected = list.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final filtered = _filtered();
    final selectionValid = filtered.any((g) => g.id == _selected.id);
    final maxW = size.width < 560 ? size.width - 32 : 520.0;
    final maxH = size.height * 0.82;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.space16,
        vertical: AppDimensions.space20,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: maxW,
        height: maxH.clamp(420.0, 720.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.space20,
                AppDimensions.space16,
                AppDimensions.space12,
                AppDimensions.space8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '创建房间',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.space20,
                0,
                AppDimensions.space20,
                AppDimensions.space8,
              ),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '搜索游戏',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: _applyQuery,
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '没有匹配的游戏',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                widget.onRequestAdapt(_searchController.text),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('请求适配'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppDimensions.space8,
                        AppDimensions.space4,
                        AppDimensions.space8,
                        AppDimensions.space8,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final g = filtered[index];
                        return _GameListTile(
                          game: g,
                          selected: g.id == _selected.id,
                          onTap: () => setState(() => _selected = g),
                        );
                      },
                    ),
            ),
            if (widget.steamMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.space20,
                  AppDimensions.space4,
                  AppDimensions.space20,
                  AppDimensions.space8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '房间门槛',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: kSteamLobbyGateBasic,
                          label: Text('基础口令'),
                          icon: Icon(Icons.lock_outline, size: 16),
                        ),
                        ButtonSegment(
                          value: kSteamLobbyGateDouble,
                          label: Text('额外密码'),
                          icon: Icon(Icons.key, size: 16),
                        ),
                        ButtonSegment(
                          value: kSteamLobbyGateOpen,
                          label: Text('完全公开'),
                          icon: Icon(Icons.public, size: 16),
                        ),
                      ],
                      selected: {_gate},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => setState(() {
                        _gate = v.first;
                        _gateError = null;
                      }),
                    ),
                    const SizedBox(height: 8),
                    if (_gate == kSteamLobbyGateDouble)
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: '额外密码',
                          hintText: '告诉好友的密码',
                          errorText: _gateError,
                          isDense: true,
                        ),
                        onChanged: (_) {
                          if (_gateError != null) {
                            setState(() => _gateError = null);
                          }
                        },
                      )
                    else
                      Text(
                        _gate == kSteamLobbyGateOpen
                            ? '完全公开需要二次确认：任何搜到该游戏房间的人都能直接加入。'
                            : '使用全工具统一基础口令，好友搜索该游戏即可加入。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.space16,
                AppDimensions.space8,
                AppDimensions.space16,
                AppDimensions.space16,
              ),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: !selectionValid ? null : _submit,
                    child: const Text('创建并连接'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameListTile extends StatelessWidget {
  const _GameListTile({
    required this.game,
    required this.selected,
    required this.onTap,
  });

  final GameInfo game;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final desc = game.description.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.space4,
        vertical: AppDimensions.space2,
      ),
      child: Material(
        color: selected
            ? palette.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppDimensions.radiusXs),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimensions.radiusXs),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.space12,
              vertical: AppDimensions.space8,
            ),
            child: Row(
              children: [
                GameLogo(game: game),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 20, color: palette.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
