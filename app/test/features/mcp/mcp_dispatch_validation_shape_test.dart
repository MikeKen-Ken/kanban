import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_pending_store.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_validation_shape.dart';

DispatchVerificationCommand _command({
  String executable = 'flutter',
  List<String> args = const ['test', 'a_test.dart'],
  String cwd = '.',
  int expectedExitCode = 0,
}) =>
    DispatchVerificationCommand(
      executable: executable,
      args: args,
      cwd: cwd,
      expectedExitCode: expectedExitCode,
    );

DispatchValidationResult _result({
  String executable = 'flutter',
  List<String> args = const ['test', 'a_test.dart'],
  String cwd = '.',
  int exitCode = 0,
  bool timedOut = false,
}) =>
    DispatchValidationResult(
      commandSummary: '$executable ${args.join(' ')}',
      executable: executable,
      args: args,
      cwd: cwd,
      exitCode: exitCode,
      durationMs: 12,
      timedOut: timedOut,
    );

void main() {
  final first = _command();
  final second = _command(args: const ['test', 'b_test.dart']);

  test('全部通过时结果必须与声明等长', () {
    expect(
      dispatchValidationShapeError(
        isManual: false,
        commands: [first, second],
        results: [
          _result(),
          _result(args: const ['test', 'b_test.dart']),
        ],
      ),
      isNull,
    );
    expect(
      dispatchValidationShapeError(
        isManual: false,
        commands: [first, second],
        results: [_result()],
      ),
      '验证结果未覆盖全部声明命令',
    );
  });

  test('允许首条失败的 fail-fast 前缀', () {
    expect(
      dispatchValidationShapeError(
        isManual: false,
        commands: [first, second],
        results: [_result(exitCode: 1)],
      ),
      isNull,
    );
    expect(
      dispatchValidationShapeError(
        isManual: false,
        commands: [first, second],
        results: [_result(timedOut: true, exitCode: 124)],
      ),
      isNull,
    );
  });

  test('拒绝空结果、过长结果和命令身份不一致', () {
    expect(
      dispatchValidationShapeError(
        isManual: false,
        commands: [first],
        results: const [],
      ),
      '验证结果数量与声明命令不一致',
    );
    expect(
      dispatchValidationShapeError(
        isManual: false,
        commands: [first],
        results: [_result(), _result(args: const ['test', 'b_test.dart'])],
      ),
      '验证结果数量与声明命令不一致',
    );
    expect(
      dispatchValidationShapeError(
        isManual: false,
        commands: [first],
        results: [_result(args: const ['test', 'other_test.dart'])],
      ),
      '验证结果与第 1 条声明命令不一致',
    );
  });

  test('人工验证不得附带命令结果', () {
    expect(
      dispatchValidationShapeError(
        isManual: true,
        commands: const [],
        results: const [],
      ),
      isNull,
    );
    expect(
      dispatchValidationShapeError(
        isManual: true,
        commands: const [],
        results: [_result()],
      ),
      '人工验证声明不应附带命令结果',
    );
  });
}
