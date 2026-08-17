import 'dispatch_pending_store.dart';

/// 校验 Worker 上报的验证结果。
///
/// 测试已下放给 Agent 会话；Worker 只记账，结果必须为空。
String? dispatchValidationShapeError({
  required bool isManual,
  required List<DispatchValidationResult> results,
}) {
  if (results.isNotEmpty) {
    return isManual
        ? '人工验证声明不应附带命令结果'
        : '验证已改由 Agent 会话内完成，Worker 不应上报命令结果';
  }
  return null;
}
