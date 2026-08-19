import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/activity/activity_models.dart';
import 'package:kanban/models/kanban_models.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardStorage storage;
  late BoardController controller;
  late String todoColumnId;
  late String projectId;

  Future<KanbanBoard> loadDiskBoard() => storage.loadBoard(projectId);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_ephemeral_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = BoardStorage(baseDirectory: tempDir, prefs: prefs);
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: storage,
    );
    projectId = controller.activeProjectId!;
    todoColumnId =
        controller.board!.columns.firstWhere((c) => c.id == 'todo').id;
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('beginBlankCard 仅进内存，取消后不落盘也不进回收站', () async {
    final beforeRevision = controller.board!.revision;

    final cardId = await controller.beginBlankCard(todoColumnId);
    expect(cardId, isNotNull);
    expect(
      controller.board!.columns
          .expand((c) => c.cards)
          .any((c) => c.id == cardId),
      isTrue,
    );
    expect(controller.board!.revision, beforeRevision);

    final diskWhileDraft = await loadDiskBoard();
    expect(
      diskWhileDraft.columns.expand((c) => c.cards).any((c) => c.id == cardId),
      isFalse,
    );

    await controller.discardBlankNewCard(todoColumnId, cardId!);
    expect(
      controller.board!.columns
          .expand((c) => c.cards)
          .any((c) => c.id == cardId),
      isFalse,
    );
    expect(controller.activeProjectTrash.items, isEmpty);

    final diskAfterDiscard = await loadDiskBoard();
    expect(
      diskAfterDiscard.columns
          .expand((c) => c.cards)
          .any((c) => c.id == cardId),
      isFalse,
    );
  });

  test('草稿填写标题后首次保存才落盘并记创建活动', () async {
    final cardId = (await controller.beginBlankCard(todoColumnId))!;

    final error = await controller.updateCardFull(
      todoColumnId,
      cardId,
      title: '确认新建',
    );
    expect(error, isNull);

    final disk = await loadDiskBoard();
    expect(
      disk.columns.expand((c) => c.cards).any((c) => c.id == cardId),
      isTrue,
    );

    final log = controller.sharedContent.activityByProject[projectId];
    expect(log, isNotNull);
    expect(
      log!.events.any(
        (e) => e.entityId == cardId && e.action == ActivityAction.created,
      ),
      isTrue,
    );
  });

  test('其它落盘不会把未确认草稿写进磁盘', () async {
    final draftId = (await controller.beginBlankCard(todoColumnId))!;
    final realId = (await controller.addCard(todoColumnId, '真实卡'))!;

    final disk = await loadDiskBoard();
    final diskIds = disk.columns.expand((c) => c.cards).map((c) => c.id);
    expect(diskIds, contains(realId));
    expect(diskIds, isNot(contains(draftId)));

    expect(
      controller.board!.columns
          .expand((c) => c.cards)
          .any((c) => c.id == draftId),
      isTrue,
    );
  });
}
