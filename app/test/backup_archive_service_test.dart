import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/import_export/backup_archive_service.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/features/sync_conflict/workspace_snapshot.dart';

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
      ),
      createdAt: DateTime(2026, 8, 3),
    );

    final decoded = service.decode(encoded);

    expect(decoded.workspace.manifest.projects, isEmpty);
    expect(decoded.attachments['attachments/p1/image.jpg'], [1, 2, 3]);
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
}
