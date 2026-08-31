import 'package:astral_game/data/models/bookmark.dart';
import 'package:flutter/material.dart';

/// 编辑收藏的结果（改名 / 置顶）。
class BookmarkEditorResult {
  const BookmarkEditorResult({required this.customName, required this.pinned});
  final String customName;
  final bool pinned;
}

/// 「编辑收藏」Dialog：改名 / 置顶。
///
/// 新建收藏已改为一键收藏（自动命名，见 `RoomState.quickSaveBookmark`），
/// 不再弹命名框；此 Dialog 只用于收藏页等处的后续编辑。
class BookmarkEditorDialog extends StatefulWidget {
  const BookmarkEditorDialog({super.key, required this.bookmark});

  final Bookmark bookmark;

  @override
  State<BookmarkEditorDialog> createState() => _BookmarkEditorDialogState();
}

class _BookmarkEditorDialogState extends State<BookmarkEditorDialog> {
  late final TextEditingController _name;
  late bool _pinned;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.bookmark.customName);
    _pinned = widget.bookmark.pinned;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _name.text.trim();
    if (trimmed.isEmpty) return;
    if (_formKey.currentState?.validate() != true) return;
    Navigator.pop(
      context,
      BookmarkEditorResult(customName: trimmed, pinned: _pinned),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑收藏'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '名字',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                validator: (v) => (v ?? '').trim().isEmpty ? '名字不能为空' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _pinned,
                onChanged: (v) => setState(() => _pinned = v),
                title: const Text('置顶'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 弹「编辑收藏」Dialog（外部组件统一入口），返回更新后的 [Bookmark]；取消返回 null。
Future<Bookmark?> showBookmarkEditor(
  BuildContext context, {
  required Bookmark existing,
}) async {
  final result = await showDialog<BookmarkEditorResult>(
    context: context,
    builder: (c) => BookmarkEditorDialog(bookmark: existing),
  );
  if (result == null) return null;
  return existing.copyWith(
    customName: result.customName,
    pinned: result.pinned,
  );
}
