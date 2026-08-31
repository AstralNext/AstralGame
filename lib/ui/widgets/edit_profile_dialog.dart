import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/app_snack_bar.dart';
import 'package:astral_game/ui/widgets/avatar_widget.dart';
import 'package:astral_game/utils/image_picker_helper.dart';
import 'package:flutter/material.dart';

/// 全局编辑资料弹窗（侧栏 / 顶栏头像共用）。
Future<void> showEditProfileDialog(BuildContext context) async {
  final nodes = getIt<NodeManagementService>();
  final nameController = TextEditingController(
    text: nodes.currentUsername.value,
  );
  var avatar = nodes.currentUserAvatar.value;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('编辑资料'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final bytes =
                        await ImagePickerHelper.pickImageFromGallery();
                    if (bytes == null) return;
                    setState(() => avatar = bytes);
                  },
                  child: AvatarWidget(avatar: avatar, size: 72),
                ),
                const SizedBox(height: 20),
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
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isNotEmpty) {
                    await nodes.updateCurrentUsername(name);
                  }
                  await nodes.updateCurrentUserAvatar(avatar);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == true && context.mounted) {
    showAppSnackBar(context, '资料已更新');
  }
}
