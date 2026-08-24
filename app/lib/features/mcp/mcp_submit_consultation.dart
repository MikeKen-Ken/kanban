import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_submit_for_verify.dart';
import 'mcp_tool_results.dart';

/// 将咨询答复追加到现有备注；答复为空时由调用方提前拒绝。
String appendConsultationResponse(
    String? description, String responseMarkdown) {
  final existing = description?.trimRight() ?? '';
  final response = responseMarkdown.trim();
  if (existing.isEmpty) return response;
  return '$existing\n\n$response';
}

/// 追加咨询答复并移入「待验证」；移列失败时恢复原备注。
Future<CallToolResult> mcpSubmitConsultation(
  BoardController controller, {
  required String cardId,
  required String responseMarkdown,
  String? projectId,
}) async {
  final response = responseMarkdown.trim();
  if (response.isEmpty) {
    return mcpErrorResult('responseMarkdown cannot be empty');
  }

  final located = await resolveMcpProjectIdForCard(
    controller,
    cardId: cardId,
    projectId: projectId,
  );
  if (located.error != null) return located.error!;

  return runMcpForProject(controller, located.projectId!,
      (resolvedProjectId) async {
    final columnId = controller.findColumnIdForCard(cardId) ?? located.columnId;
    final card = controller.findCardById(cardId);
    if (columnId == null || card == null) {
      return mcpErrorResult('Card not found: $cardId');
    }
    if (!card.labels.contains('consultation')) {
      return mcpErrorResult('The card does not have the consultation label');
    }

    final originalDescription = card.description;
    final description = appendConsultationResponse(
      originalDescription,
      response,
    );
    final updateError = await controller.updateCardFull(
      columnId,
      cardId,
      description: description,
    );
    if (updateError != null) return mcpErrorResult(updateError);

    final submitted = await mcpSubmitCardForVerify(
      controller,
      cardId: cardId,
      projectId: resolvedProjectId,
    );
    if (submitted.isError == true) {
      final rollbackColumnId =
          controller.findColumnIdForCard(cardId) ?? columnId;
      await controller.updateCardFull(
        rollbackColumnId,
        cardId,
        description: originalDescription,
        clearDescription: originalDescription == null,
      );
      return submitted;
    }

    final text = submitted.content.whereType<TextContent>().first.text;
    final payload = jsonDecode(text) as Map<String, dynamic>;
    return mcpJsonResult({
      'ok': true,
      'cardId': cardId,
      'projectId': resolvedProjectId,
      'responseAppended': true,
      'toColumnId': payload['toColumnId'],
      'alreadyInVerifyColumn': payload['alreadyInVerifyColumn'],
    });
  });
}
