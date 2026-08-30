import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:flutter/material.dart';

/// 创建房间：大弹窗列表。选中游戏后返回；取消返回 null。
Future<GameInfo?> showCreateRoomDialog(
  BuildContext context, {
  required List<GameInfo> catalog,
  required void Function(String searchedName) onRequestAdapt,
}) {
  return showDialog<GameInfo>(
    context: context,
    builder: (context) =>
        _CreateRoomDialog(catalog: catalog, onRequestAdapt: onRequestAdapt),
  );
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog({
    required this.catalog,
    required this.onRequestAdapt,
  });

  final List<GameInfo> catalog;
  final void Function(String searchedName) onRequestAdapt;

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  late GameInfo _selected;
  final _searchController = TextEditingController();
  var _query = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.catalog.first;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: maxW,
        height: maxH.clamp(420.0, 720.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: !selectionValid
                        ? null
                        : () => Navigator.pop(context, _selected),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: selected
            ? palette.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
