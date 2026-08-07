import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import 'backup_history_store.dart';
import '../../common/app_snack_bar.dart';

class BackupHistoryScreen extends StatefulWidget {
  const BackupHistoryScreen({super.key});

  @override
  State<BackupHistoryScreen> createState() => _BackupHistoryScreenState();
}

class _BackupHistoryScreenState extends State<BackupHistoryScreen> {
  List<BackupSnapshotInfo> _local = const [];
  List<BackupSnapshotInfo> _remote = const [];
  bool _loading = true;
  bool _working = false;
  String? _remoteMessage;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _remoteMessage = null;
    });
    final controller = context.read<BoardController>();
    final local = await controller.listLocalTimePointBackups();
    List<BackupSnapshotInfo> remote = const [];
    String? remoteMessage;
    try {
      remote = await controller.listRemoteTimePointBackups();
    } catch (error) {
      remoteMessage = 'WebDAV 备份暂时无法读取：$error';
    }
    if (!mounted) return;
    setState(() {
      _local = local;
      _remote = remote;
      _remoteMessage = remoteMessage;
      _loading = false;
    });
  }

  Future<void> _createBackup() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await context.read<BoardController>().createTimePointBackup();
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

  Future<void> _restore(BackupSnapshotInfo snapshot, {required bool remote}) async {
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
      await context.read<BoardController>().restoreTimePointBackup(
            snapshot.id,
            remote: remote,
          );
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
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无备份'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('时间点备份'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _working ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _working ? null : _createBackup,
        icon: _working
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('立即备份'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                const Text('数据有更新时每 10 分钟自动备份，仅保留最近 7 天。'),
                const SizedBox(height: 12),
                _section('本地备份', _local, remote: false),
                const SizedBox(height: 12),
                _section('WebDAV 备份', _remote, remote: true),
                if (_remoteMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _remoteMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
