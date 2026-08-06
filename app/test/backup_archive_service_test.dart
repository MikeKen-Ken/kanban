import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/import_export/backup_archive_service.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/features/sync_conflict/workspace_snapshot.dart';
import 'package:kanban/features/trash/trash_models.dart';

void main() {
  const service = BackupArchiveService();

  ProjectWorkspaceSnapshot emptyWorkspace() {
    return const ProjectWorkspaceSnapshot(
      manifest: ProjectsManifest(
        projects: [],
        updatedAt: 0,
        revision: 0,
      ),
      boards: {},
      settings: {},
    );
  }

  test('完整备份 ZIP 可往返工作区与附件', () {
    final encoded = service.encode(
      BackupPackage(
        workspace: emptyWorkspace(),
        attachments: {
          'attachments/p1/image.jpg': Uint8List.fromList([1, 2, 3]),
        },
        labelTrash: const [
          TrashItem(
            id: 'label-trash',
            type: TrashItemType.customLabel,
            deletedAt: 1,
            displayName: '旧标签',
            payload: {},
          ),
        ],
      ),
      createdAt: DateTime(2026, 8, 3),
    );

    final decoded = service.decode(encoded);

    expect(decoded.workspace.manifest.projects, isEmpty);
    expect(decoded.attachments['attachments/p1/image.jpg'], [1, 2, 3]);
    expect(decoded.labelTrash.single.id, 'label-trash');
  });

  test('拒绝目录穿越附件路径', () {
    expect(
      () => service.encode(
        BackupPackage(
          workspace: emptyWorkspace(),
          attachments: {
            'attachments/../secret': Uint8List.fromList([1]),
          },
        ),
      ),
      throwsFormatException,
    );
  });

  test('拒绝校验清单未声明的附件', () {
    final encoded = service.encode(
      BackupPackage(workspace: emptyWorkspace()),
    );
    final archive = ZipDecoder().decodeBytes(encoded);
    archive.addFile(
      ArchiveFile.bytes(
        'attachments/p1/undeclared.jpg',
        Uint8List.fromList([9]),
      ),
    );

    expect(
      () => service.decode(ZipEncoder().encodeBytes(archive)),
      throwsFormatException,
    );
  });
}
