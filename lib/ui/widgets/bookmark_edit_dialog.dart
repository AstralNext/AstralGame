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
/// 收藏房间时会先弹命名框（见 [showBookmarkNameDialog]），由用户确认/修改名字；
/// 此 Dialog 用于收藏页等处的后续编辑（改名 / 置顶）。
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
        FilledButton(onPressed: _submit, child: const Text('保存')),
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

/// 收藏房间前的命名框：预填自动名 [initialName]（默认全选，方便直接改写），
/// 用户确认后返回 trim 后的名字；取消返回 null。
Future<String?> showBookmarkNameDialog(
  BuildContext context, {
  required String initialName,
  String cancelLabel = '取消',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _BookmarkNameDialog(initialName: initialName, cancelLabel: cancelLabel),
  );
}

/// 命名框内容：controller 由 State 持有，随弹窗退场动画结束一并释放。
class _BookmarkNameDialog extends StatefulWidget {
  const _BookmarkNameDialog({
    required this.initialName,
    required this.cancelLabel,
  });

  final String initialName;
  final String cancelLabel;

  @override
  State<_BookmarkNameDialog> createState() => _BookmarkNameDialogState();
}

class _BookmarkNameDialogState extends State<_BookmarkNameDialog> {
  late final TextEditingController _name;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialName.length,
      );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('收藏房间'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名字',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            validator: (v) => (v ?? '').trim().isEmpty ? '名字不能为空' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
