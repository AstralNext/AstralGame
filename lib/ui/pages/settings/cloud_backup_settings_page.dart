import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:astral_game/data/services/webdav_backup_service.dart';

class CloudBackupSettingsPage extends StatefulWidget {
  const CloudBackupSettingsPage({super.key});

  @override
  State<CloudBackupSettingsPage> createState() =>
      _CloudBackupSettingsPageState();
}

class _CloudBackupSettingsPageState extends State<CloudBackupSettingsPage> {
  final _settings = GetIt.I<AppSettingsService>();
  final _backupService = GetIt.I<WebDavBackupService>();

  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _remotePathController = TextEditingController();

  bool _obscurePassword = true;
  bool _isTesting = false;
  bool? _connectionStatus;
  String _connectionMessage = '';

  bool _isBackingUp = false;
  double _backupProgress = 0;
  String _backupMessage = '';

  bool _isLoadingList = false;
  List<RemoteBackupEntry> _backupList = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (_settings.isWebDavConfigured()) {
      _refreshList();
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remotePathController.dispose();
    super.dispose();
  }

  void _loadSettings() {
    _urlController.text = _settings.getWebDavUrl() ?? '';
    _usernameController.text = _settings.getWebDavUsername() ?? '';
    _passwordController.text = _settings.getWebDavPassword() ?? '';
    _remotePathController.text = _settings.getWebDavRemotePath() ?? '';

    if (_settings.isWebDavConfigured()) {
      _connectionStatus = null;
    }
  }

  Future<void> _saveSettings() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      await _settings.clearAllWebDavSettings();
    } else {
      await _settings.setWebDavUrl(url);
      await _settings.setWebDavUsername(_usernameController.text.trim());
      await _settings.setWebDavPassword(_passwordController.text.trim());
      await _settings.setWebDavRemotePath(_remotePathController.text.trim());
    }
    _connectionStatus = null;
    if (mounted) setState(() {});
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = null;
      _connectionMessage = '';
    });
    await _saveSettings();

    try {
      final success = await _backupService.testConnection();
      setState(() {
        _isTesting = false;
        _connectionStatus = success;
        _connectionMessage = success ? '连接成功' : '连接失败，请检查地址和凭据';
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _connectionStatus = false;
        _connectionMessage = '连接失败: $e';
      });
    }
  }

  Future<void> _startBackup() async {
    if (_isBackingUp) return;
    setState(() {
      _isBackingUp = true;
      _backupProgress = 0;
      _backupMessage = '正在准备...';
    });

    try {
      await _backupService.backup(
        onProgress: (stage, progress, message) {
          if (mounted) {
            setState(() {
              _backupProgress = progress;
              _backupMessage = message;
            });
          }
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('备份成功'),
            backgroundColor: Colors.green,
          ),
        );
        _refreshList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('备份失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _backupProgress = 0;
        });
      }
    }
  }

  Future<void> _refreshList() async {
    setState(() => _isLoadingList = true);
    try {
      final list = await _backupService.listBackups();
      if (mounted) setState(() => _backupList = list);
    } catch (_) {
      if (mounted) setState(() => _backupList = []);
    } finally {
      if (mounted) setState(() => _isLoadingList = false);
    }
  }

  Future<void> _confirmRestore(RemoteBackupEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复备份'),
        content: Text(
            '确定要从以下备份恢复数据吗？\n\n'
            '文件: ${entry.fileName}\n'
            '时间: ${entry.lastModified != null ? _formatDate(entry.lastModified!) : "未知"}\n'
            '大小: ${entry.size != null ? "${entry.size} B" : "未知"}\n\n'
            '恢复将覆盖本地的房间列表；若备份中包含服务器列表也会一并覆盖。旧版备份可能仅有房间数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isBackingUp = true;
      _backupProgress = 0;
      _backupMessage = '正在恢复...';
    });

    try {
      await _backupService.restore(
        entry.remotePath,
        onProgress: (stage, progress, message) {
          if (mounted) {
            setState(() {
              _backupProgress = progress;
              _backupMessage = message;
            });
          }
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('恢复成功，部分数据可能需要重启应用后生效'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('恢复失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _backupProgress = 0;
        });
      }
    }
  }

  Future<void> _deleteBackup(RemoteBackupEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除备份'),
        content: Text('确定要删除远程备份 ${entry.fileName} 吗？\n\n此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _backupService.deleteBackup(entry.remotePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备份已删除')),
        );
        _refreshList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatSize(String? sizeStr) {
    if (sizeStr == null) return '未知';
    final size = int.tryParse(sizeStr);
    if (size == null) return '$sizeStr B';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('云备份')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimensions.pagePaddingH,
          16,
          AppDimensions.pagePaddingH,
          32,
        ),
        children: [
        AstralCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Row(
                  children: [
                    Icon(Icons.cloud_outlined, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      'WebDAV 连接',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (_connectionStatus != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _connectionStatus!
                              ? Colors.green.withValues(alpha: 0.12)
                              : Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _connectionStatus!
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              size: 14,
                              color: _connectionStatus!
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _connectionMessage.isEmpty
                                  ? (_connectionStatus!
                                      ? '已连接'
                                      : '连接失败')
                                  : _connectionMessage,
                              style: TextStyle(
                                fontSize: 12,
                                color: _connectionStatus!
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _urlController,
                  label: '服务器地址',
                  hint: 'https://dav.jianguoyun.com/dav/',
                  icon: Icons.link,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _usernameController,
                        label: '用户名',
                        hint: 'your@email.com',
                        icon: Icons.person,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _passwordController,
                        label: '密码',
                        hint: '应用密码',
                        icon: Icons.lock,
                        obscure: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 18,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _remotePathController,
                  label: '远程路径',
                  hint: '/AstralGame',
                  icon: Icons.folder_outlined,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isTesting ? null : _testConnection,
                        icon: _isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_find, size: 18),
                        label: Text(_isTesting ? '测试中...' : '测试连接'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isTesting ? null : _saveSettings,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('保存配置'),
                      ),
                    ),
                  ],
                ),
              ],
          ),
        ),
        const SizedBox(height: 24),
        AstralCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Row(
                  children: [
                    Icon(Icons.backup, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      '备份与恢复',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '将当前房间数据打包备份到 WebDAV，或从云端恢复。',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                if (_isBackingUp) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _backupProgress > 0 ? _backupProgress : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _backupMessage,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            (_isBackingUp || !_settings.isWebDavConfigured())
                                ? null
                                : _startBackup,
                        icon: const Icon(Icons.cloud_upload, size: 18),
                        label: const Text('立即备份'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            (_isBackingUp || !_settings.isWebDavConfigured())
                                ? null
                                : _refreshList,
                        icon: _isLoadingList
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(_isLoadingList ? '刷新中...' : '刷新列表'),
                      ),
                    ),
                  ],
                ),
                if (!_settings.isWebDavConfigured())
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '请先配置 WebDAV 连接信息',
                      style: TextStyle(
                        color: colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
          ),
        ),
        const SizedBox(height: 24),
        if (_settings.isWebDavConfigured()) ...[
          Text(
            '备份历史',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '远程服务器上的备份文件列表',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoadingList)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_backupList.isEmpty)
            AstralCard(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 40,
                      color: colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '暂无备份',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._backupList.map((entry) => _buildBackupEntry(entry)),
        ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, size: 18, color: colorScheme.primary),
        suffixIcon: suffixIcon,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildBackupEntry(RemoteBackupEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AstralCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.archive_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(entry.lastModified ??
                        DateTime.fromMillisecondsSinceEpoch(0)),
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatSize(entry.size),
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.restore, size: 18, color: colorScheme.primary),
              tooltip: '恢复',
              onPressed: _isBackingUp ? null : () => _confirmRestore(entry),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18, color: colorScheme.error),
              tooltip: '删除',
              onPressed: _isBackingUp ? null : () => _deleteBackup(entry),
            ),
          ],
        ),
      ),
    );
  }
}
