import '../sync_conflict/workspace_merge.dart';
import '../trash/trash_models.dart';
import 'backup_archive_service.dart';

/// 从时间点备份恢复工作区时采用的策略。
enum BackupRestoreMode { replace, merge }

/// 将备份与当前工作区合并，避免为了找回旧数据而覆盖之后的改动。
class BackupRestoreService {
  const BackupRestoreService();

  BackupPackage merge({
    required BackupPackage current,
    required BackupPackage backup,
  }) {
    final mergedLabelTrash = TrashBin(
      items: current.labelTrash,
      updatedAt: 0,
      revision: 0,
    ).mergeWith(
      TrashBin(items: backup.labelTrash, updatedAt: 0, revision: 0),
    );
    return BackupPackage(
      workspace: mergeWorkspaces(
        local: current.workspace,
        remote: backup.workspace,
      ),
      // 同一附件 id 的现有文件优先，避免合并操作静默覆盖较新的二进制内容。
      attachments: {...backup.attachments, ...current.attachments},
      labelTrash: mergedLabelTrash.items,
    );
  }
}
