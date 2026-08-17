import 'dispatch_pending_store.dart';

/// 校验 Worker 上报的验证结果是否与声明命令对齐。
///
/// 允许 fail-fast：结果可以短于声明列表，但最后一条必须失败，
/// 避免「前面都过了、后面没跑」被记成验证通过。
String? dispatchValidationShapeError({
  required bool isManual,
  required List<DispatchVerificationCommand> commands,
  required List<DispatchValidationResult> results,
}) {
  if (isManual) {
    return results.isEmpty ? null : '人工验证声明不应附带命令结果';
  }
  if (results.isEmpty || results.length > commands.length) {
    return '验证结果数量与声明命令不一致';
  }
  for (var index = 0; index < results.length; index++) {
    final expected = commands[index];
    final actual = results[index];
    if (actual.executable != expected.executable ||
        !_sameStrings(actual.args, expected.args) ||
        actual.cwd != expected.cwd) {
      return '验证结果与第 ${index + 1} 条声明命令不一致';
    }
  }
  if (results.length < commands.length) {
    final last = results.last;
    final expected = commands[results.length - 1];
    final lastFailed =
        last.timedOut || last.exitCode != expected.expectedExitCode;
    if (!lastFailed) {
      return '验证结果未覆盖全部声明命令';
    }
  }
  return null;
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
