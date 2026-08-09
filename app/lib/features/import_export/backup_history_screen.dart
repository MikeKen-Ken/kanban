import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import 'backup_file_picker.dart';
import 'backup_history_store.dart';

/// 远端备份列表超时，避免 WebDAV 挂起导致整页永久转圈。
const Duration kRemoteBackupListTimeout = Duration(seconds: 20);

class BackupHistoryScreen extends StatefulWidget {
  const BackupHistoryScreen({
    super.key,
    this.listLocalBackups,
    this.listRemoteBackups,
    this.createBackup,
    this.restoreBackup,
  });

  /// 测试注入；默认走 [BoardController]。
  final Future<List<BackupSnapshotInfo>> Function()? listLocalBackups;
  final Future<List<BackupSnapshotInfo>> Function()? listRemoteBackups;
  final Future<void> Function()? createBackup;
  final Future<void> Function(String id, {required bool remote})? restoreBackup;

  @override
  State<BackupHistoryScreen> createState() => _BackupHistoryScreenState();
}

class _BackupHistoryScreenState extends State<BackupHistoryScreen> {
  List<BackupSnapshotInfo> _local = const [];
  List<BackupSnapshotInfo> _remote = const [];
  bool _loading = true;
  bool _remoteLoading = false;
  bool _working = false;
  String? _localError;
  String? _remoteMessage;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<List<BackupSnapshotInfo>> _listLocal() {
    final override = widget.listLocalBackups;
    if (override != null) return override();
    return context.read<BoardController>().listLocalTimePointBackups();
  }

  Future<List<BackupSnapshotInfo>> _listRemote() {
    final override = widget.listRemoteBackups;
    if (override != null) return override();
    return context.read<BoardController>().listRemoteTimePointBackups();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _remoteLoading = true;
      _localError = null;
      _remoteMessage = null;
    });

    // 本地列表先结束整页 loading；远端独立加载，避免 WebDAV 挂起拖死页面。
    try {
      final local = await _listLocal();
      if (!mounted) return;
      setState(() {
        _local = local;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _local = const [];
        _localError = '本地备份无法读取：$error';
        _loading = false;
      });
    }

    try {
      final remote = await _listRemote().timeout(kRemoteBackupListTimeout);
      if (!mounted) return;
      setState(() {
        _remote = remote;
        _remoteMessage = null;
        _remoteLoading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _remote = const [];
        _remoteMessage = 'WebDAV 备份读取超时，请稍后重试';
        _remoteLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _remote = const [];
        _remoteMessage = 'WebDAV 备份暂时无法读取：$error';
        _remoteLoading = false;
      });
    }
  }

  Future<void> _createBackup() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final override = widget.createBackup;
      if (override != null) {
        await override();
      } else {
        await context.read<BoardController>().createTimePointBackup();
      }
      if (!mounted) return;
      showAppSnackBar(context, message: '本地备份已创建，WebDAV 可用时会自动镜像');
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: '创建备份失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _chooseBackupDirectory() async {
    final path = await pickBackupDirectory();
    if (path == null || !mounted) return;
    try {
      await context.read<BoardController>().setAutoBackupDirectory(path);
      if (!mounted) return;
      showAppSnackBar(context, message: '自动备份将保存到所选文件夹');
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: '设置备份文件夹失败：$error');
    }
  }

  Future<void> _resetBackupDirectory() async {
    try {
      await context.read<BoardController>().setAutoBackupDirectory(null);
      if (!mounted) return;
      showAppSnackBar(context, message: '已恢复默认自动备份文件夹');
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: '恢复默认文件夹失败：$error');
    }
  }

  Future<void> _restore(BackupSnapshotInfo snapshot,
      {required bool remote}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复到这个时间点？'),
        content: Text(
          '将恢复 ${_formatTime(snapshot.createdAt)} 的完整工作区。'
          '恢复前会自动保存当前状态。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      final override = widget.restoreBackup;
      if (override != null) {
        await override(snapshot.id, remote: remote);
      } else {
        await context.read<BoardController>().restoreTimePointBackup(
              snapshot.id,
              remote: remote,
            );
      }
      if (!mounted) return;
      showAppSnackBar(context, message: '工作区已恢复');
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: '恢复失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _formatTime(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());

  String _formatSize(int bytes) {
    if (bytes <= 0) return '大小由 WebDAV 管理';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Widget _section(
    String title,
    List<BackupSnapshotInfo> items, {
    required bool remote,
    bool loading = false,
    String? error,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              )
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  remote ? '暂无 WebDAV 备份' : '暂无本地备份',
                  key: ValueKey(remote ? 'remote-empty' : 'local-empty'),
                ),
              )
            else
              for (final snapshot in items)
                ListTile(
                  leading: Icon(
                    remote ? Icons.cloud_outlined : Icons.history,
                  ),
                  title: Text(_formatTime(snapshot.createdAt)),
                  subtitle: Text(_formatSize(snapshot.sizeBytes)),
                  trailing: const Icon(Icons.restore),
                  enabled: !_working,
                  onTap: () => _restore(snapshot, remote: remote),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDirectory =
        context.watch<BoardController>().appSettings.autoBackupDirectory;
    return Scaffold(
      appBar: AppBar(
        title: const Text('时间点备份'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _working || _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: '自动备份文件夹',
            onSelected: (value) {
              if (value == 'choose') {
                _chooseBackupDirectory();
              } else {
                _resetBackupDirectory();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'choose',
                child: Text('选择自动备份文件夹'),
              ),
              if (selectedDirectory != null)
                const PopupMenuItem(
                  value: 'reset',
                  child: Text('恢复默认文件夹'),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _working || _loading ? null : _createBackup,
        icon: _working
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('立即备份'),
      ),
      body: _loading
          ? const Center(
              key: ValueKey('backup-history-loading'),
              child: CircularProgressIndicator(),
            )
          : ListView(
              key: const ValueKey('backup-history-content'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  selectedDirectory == null
                      ? '数据有更新时每 10 分钟自动备份，仅保留最近 7 天。'
                      : '自动备份文件夹：$selectedDirectory\n数据有更新时每 10 分钟自动备份，仅保留最近 7 天。',
                ),
                const SizedBox(height: 12),
                _section(
                  '本地备份',
                  _local,
                  remote: false,
                  error: _localError,
                ),
                const SizedBox(height: 12),
                _section(
                  'WebDAV 备份',
                  _remote,
                  remote: true,
                  loading: _remoteLoading,
                  error: _remoteLoading ? null : _remoteMessage,
                ),
              ],
            ),
    );
  }
}
