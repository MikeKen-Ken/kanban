import 'package:mcp_dart/mcp_dart.dart';

import '../../controllers/board_controller.dart';
import '../kanban/next_work_card.dart';
import 'mcp_arg_parsers.dart';
import 'mcp_tool_results.dart';

/// 按需拉取本轮工作项；不含附件二进制。
Future<CallToolResult> mcpGetWorkItems(
  BoardController controller, {
  required String cardId,
  String? projectId,
}) async {
  final located = await resolveMcpProjectIdForCard(
    controller,
    cardId: cardId,
    projectId: projectId,
  );
  if (located.error != null) return located.error!;

  return runMcpForProject(controller, located.projectId, (resolvedProjectId) async {
    final card = controller.findCardById(cardId);
    if (card == null) return mcpErrorResult('未找到卡片：$cardId');

    final rework = isReworkWorkMode(card);
    final payload = <String, dynamic>{
      'projectId': resolvedProjectId,
      'cardId': cardId,
      'workMode': rework ? 'rework' : 'normal',
      'workItems': buildCardWorkItems(card),
      'suggestedCommitMessage': buildCardCommitMessage(card),
      'summary': buildCardWorkSummary(card),
    };
    if (card.attachments.isNotEmpty || card.fileAttachments.isNotEmpty) {
      payload['attachmentCount'] = card.attachments.length;
      payload['fileAttachmentCount'] = card.fileAttachments.length;
      payload['attachmentsNote'] =
          '附件仅计数；元数据用 list_card_attachments，二进制用 read_card_attachment 按需读取';
    }
    return mcpJsonResult(payload);
  });
}
