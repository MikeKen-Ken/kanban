import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/kanban_paths.dart';

void main() {
  test('merge prefers higher revision', () {
    final local = KanbanBoard.empty(id: '1').copyWith(revision: 2, updatedAt: 100);
    final remote = KanbanBoard.empty(id: '1').copyWith(revision: 3, updatedAt: 50);
    expect(local.mergeWith(remote).revision, 3);
  });

  test('merge uses updatedAt when revision equal', () {
    final local = KanbanBoard.empty(id: '1').copyWith(revision: 2, updatedAt: 100);
    final remote = KanbanBoard.empty(id: '1').copyWith(revision: 2, updatedAt: 200);
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
    expect(merged.columns.length, 3);
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

  test('attachmentIdFromRemoteFileName parses main and thumb files', () {
    expect(
      KanbanPaths.attachmentIdFromRemoteFileName('550e8400-e29b-41d4-a716-446655440000.jpg'),
      '550e8400-e29b-41d4-a716-446655440000',
    );
    expect(
      KanbanPaths.attachmentIdFromRemoteFileName(
        '550e8400-e29b-41d4-a716-446655440000_thumb.jpg',
      ),
      '550e8400-e29b-41d4-a716-446655440000',
    );
    expect(KanbanPaths.attachmentIdFromRemoteFileName('notes.txt'), isNull);
  });
}
