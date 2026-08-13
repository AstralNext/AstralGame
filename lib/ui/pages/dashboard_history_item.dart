import 'package:astral_game/config/constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/grouped_tile_shape.dart';
import 'package:astral_game/utils/room_display.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:astral_game/utils/room_share_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DashboardDismissibleHistoryItem extends StatefulWidget {
  const DashboardDismissibleHistoryItem({
    super.key,
    required this.room,
    required this.onJoin,
    required this.onRemove,
    this.grouped = false,
    this.index = 0,
    this.count = 1,
  });

  final RoomMod room;
  final VoidCallback onJoin;
  final void Function(RoomMod) onRemove;
  final bool grouped;
  final int index;
  final int count;

  @override
  State<DashboardDismissibleHistoryItem> createState() =>
      _DashboardDismissibleHistoryItemState();
}

class _DashboardDismissibleHistoryItemState
    extends State<DashboardDismissibleHistoryItem> {
  Future<void> _shareRoom(BuildContext context) async {
    final url = joinShareUrlFromCode(widget.room.shareCode);
    if (url.isEmpty) return;
    HapticFeedback.mediumImpact();
    await shareJoinInvite(
      context: context,
      url: url,
      gameName: widget.room.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final borderRadius = widget.grouped
        ? groupedTileBorderRadius(index: widget.index, count: widget.count)
        : AppRadius.brMedium;

    final row = Material(
      color: Colors.transparent,
      shape: widget.grouped
          ? groupedTileShape(index: widget.index, count: widget.count)
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.room.shareCode.isNotEmpty ? widget.onJoin : null,
        onLongPress:
            widget.room.shareCode.isNotEmpty ? () => _shareRoom(context) : null,
        borderRadius: borderRadius,
        splashColor: palette.accentMuted,
        highlightColor: palette.accent.withValues(alpha: 0.08),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.grouped ? 12 : 10,
            12,
            widget.grouped ? 12 : 10,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.accentMutedStrong,
                  borderRadius: AppRadius.brSmall,
                ),
                child: Icon(
                  Icons.meeting_room_outlined,
                  color: palette.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomDisplayLabel(widget.room),
                      style: textTheme.titleMedium?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      historyItemSubtitle(widget.room),
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.textTertiary.withValues(alpha: 0.65),
              ),
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: Key(widget.room.shareCode),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: palette.error,
          borderRadius: borderRadius,
        ),
        child: Icon(Icons.delete_outlined, color: palette.onError, size: 22),
      ),
      onDismissed: (_) => widget.onRemove(widget.room),
      child: row,
    );
  }
}

class DashboardHistoryItem extends StatefulWidget {
  const DashboardHistoryItem({
    super.key,
    required this.room,
    required this.onJoin,
    this.grouped = false,
    this.index = 0,
    this.count = 1,
  });

  final RoomMod room;
  final VoidCallback onJoin;
  final bool grouped;
  final int index;
  final int count;

  @override
  State<DashboardHistoryItem> createState() => _DashboardHistoryItemState();
}

class _DashboardHistoryItemState extends State<DashboardHistoryItem> {
  bool isHovered = false;
  final _roomState = getIt<RoomState>();

  Future<void> _shareRoom(BuildContext context) async {
    final url = joinShareUrlFromCode(widget.room.shareCode);
    if (url.isEmpty) return;
    HapticFeedback.mediumImpact();
    await shareJoinInvite(
      context: context,
      url: url,
      gameName: widget.room.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final borderRadius = widget.grouped
        ? groupedTileBorderRadius(index: widget.index, count: widget.count)
        : AppRadius.brMedium;

    final row = Material(
      color: Colors.transparent,
      shape: widget.grouped
          ? groupedTileShape(index: widget.index, count: widget.count)
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.room.shareCode.isNotEmpty ? widget.onJoin : null,
        onLongPress:
            widget.room.shareCode.isNotEmpty ? () => _shareRoom(context) : null,
        borderRadius: borderRadius,
        splashColor: palette.accentMuted,
        highlightColor: palette.accent.withValues(alpha: 0.08),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.grouped ? 12 : 10,
            12,
            widget.grouped ? 12 : 10,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.accentMutedStrong,
                  borderRadius: AppRadius.brSmall,
                ),
                child: Icon(
                  Icons.meeting_room_outlined,
                  color: palette.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomDisplayLabel(widget.room),
                      style: textTheme.titleMedium?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      historyItemSubtitle(widget.room),
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (!widget.grouped)
                AnimatedOpacity(
                  opacity: isHovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.copy_outlined,
                          size: 18,
                          color: palette.textSecondary,
                        ),
                        onPressed: widget.room.shareCode.isNotEmpty
                            ? () async {
                                final url = joinShareUrlFromCode(
                                  widget.room.shareCode,
                                );
                                if (url.isEmpty) return;
                                await Clipboard.setData(
                                  ClipboardData(text: url),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('邀请链接已复制'),
                                    ),
                                  );
                                }
                              }
                            : null,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outlined,
                          size: 18,
                          color: palette.error,
                        ),
                        onPressed: () => _roomState.removeRoom(widget.room.id),
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.textTertiary.withValues(alpha: 0.65),
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.grouped) return row;

    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: row,
      ),
    );
  }
}
