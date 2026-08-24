import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_pending_store.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_validation_shape.dart';

DispatchValidationResult _result() => const DispatchValidationResult(
      commandSummary: 'flutter test a_test.dart',
      executable: 'flutter',
      args: ['test', 'a_test.dart'],
      cwd: '.',
      exitCode: 0,
      durationMs: 12,
      timedOut: false,
    );

void main() {
  test('会话内验证与人工验证都只接受空结果', () {
    expect(
      dispatchValidationShapeError(isManual: false, results: const []),
      isNull,
    );
    expect(
      dispatchValidationShapeError(isManual: true, results: const []),
      isNull,
    );
  });

  test('拒绝 Worker 上报命令结果', () {
    expect(
      dispatchValidationShapeError(isManual: false, results: [_result()]),
      'Verification now runs in the Agent session; the Worker must not report command results',
    );
    expect(
      dispatchValidationShapeError(isManual: true, results: [_result()]),
      'A manual verification declaration must not include command results',
    );
  });
}
