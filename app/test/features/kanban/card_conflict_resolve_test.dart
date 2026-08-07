import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardStorage storage;
  late BoardController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_card_conflict_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = BoardStorage(baseDirectory: tempDir, prefs: prefs);
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: storage,
    );
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<({String columnId, KanbanCard card})> plantDeleteConflict() async {
    final columnId = controller.board!.columns.first.id;
    final cardId = await controller.addCard(columnId, '冲突卡');
    expect(cardId, isNotNull);

    final board = controller.board!;
    final next = board.copyWith(
      columns: board.columns.map((col) {
        if (col.id != columnId) return col;
        return col.copyWith(
          cards: col.cards.map((card) {
            if (card.id != cardId) return card;
            return card.copyWith(conflictDeleted: true);
          }).toList(),
        );
      }).toList(),
    );
    await storage.saveBoard(board.id, next);

    final projectId = controller.activeProjectId!;
    await controller.createProject('临时项目');
    await controller.switchProject(projectId);

    final card = controller.board!.columns
        .expand((col) => col.cards)
        .firstWhere((c) => c.id == cardId);
    expect(card.conflictDeleted, isTrue);
    expect(card.hasConflict, isTrue);
    return (columnId: columnId, card: card);
  }

  test('空闲时保留当前可清除删改冲突', () async {
    final planted = await plantDeleteConflict();
    await controller.resolveCardConflict(
      planted.columnId,
      planted.card.id,
      CardConflictResolution.keepPrimary,
    );

    final card = controller.board!.columns
        .expand((col) => col.cards)
        .firstWhere((c) => c.id == planted.card.id);
    expect(card.hasConflict, isFalse);
    expect(card.conflictDeleted, isFalse);
  });

  test('空闲时确认删除会移入回收站', () async {
    final planted = await plantDeleteConflict();
    await controller.resolveCardConflict(
      planted.columnId,
      planted.card.id,
      CardConflictResolution.keepOther,
    );

    final stillThere = controller.board!.columns
        .expand((col) => col.cards)
        .any((c) => c.id == planted.card.id);
    expect(stillThere, isFalse);
    expect(
      controller.activeProjectTrash.items.any(
        (item) => item.cardPayload?.id == planted.card.id,
      ),
      isTrue,
    );
  });

  test('突变锁被长事务占用时，解决冲突会一直等到锁释放', () async {
    final planted = await plantDeleteConflict();
    final lockHeld = Completer<void>();
    final unlock = Completer<void>();

    final blocker =
        controller.runOnProject(controller.activeProjectId!, () async {
      lockHeld.complete();
      await unlock.future;
    });
    await lockHeld.future;

    var resolveDone = false;
    final resolve = controller
        .resolveCardConflict(
          planted.columnId,
          planted.card.id,
          CardConflictResolution.keepPrimary,
        )
        .then((_) => resolveDone = true);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      resolveDone,
      isFalse,
      reason: '占锁期间解决冲突不应完成——对应详情按钮“点了没反应”',
    );

    unlock.complete();
    await blocker;
    await resolve.timeout(const Duration(seconds: 2));
    expect(resolveDone, isTrue);

    final card = controller.board!.columns
        .expand((col) => col.cards)
        .firstWhere((c) => c.id == planted.card.id);
    expect(card.hasConflict, isFalse);
  });
}
