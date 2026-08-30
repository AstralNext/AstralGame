import 'dart:async';

import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/join_link_service.dart';
import 'package:astral_game/data/services/share_code_service.dart';
import 'package:astral_game/data/services/shell_navigation_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 收到邀请链接后自动进房（支持短码/离线串/本地收藏）。
class JoinLinkBinder extends StatefulWidget {
  const JoinLinkBinder({super.key, required this.child});

  final Widget child;

  @override
  State<JoinLinkBinder> createState() => _JoinLinkBinderState();
}

class _JoinLinkBinderState extends State<JoinLinkBinder> {
  EffectCleanup? _cleanup;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(getIt<JoinLinkService>().start());
      _cleanup = effect(() {
        final token = getIt<JoinLinkService>().pendingToken.value;
        if (token == null || token.isEmpty) return;
        unawaited(_handle(token));
      });
    });
  }

  @override
  void dispose() {
    _cleanup?.call();
    super.dispose();
  }

  Future<void> _handle(String token) async {
    if (_busy) return;
    _busy = true;
    final links = getIt<JoinLinkService>();
    links.consume();
    try {
      final connection = getIt<ConnectionService>();
      final room = getIt<RoomState>();
      if (connection.isConnecting || connection.isLinking.value) {
        _toast('正在连接中，请稍后再打开邀请链接');
        return;
      }
      if (room.session.value != null) {
        final go = await _confirmLeave();
        if (go != true) return;
        await connection.leaveRoom();
      }
      getIt<ShellNavigationService>().openDashboardTab();

      // 识别 bookmark: 前缀 → 从本地收藏找 payload 直接加入
      final bmId = extractBookmarkId(token);
      if (bmId != null) {
        final bookmark = _findBookmarkById(room, bmId);
        if (bookmark == null) {
          _toast('本地未找到对应收藏（id=$bmId），可能已被删除');
          return;
        }
        _toast('正在通过收藏加入：${bookmark.displayName}');
        await connection.joinWithPayload(bookmark.payload);
        return;
      }

      _toast('正在通过链接加入…');
      await connection.joinWithInviteInput(token);
    } on ConnectionAbortedException {
      return;
    } on ShareCodeException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      _busy = false;
    }
  }

  Bookmark? _findBookmarkById(RoomState room, int id) {
    for (final b in room.bookmarksList.value) {
      if (b.id == id) return b;
    }
    return null;
  }

  Future<bool?> _confirmLeave() {
    final ctx = context;
    if (!ctx.mounted) return Future.value(false);
    return showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('加入新房间'),
        content: const Text('当前已在房间内。离开并加入链接里的房间？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('离开并加入'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    final ctx = context;
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
