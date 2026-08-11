import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/attachments/attachment_refs.dart';
import 'package:kanban/features/project/project_settings.dart';
import 'package:kanban/features/trash/trash_models.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  test('引用收集包含看板背景附件 id', () {
    final board = KanbanBoard(
      id: 'p1',
      title: '板',
      updatedAt: 1,
      revision: 1,
      columns: [
        KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: [
            KanbanCard(
              id: 'c1',
              title: '卡',
              order: 0,
              createdAt: 1,
              updatedAt: 1,
              attachments: [
                CardAttachment(
                  id: 'card-att',
                  fileName: 'a.jpg',
                  mimeType: 'image/jpeg',
                  order: 0,
                  createdAt: 1,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    const settings = ProjectSettings(backgroundAttachmentId: 'bg-att');
    final ids = collectReferencedAttachmentIds(
      board,
      TrashBin.empty,
      settings: settings,
    );
    expect(ids, containsAll(['card-att', 'bg-att']));
  });

  test('无背景时不额外加入空 id', () {
    final board = KanbanBoard(
      id: 'p1',
      title: '板',
      updatedAt: 1,
      revision: 1,
      columns: const [],
    );
    final ids = collectReferencedAttachmentIds(
      board,
      TrashBin.empty,
      settings: const ProjectSettings(),
    );
    expect(ids, isEmpty);
  });

  test('工作区壁纸不作为项目附件重复同步', () {
    final board = KanbanBoard(
      id: 'p1',
      title: '板',
      updatedAt: 1,
      revision: 1,
      columns: const [],
    );
    final ids = collectReferencedAttachmentIds(
      board,
      TrashBin.empty,
      settings: const ProjectSettings(
        backgroundAttachmentId: 'w1',
        wallpaperIds: ['w1', 'w2'],
      ),
    );
    expect(ids, isEmpty);
  });
}
