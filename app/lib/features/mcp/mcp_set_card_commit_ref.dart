import 'package:mcp_dart/mcp_dart.dart';

import '../../common/git_commit_ref.dart';
import '../../controllers/board_controller.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

/// 解析并写入/清除卡片提交号；成功时返回写入值（清除时为 null）。
Future<({String? value, String? error})> applyCardCommitRef(
  BoardController controller, {
  required String columnId,
  required String cardId,
  String? commitRef,
  bool clearCommitRef = false,
}) async {
  final normalized = mcpTrimmedString(commitRef);
  final shouldClear = clearCommitRef || (normalized?.isEmpty ?? false);
  if (!shouldClear && normalized == null) {
    return (value: null, error: 'commitRef 不能为空（或传 clearCommitRef=true 清除）');
  }
  final stored =
      shouldClear ? null : abbreviateGitCommitRef(normalized!);

  final updateError = await controller.updateCardFull(
    columnId,
    cardId,
    commitRef: stored,
    clearCommitRef: shouldClear,
  );
  if (updateError != null) return (value: null, error: updateError);
  return (value: stored, error: null);
}

/// 写入或清除卡片上的 Git 提交号。
Future<CallToolResult> mcpSetCardCommitRef(
  BoardController controller, {
  required String cardId,
  String? projectId,
  String? commitRef,
  bool clearCommitRef = false,
}) async {
  final located = await resolveMcpProjectIdForCard(
    controller,
    cardId: cardId,
    projectId: projectId,
  );
  if (located.error != null) return located.error!;

  final columnId = located.columnId;
  if (columnId == null) {
    return mcpErrorResult('未找到卡片所在列：$cardId');
  }

  return runMcpForProject(controller, located.projectId!, (resolvedProjectId) async {
    final applied = await applyCardCommitRef(
      controller,
      columnId: columnId,
      cardId: cardId,
      commitRef: commitRef,
      clearCommitRef: clearCommitRef,
    );
    if (applied.error != null) return mcpErrorResult(applied.error!);

    final actualColumnId =
        controller.findColumnIdForCard(cardId) ?? columnId;
    return mcpJsonResult({
      'ok': true,
      'cardId': cardId,
      'columnId': actualColumnId,
      'projectId': resolvedProjectId,
      'commitRef': applied.value,
    });
  });
}
