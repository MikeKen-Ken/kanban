import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_ready_to_submit.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_report_shell_span.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_shell_spans.dart';
import 'package:kanban/features/mcp/mcp_dispatch_card_gate.dart';
import 'package:kanban/features/mcp/mcp_submission_snapshot_store.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('验证命令识别与结束时间', () {
    test('flutter test 与夹在 format 后的测试都算验证', () {
      expect(
        isDispatchVerificationCommand(
          'dart format a.dart; flutter test test/a_test.dart',
        ),
        isTrue,
      );
      expect(
        isDispatchVerificationCommand(
          'dart format a.dart; flutter analyze',
        ),
        isTrue,
      );
      expect(
        isDispatchVerificationCommand(
          'node --test src/retry.test.ts',
        ),
        isTrue,
      );
      expect(isDispatchVerificationCommand('git status --short'), isFalse);
      expect(isDispatchVerificationCommand('dart format a.dart'), isFalse);
    });

    test('SDK 换行 call_id 规范成单行', () {
      expect(
        normalizeDispatchCallId('call_abc\nfc_xyz'),
        'call_abc_fc_xyz',
      );
      expect(normalizeDispatchCallId('  '), '');
    });

    test('SDK 提前 completed 时用 startedAt+executionTime', () {
      const span = DispatchShellSpan(
        callId: 'shell-1',
        command: 'flutter test a_test.dart',
        startedAtMs: 1000,
        endedAtMs: 1331,
        executionTimeMs: 13639,
        exitCode: 0,
      );
      expect(dispatchShellEffectiveEndMs(span), 1000 + 13639);
      expect(
        dispatchReadyBlockedByShells([span], nowMs: 1000 + 1845),
        contains('仍在执行'),
      );
      expect(
        dispatchReadyBlockedByShells([span], nowMs: 1000 + 13639),
        isNull,
      );
    });

    test('node --test 未按其 executionTime 结束时拒绝', () {
      const span = DispatchShellSpan(
        callId: 'call_abc_fc_xyz',
        command: 'node --test src/retry.test.ts',
        startedAtMs: 1000,
        endedAtMs: 1200,
        executionTimeMs: 40000,
        exitCode: 0,
      );
      expect(
        dispatchReadyBlockedByShells([span], nowMs: 1000 + 5000),
        contains('仍在执行'),
      );
    });

    test('测试失败后即使已结束也拒绝', () {
      const span = DispatchShellSpan(
        callId: 'shell-1',
        command: 'flutter test a_test.dart',
        startedAtMs: 0,
        endedAtMs: 20000,
        executionTimeMs: 20000,
        exitCode: 1,
      );
      expect(
        dispatchReadyBlockedByShells([span], nowMs: 21000),
        contains('exitCode=1'),
      );
    });

    test('较新的成功验证覆盖较早失败', () {
      const failed = DispatchShellSpan(
        callId: 'shell-1',
        command:
            'cd app && flutter test test/features/kanban/rework_move_gate_test.dart --name old',
        startedAtMs: 0,
        endedAtMs: 1000,
        executionTimeMs: 1000,
        exitCode: 1,
      );
      const passed = DispatchShellSpan(
        callId: 'shell-2',
        command: 'flutter test test/features/kanban/rework_move_gate_test.dart',
        startedAtMs: 2000,
        endedAtMs: 9000,
        executionTimeMs: 7000,
        exitCode: 0,
      );
      expect(
        dispatchReadyBlockedByShells([failed, passed], nowMs: 10000),
        isNull,
      );
      expect(
        dispatchReadyBlockedByShells([passed, failed], nowMs: 10000),
        isNull,
      );
    });

    test('滞后上报的 cd && 解析失败不得覆盖已通过的 flutter test', () {
      const passed = DispatchShellSpan(
        callId: 'shell-pass',
        command: 'flutter test test/a_test.dart',
        startedAtMs: 1000,
        endedAtMs: 21000,
        executionTimeMs: 20000,
        exitCode: 0,
      );
      const parseFail = DispatchShellSpan(
        callId: 'shell-cd-and',
        command: 'cd app && flutter test test/a_test.dart',
        startedAtMs: 900,
        endedAtMs: 50000,
        executionTimeMs: 80,
        exitCode: 1,
      );
      expect(dispatchShellEffectiveEndMs(parseFail), 900 + 80);
      expect(
        dispatchReadyBlockedByShells([passed, parseFail], nowMs: 50000),
        isNull,
      );
    });

    test('仅有 cd && 短失败时仍拒绝，并提示不要用 &&', () {
      const parseFail = DispatchShellSpan(
        callId: 'shell-cd-and',
        command: 'cd app && flutter test test/a_test.dart',
        startedAtMs: 0,
        endedAtMs: 100,
        executionTimeMs: 80,
        exitCode: 1,
      );
      expect(
        dispatchReadyBlockedByShells([parseFail], nowMs: 1000),
        contains('working_directory'),
      );
    });

    test('flutter test 成功但耗时过短时拒绝', () {
      const span = DispatchShellSpan(
        callId: 'shell-fast',
        command:
            'dart format a.dart; if (\$LASTEXITCODE -ne 0) { exit \$LASTEXITCODE }; '
            'flutter test a_test.dart',
        startedAtMs: 0,
        endedAtMs: 600,
        executionTimeMs: 600,
        exitCode: 0,
      );
      expect(
        dispatchReadyBlockedByShells([span], nowMs: 1000),
        contains('耗时过短'),
      );
    });

    test('无 executionTime 的秒退 flutter test 也拒绝', () {
      const span = DispatchShellSpan(
        callId: 'shell-fast',
        command: 'flutter test test/a_test.dart',
        startedAtMs: 0,
        endedAtMs: 600,
        exitCode: 0,
      );
      expect(dispatchShellObservedDurationMs(span), 600);
      expect(
        dispatchReadyBlockedByShells([span], nowMs: 1000),
        contains('working_directory'),
      );
    });

    test('正常耗时的 flutter test 仍放行', () {
      const span = DispatchShellSpan(
        callId: 'shell-ok',
        command: 'flutter test test/a_test.dart',
        startedAtMs: 0,
        endedAtMs: 8000,
        executionTimeMs: 8000,
        exitCode: 0,
      );
      expect(
        dispatchReadyBlockedByShells([span], nowMs: 9000),
        isNull,
      );
    });

    test('秒退的 flutter analyze 不按测试秒退拦截', () {
      const span = DispatchShellSpan(
        callId: 'analyze',
        command: 'flutter analyze lib/a.dart',
        startedAtMs: 0,
        endedAtMs: 800,
        executionTimeMs: 800,
        exitCode: 0,
      );
      expect(
        dispatchReadyBlockedByShells([span], nowMs: 1000),
        isNull,
      );
    });

    test('无 executionTime 的滞后 cd && 失败也不覆盖成功验证', () {
      const passed = DispatchShellSpan(
        callId: 'shell-pass',
        command: 'flutter test test/a_test.dart',
        startedAtMs: 1000,
        endedAtMs: 21000,
        executionTimeMs: 20000,
        exitCode: 0,
      );
      const parseFail = DispatchShellSpan(
        callId: 'shell-cd-and',
        command: 'cd app && flutter test test/a_test.dart',
        startedAtMs: 900,
        endedAtMs: 50000,
        exitCode: 1,
      );
      expect(
        dispatchReadyBlockedByShells([passed, parseFail], nowMs: 50000),
        isNull,
      );
    });
  });

  group('ready_to_submit 门禁', () {
    final gate = McpDispatchCardGate.instance;
    late Directory tempDir;
    late BoardController controller;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      gate.debugReset();
      DispatchShellSpanStore.debugReset();
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('kanban_shell_span_');
      final prefs = await SharedPreferences.getInstance();
      controller = await BoardController.createForTest(
        prefs: prefs,
        storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
      );
    });

    tearDown(() async {
      gate.debugReset();
      DispatchShellSpanStore.debugReset();
      controller.dispose();
      await Future<void>.delayed(Duration.zero);
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } on FileSystemException {
        // 测试收尾删目录失败可忽略。
      }
    });

    test('Worker 上报未结束的 flutter test 时拒绝 ready_to_submit', () async {
      final clock = <int>[1000];
      final spans = DispatchShellSpanStore(nowMs: () => clock.first);
      final projectId = controller.activeProjectId!;
      final todo =
          controller.board!.columns.firstWhere((item) => item.id == 'todo');
      final cardId = (await controller.addCard(todo.id, '竞态卡'))!;

      gate.beginBatch('worker-a', projectId: projectId);
      expect(
          gate.beginAgentSession('worker-a', sessionId: 'session-a'), isTrue);
      expect(
        gate.authorizePick(projectId, workerToken: 'worker-a'),
        McpDispatchPickPermission.allowed,
      );
      gate.recordPickedCard(
        projectId: projectId,
        cardId: cardId,
        workerToken: 'worker-a',
      );

      await McpSubmissionSnapshotStore().write(
        McpSubmissionSnapshot(
          projectId: projectId,
          cardId: cardId,
          workMode: 'normal',
          suggestedCommitMessage: '竞态卡',
          capturedAt: 1,
        ),
      );

      final command =
          'dart format a.dart; if (\$LASTEXITCODE -eq 0) { flutter test a_test.dart }';
      final reported = await dispatchReportShellSpan(
        workerToken: 'worker-a',
        sessionId: 'session-a',
        callId: 'call-test',
        command: command,
        phase: 'start',
        startedAtMs: 1000,
        store: spans,
      );
      expect(reported.isError, isNot(true));

      final ended = await dispatchReportShellSpan(
        workerToken: 'worker-a',
        sessionId: 'session-a',
        callId: 'call-test',
        command: command,
        phase: 'end',
        startedAtMs: 1000,
        endedAtMs: 1331,
        executionTimeMs: 13639,
        exitCode: 0,
        store: spans,
      );
      expect(ended.isError, isNot(true));

      clock[0] = 1000 + 1845;
      final ready = await dispatchReadyToSubmit(
        controller,
        workerToken: 'worker-a',
        cardId: cardId,
        completedChecklistIds: const [],
        completedFeedbackIds: const [],
        verificationCommands: const [],
        shellSpans: spans,
      );
      expect(ready.isError, isTrue);
      expect(
        ready.content.whereType<TextContent>().first.text,
        contains('仍在执行'),
      );

      clock[0] = 1000 + 13639;
      final accepted = await dispatchReadyToSubmit(
        controller,
        workerToken: 'worker-a',
        cardId: cardId,
        completedChecklistIds: const [],
        completedFeedbackIds: const [],
        verificationCommands: const [],
        shellSpans: spans,
      );
      expect(accepted.isError, isNot(true));
    });
  });
}
