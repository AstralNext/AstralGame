import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:get_it/get_it.dart';
import 'package:signals/signals_flutter.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/ui/pages/dashboard_wide_layout.dart';
import 'package:astral_game/ui/pages/dashboard_narrow_layout.dart';
import 'package:astral_game/ui/widgets/avatar_widget.dart';
import 'package:astral_game/utils/image_picker_helper.dart';
import 'package:astral_game/utils/room_share.dart';

/// 仪表盘页面
///
/// 显示网络状态、在线用户和房间历史
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final NodeManagementService _nodeManagement = GetIt.I<NodeManagementService>();
  final ConnectionService _connectionService = GetIt.I<ConnectionService>();
  final ScreenStateService _screenStateService = GetIt.I<ScreenStateService>();
  final RoomState _roomState = getIt<RoomState>();

  /// 处理设置按钮点击
  void _handleSettings() {
    _showEditProfileDialog();
  }

  Future<void> _showEditProfileDialog() async {
    if (!mounted) return;

    final nameController = TextEditingController(
      text: _nodeManagement.currentUsername.value,
    );
    var avatar = _nodeManagement.currentUserAvatar.value;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('编辑资料'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final bytes = await ImagePickerHelper.pickImageFromGallery();
                      if (bytes == null) return;
                      setState(() => avatar = bytes);
                    },
                    child: AvatarWidget(
                      avatar: avatar,
                      size: 72,
                      shape: AvatarShape.circle,
                      borderWidth: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      hintText: '请输入昵称',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () async {
                    await _nodeManagement.updateCurrentUserAvatar(null);
                    if (mounted) Navigator.pop(context, true);
                  },
                  child: const Text('清除头像'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isNotEmpty) {
                      await _nodeManagement.updateCurrentUsername(name);
                    }
                    await _nodeManagement.updateCurrentUserAvatar(avatar);
                    if (mounted) Navigator.pop(context, true);
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资料已更新')),
      );
    }
  }

  /// 处理分享房间
  Future<void> _handleShareRoom() async {
    final code = _roomState.activeShareCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: roomShareCodeForClipboard(code)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('房间分享码已复制')),
      );
    }
  }

  /// 处理断开连接
  Future<void> _handleDisconnect() async {
    await _connectionService.disconnect();
  }

  /// 处理创建房间
  Future<void> _handleCreateRoom() async {
    if (_connectionService.isConnecting) return;

    final TextEditingController nameController = TextEditingController();

    final roomName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建房间'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '房间名（必填）',
            hintText: '例如：周五开黑 / 1号桌',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = nameController.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            child: const Text('创建并连接'),
          ),
        ],
      ),
    );

    if (roomName == null || roomName.trim().isEmpty) return;

    final room = await _connectionService.createRoom(roomName: roomName.trim());

    final success = await _connectionService.connectToRoom(room.roomName, room.password);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接失败，请重试')),
      );
    }
  }

  /// 处理加入房间
  Future<void> _handleJoinRoom() async {
    if (_connectionService.isConnecting) return;

    final TextEditingController uuidController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('加入房间'),
        content: TextField(
          controller: uuidController,
          decoration: const InputDecoration(
            labelText: '房间分享码',
            hintText: '例如：随机码_房间名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (uuidController.text.isNotEmpty) {
                Navigator.pop(context, uuidController.text.trim());
              }
            },
            child: const Text('加入'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        final room = await _connectionService.joinRoom(result);

        final success =
            await _connectionService.connectToRoom(room.roomName, room.password);
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('连接失败，请重试')),
          );
        }
      } on FormatException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      }
    }
  }

  /// 处理从历史记录加入房间
  void _handleJoinHistory(String shareCode) async {
    if (shareCode.isEmpty || _connectionService.isConnecting) return;

    final index = _roomState.rooms.indexWhere((r) => r.shareCode == shareCode);
    if (index != -1) {
      final room = _roomState.rooms[index];

      final success = await _connectionService.connectToRoom(room.roomName, room.password);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接失败，请重试')),
        );
      }
    }
  }

  /// 处理移除房间
  void _handleRemoveRoom(RoomMod room) {
    _connectionService.removeRoom(room.id);
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final isNarrow = _screenStateService.isNarrow;

      return isNarrow
          ? DashboardNarrowLayout(
              nodeManagement: _nodeManagement,
              connectionService: _connectionService,
              roomState: _roomState,
              onSettings: _handleSettings,
              onCreateRoom: _handleCreateRoom,
              onJoinRoom: _handleJoinRoom,
              onShareRoom: _handleShareRoom,
              onDisconnect: _handleDisconnect,
              onRemoveRoom: _handleRemoveRoom,
              onJoinHistory: _handleJoinHistory,
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: DashboardWideLayout(
                nodeManagement: _nodeManagement,
                connectionService: _connectionService,
                screenStateService: _screenStateService,
                roomState: _roomState,
                onSettings: _handleSettings,
                onCreateRoom: _handleCreateRoom,
                onJoinRoom: _handleJoinRoom,
                onShareRoom: _handleShareRoom,
                onDisconnect: _handleDisconnect,
                onJoinHistory: _handleJoinHistory,
              ),
            );
    });
  }
}
