import 'dart:typed_data';

import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/app_toast.dart';
import 'package:astral_game/ui/widgets/avatar_widget.dart';
import 'package:astral_game/utils/image_picker_helper.dart';
import 'package:flutter/material.dart';

/// 全局资料弹窗（侧栏 / 顶栏头像共用）。
///
/// [onboarding] 为 true 时用于首次启动引导：遮罩不可点关闭，
/// 提供「稍后再说」，无论保存还是跳过都会写入已引导标记。
Future<void> showEditProfileDialog(
  BuildContext context, {
  bool onboarding = false,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: !onboarding,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (_) => _ProfileDialog(onboarding: onboarding),
  );

  if (saved == true && context.mounted) {
    showAppToast(context, '资料已更新');
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.onboarding});

  final bool onboarding;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _nameController;
  Uint8List? _avatar;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final nodes = getIt<NodeManagementService>();
    _nameController = TextEditingController(text: nodes.currentUsername.value);
    _avatar = nodes.currentUserAvatar.value;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final bytes = await ImagePickerHelper.pickImageFromGallery();
    if (bytes == null || !mounted) return;
    setState(() => _avatar = bytes);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showAppToast(context, '请输入昵称');
      return;
    }

    setState(() => _saving = true);
    final nodes = getIt<NodeManagementService>();
    if (name != nodes.currentUsername.value) {
      await nodes.updateCurrentUsername(name);
    }
    await nodes.updateCurrentUserAvatar(_avatar);
    await getIt<AppSettingsService>().markProfileSetupDone();
    if (mounted) Navigator.pop(context, true);
  }

  /// 引导态为「稍后再说」，普通态为「取消」。
  Future<void> _dismiss() async {
    if (_saving) return;
    if (widget.onboarding) {
      await getIt<AppSettingsService>().markProfileSetupDone();
    }
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final onboarding = widget.onboarding;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: palette.shadowLift,
                blurRadius: 48,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AvatarWidget(
                        avatar: _avatar,
                        size: 92,
                        showBorder: false,
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: palette.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: palette.card, width: 3),
                          ),
                          child: Icon(
                            Icons.camera_alt_rounded,
                            size: 16,
                            color: palette.onAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  onboarding ? '完善你的资料' : '编辑资料',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  onboarding ? '昵称会显示给同一房间的玩家\n点击头像可立即更换' : '昵称会显示给同一房间的玩家',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 26),
                Container(
                  decoration: BoxDecoration(
                    color: palette.canvas.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _nameController,
                    autofocus: onboarding,
                    textAlign: TextAlign.center,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    maxLength: 16,
                    style: textTheme.bodyLarge?.copyWith(
                      color: palette.textPrimary,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hintText: '输入昵称',
                      hintStyle: textTheme.bodyLarge?.copyWith(
                        color: palette.textTertiary,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.onAccent,
                      disabledBackgroundColor: palette.accent.withValues(
                        alpha: 0.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: _saving
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.onAccent,
                            ),
                          )
                        : Text(onboarding ? '开始使用' : '保存'),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _saving ? null : _dismiss,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.textSecondary,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(onboarding ? '稍后再说' : '取消'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
