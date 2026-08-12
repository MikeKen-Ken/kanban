import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/sync_conflict/board_merge.dart';
import 'package:kanban/features/project/projects_manifest.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/kanban_paths.dart';

void main() {
  test('merge prefers higher revision', () {
    final local =
        KanbanBoard.empty(id: '1').copyWith(revision: 2, updatedAt: 100);
    final remote =
        KanbanBoard.empty(id: '1').copyWith(revision: 3, updatedAt: 50);
    expect(local.mergeWith(remote).revision, 3);
  });

  test('merge uses updatedAt when revision equal', () {
    final local =
        KanbanBoard.empty(id: '1').copyWith(revision: 2, updatedAt: 100);
    final remote =
        KanbanBoard.empty(id: '1').copyWith(revision: 2, updatedAt: 200);
    expect(local.mergeWith(remote).updatedAt, 200);
  });

  test('merge keeps columns that only exist on the older side', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final local = KanbanBoard.empty(id: '1').copyWith(
      revision: 5,
      updatedAt: now,
    );
    final remote = KanbanBoard(
      id: '1',
      title: '我的看板',
      updatedAt: now + 1000,
      revision: 6,
      columns: [
        KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: [],
        ),
        KanbanColumn(
          id: 'doing',
          title: '进行中',
          order: 1,
          cards: [],
        ),
      ],
    );

    final merged = local.mergeWith(remote);
    expect(merged.columns.map((c) => c.id), contains('done'));
    expect(merged.columns.map((c) => c.id), contains('blocked'));
    expect(merged.columns.map((c) => c.id), contains('verify'));
    expect(merged.columns.map((c) => c.id), contains('rework'));
    expect(merged.columns.length, 6);
  });

  test('merge keeps newer card when the same card exists on both sides', () {
    final local = KanbanBoard(
      id: '1',
      title: '我的看板',
      updatedAt: 100,
      revision: 2,
      columns: [
        KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: [
            KanbanCard(
              id: 'card-1',
              title: '本地标题',
              order: 0,
              createdAt: 1,
              updatedAt: 100,
            ),
          ],
        ),
      ],
    );
    final remote = local.copyWith(
      updatedAt: 200,
      revision: 3,
      columns: [
        KanbanColumn(
          id: 'todo',
          title: '待办',
          order: 0,
          cards: [
            KanbanCard(
              id: 'card-1',
              title: '远端标题',
              order: 0,
              createdAt: 1,
              updatedAt: 200,
            ),
          ],
        ),
      ],
    );

    final merged = local.mergeWith(remote);
    expect(merged.columns.first.cards.single.title, '远端标题');
    expect(merged.columns.first.cards.single.hasConflict, isTrue);
    expect(merged.columns.first.cards.single.conflictSide?.title, '本地标题');
  });

  test('CardAttachment serializes round trip', () {
    final attachment = CardAttachment(
      id: 'att-1',
      fileName: 'photo.png',
      mimeType: 'image/jpeg',
      order: 0,
      createdAt: 100,
      width: 800,
      height: 600,
    );
    final json = attachment.toJson();
    final restored = CardAttachment.fromJson(json);
    expect(restored.id, attachment.id);
    expect(restored.fileName, attachment.fileName);
    expect(restored.width, 800);
  });

  test('KanbanCard copyWith 可清空备注', () {
    final card = KanbanCard(
      id: 'card-1',
      title: '带备注',
      description: '旧备注',
      order: 0,
      createdAt: 1,
    );
    final cleared = card.copyWith(description: null);
    expect(cleared.description, isNull);

    final updated = card.copyWith(description: '新备注');
    expect(updated.description, '新备注');

    final unchanged = card.copyWith(title: '新标题');
    expect(unchanged.description, '旧备注');
  });

  test('KanbanCard keeps attachments in json', () {
    final card = KanbanCard(
      id: 'card-1',
      title: '带图卡片',
      order: 0,
      createdAt: 1,
      attachments: [
        CardAttachment(
          id: 'att-1',
          fileName: 'a.jpg',
          mimeType: 'image/jpeg',
          order: 0,
          createdAt: 1,
        ),
      ],
    );
    final restored = KanbanCard.fromJson(card.toJson());
    expect(restored.attachments, hasLength(1));
    expect(restored.coverAttachment?.id, 'att-1');
  });

  test('KanbanCard conflictSide serializes without nesting', () {
    final card = KanbanCard(
      id: 'card-1',
      title: '主标题',
      order: 0,
      createdAt: 1,
      conflictSide: KanbanCard(
        id: 'card-1',
        title: '冲突标题',
        order: 0,
        createdAt: 1,
      ),
      conflictColumnId: 'doing',
    );
    final restored = KanbanCard.fromJson(card.toJson());
    expect(restored.hasConflict, isTrue);
    expect(restored.conflictSide?.title, '冲突标题');
    expect(restored.conflictColumnId, 'doing');
    expect(restored.toJson()['conflictSide'], isA<Map>());
    expect(
      (restored.toJson()['conflictSide'] as Map)['conflictSide'],
      isNull,
    );
  });

  test('看板与项目标题冲突可选择另一侧并清除标记', () {
    final board = KanbanBoard.empty(id: '1').copyWith(
      conflictTitle: '另一侧看板',
    );
    final resolvedBoard = board.copyWith(
      title: board.conflictTitle,
      clearConflictTitle: true,
    );
    expect(resolvedBoard.title, '另一侧看板');
    expect(resolvedBoard.conflictTitle, isNull);

    const project = ProjectEntry(
      id: '1',
      title: '当前项目',
      updatedAt: 1,
      revision: 1,
      conflictTitle: '另一侧项目',
    );
    final resolvedProject = project.copyWith(
      title: project.conflictTitle,
      clearConflictTitle: true,
    );
    expect(resolvedProject.title, '另一侧项目');
    expect(resolvedProject.conflictTitle, isNull);
  });

  test('CardFileAttachment serializes round trip', () {
    final attachment = CardFileAttachment(
      id: 'file-1',
      fileName: 'notes.txt',
      mimeType: 'text/plain',
      order: 0,
      createdAt: 100,
      size: 42,
    );
    final json = attachment.toJson();
    final restored = CardFileAttachment.fromJson(json);
    expect(restored.id, attachment.id);
    expect(restored.fileName, attachment.fileName);
    expect(restored.size, 42);
  });

  test('KanbanCard keeps fileAttachments in json', () {
    final card = KanbanCard(
      id: 'card-1',
      title: '带文件卡片',
      order: 0,
      createdAt: 1,
      fileAttachments: [
        CardFileAttachment(
          id: 'file-1',
          fileName: 'script.sh',
          mimeType: 'text/x-shellscript',
          order: 0,
          createdAt: 1,
          size: 128,
        ),
      ],
    );
    final restored = KanbanCard.fromJson(card.toJson());
    expect(restored.fileAttachments, hasLength(1));
    expect(restored.sortedFileAttachments.single.fileName, 'script.sh');
  });

  test('attachmentIdFromRemoteFileName parses main and thumb files', () {
    expect(
      KanbanPaths.attachmentIdFromRemoteFileName(
          '550e8400-e29b-41d4-a716-446655440000.jpg'),
      '550e8400-e29b-41d4-a716-446655440000',
    );
    expect(
      KanbanPaths.attachmentIdFromRemoteFileName(
        '550e8400-e29b-41d4-a716-446655440000_thumb.jpg',
      ),
      '550e8400-e29b-41d4-a716-446655440000',
    );
    expect(KanbanPaths.attachmentIdFromRemoteFileName('notes.txt'), isNull);
    expect(
      KanbanPaths.fileAttachmentIdFromRemoteFileName(
        '550e8400-e29b-41d4-a716-446655440000.bin',
      ),
      '550e8400-e29b-41d4-a716-446655440000',
    );
  });
}
