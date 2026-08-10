import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/mcp_run_context_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late McpRunContextStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = McpRunContextStore(prefsLoader: () async => prefs);
  });

  test('按项目和卡片隔离保存本机运行上下文', () async {
    const context = McpRunContext(
      projectId: 'project-a',
      cardId: 'card-a',
      runId: 'run-1',
      lastSubagentId: 'agent-1',
      baseCommit: 'abc123',
      lastCommit: 'def456',
      reviewRound: 2,
      handoffSummary: '已完成主要修改，等待返工。',
      resumeStatus: 'resumed',
      updatedAt: 123456,
    );
    await store.write(context);

    final restored = await store.read(
      projectId: 'project-a',
      cardId: 'card-a',
    );
    expect(restored, isNotNull);
    expect(restored!.toJson(), context.toJson());
    expect(
      await store.read(projectId: 'project-b', cardId: 'card-a'),
      isNull,
    );
  });

  test('覆盖和删除上下文不影响其他卡片', () async {
    await store.write(
      const McpRunContext(
        projectId: 'project-a',
        cardId: 'card-a',
        runId: 'run-1',
        updatedAt: 1,
      ),
    );
    await store.write(
      const McpRunContext(
        projectId: 'project-a',
        cardId: 'card-b',
        runId: 'run-2',
        updatedAt: 2,
      ),
    );
    await store.write(
      const McpRunContext(
        projectId: 'project-a',
        cardId: 'card-a',
        runId: 'run-3',
        reviewRound: 1,
        updatedAt: 3,
      ),
    );

    expect(
      (await store.read(projectId: 'project-a', cardId: 'card-a'))!.runId,
      'run-3',
    );
    await store.delete(projectId: 'project-a', cardId: 'card-a');
    expect(
      await store.read(projectId: 'project-a', cardId: 'card-a'),
      isNull,
    );
    expect(
      (await store.read(projectId: 'project-a', cardId: 'card-b'))!.runId,
      'run-2',
    );
  });
}
