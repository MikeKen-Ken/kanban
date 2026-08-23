import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import 'backup_file_picker.dart';
import 'backup_history_store.dart';
import 'backup_restore_service.dart';
import 'backup_retention.dart';

class BackupHistoryScreen extends StatefulWidget {
  const BackupHistoryScreen({
    super.key,
    this.listLocalBackups,
    this.autoBackupDirectory,
    this.autoBackupRetentionDays,
    this.onRetentionDaysChanged,
    this.createBackup,
    this.restoreBackup,
  });

  /// 测试注入；默认走 [BoardController]。
  final Future<List<BackupSnapshotInfo>> Function()? listLocalBackups;
  final String? Function()? autoBackupDirectory;
  final int Function()? autoBackupRetentionDays;
  final Future<void> Function(int days)? onRetentionDaysChanged;
  final Future<void> Function()? createBackup;
  final Future<void> Function(String id, BackupRestoreMode mode)? restoreBackup;

  @override
  State<BackupHistoryScreen> createState() => _BackupHistoryScreenState();
}

class _BackupHistoryScreenState extends State<BackupHistoryScreen> {
  List<BackupSnapshotInfo> _local = const [];
  bool _loading = true;
  bool _working = false;
  String? _localError;

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

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _localError = null;
    });

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
        _localError = 'Could not read local backups: $error';
        _loading = false;
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
      showAppSnackBar(context, message: 'Local backup created');
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'Could not create backup: $error');
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
      showAppSnackBar(context,
          message: 'Automatic backups will use the selected folder');
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'Could not set backup folder: $error');
    }
  }

  Future<void> _changeRetentionDays(int days) async {
    final override = widget.onRetentionDaysChanged;
    if (override != null) {
      await override(days);
      if (!mounted) return;
      await _reload();
      return;
    }
    await context.read<BoardController>().saveAppSettings(
          context.read<BoardController>().appSettings.copyWith(
                autoBackupRetentionDays: days,
              ),
        );
    if (!mounted) return;
    await _reload();
  }

  Future<void> _resetBackupDirectory() async {
    try {
      await context.read<BoardController>().setAutoBackupDirectory(null);
      if (!mounted) return;
      showAppSnackBar(context, message: 'Restored the default backup folder');
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context,
          message: 'Could not restore the default folder: $error');
    }
  }

  Future<void> _restore(BackupSnapshotInfo snapshot) async {
    final mode = await showDialog<BackupRestoreMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this point-in-time backup?'),
        content: Text(
          'Full restore replaces the current workspace. Restore and merge keeps new data from both versions and marks conflicting fields.\n'
          'The full workspace from ${_formatTime(snapshot.createdAt)} will be restored. '
          'Your current state is backed up first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, BackupRestoreMode.merge),
            child: const Text('Restore and merge'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, BackupRestoreMode.replace),
            child: const Text('Full restore'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    setState(() => _working = true);
    try {
      final override = widget.restoreBackup;
      if (override != null) {
        await override(snapshot.id, mode);
      } else {
        await context
            .read<BoardController>()
            .restoreTimePointBackup(snapshot.id, mode: mode);
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: mode == BackupRestoreMode.merge
            ? 'Workspace restored and merged'
            : 'Workspace restored',
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'Could not restore backup: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _formatTime(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());

  String _formatSize(int bytes) {
    if (bytes <= 0) return 'Unknown size';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Widget _section(
    String title,
    List<BackupSnapshotInfo> items, {
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
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No local backups yet',
                  key: ValueKey('local-empty'),
                ),
              )
            else
              for (final snapshot in items)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(_formatTime(snapshot.createdAt)),
                  subtitle: Text(_formatSize(snapshot.sizeBytes)),
                  trailing: const Icon(Icons.restore),
                  enabled: !_working,
                  onTap: () => _restore(snapshot),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final directoryOverride = widget.autoBackupDirectory;
    final selectedDirectory = directoryOverride != null
        ? directoryOverride()
        : context.watch<BoardController>().appSettings.autoBackupDirectory;
    final retentionOverride = widget.autoBackupRetentionDays;
    final retentionDays = retentionOverride != null
        ? retentionOverride()
        : context.watch<BoardController>().appSettings.autoBackupRetentionDays;
    final retentionOptions = [
      ...autoBackupRetentionDayOptions,
      if (!autoBackupRetentionDayOptions.contains(retentionDays)) retentionDays,
    ]..sort();
    final retentionHint = retentionDays <= 0
        ? 'Backups in the current folder are never removed automatically.'
        : 'Backups older than $retentionDays days are removed from the selected folder.';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Point-in-time backup'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _working || _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Automatic backup folder',
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
                child: Text('Choose automatic backup folder'),
              ),
              if (selectedDirectory != null)
                const PopupMenuItem(
                  value: 'reset',
                  child: Text('Restore default folder'),
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
        label: const Text('Back up now'),
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
                      ? 'Back up automatically every 10 minutes when data changes. $retentionHint'
                      : 'Automatic backup folder: $selectedDirectory\n'
                          'Back up automatically every 10 minutes when data changes. $retentionHint',
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.auto_delete_outlined),
                  title: const Text('Automatically remove expired backups'),
                  subtitle: Text(
                    retentionDays <= 0
                        ? 'Off: keep all backups in the current folder'
                        : 'Remove backups older than $retentionDays days from the selected folder',
                  ),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const ValueKey('backup-retention-days'),
                      value: retentionDays,
                      items: [
                        for (final option in retentionOptions)
                          DropdownMenuItem(
                            value: option,
                            child: Text(autoBackupRetentionDaysLabel(option)),
                          ),
                      ],
                      onChanged: _working
                          ? null
                          : (value) {
                              if (value == null) return;
                              _changeRetentionDays(value);
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _section(
                  'Local backups',
                  _local,
                  error: _localError,
                ),
              ],
            ),
    );
  }
}
