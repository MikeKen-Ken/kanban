import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import 'agent_dispatch_registry.dart';
import 'agent_dispatch_service.dart';

class CardAgentConversationSection extends StatelessWidget {
  const CardAgentConversationSection({
    required this.cardId,
    super.key,
  });

  final String cardId;

  @override
  Widget build(BuildContext context) {
    final board = context.watch<BoardController>();
    final card = board.findCardById(cardId);
    final hasHistory =
        card?.agentConversationMarkdown?.trim().isNotEmpty ?? false;
    return OutlinedButton.icon(
      key: const ValueKey('card-agent-conversation-open'),
      onPressed: card == null
          ? null
          : () => showCardAgentConversationDialog(
                context: context,
                cardId: cardId,
              ),
      icon: Icon(hasHistory ? Icons.forum : Icons.forum_outlined),
      label: Text(hasHistory ? '查看 / 追问 Agent' : 'Agent 对话'),
    );
  }
}

Future<void> showCardAgentConversationDialog({
  required BuildContext context,
  required String cardId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CardAgentConversationDialog(cardId: cardId),
  );
}

class _CardAgentConversationDialog extends StatefulWidget {
  const _CardAgentConversationDialog({required this.cardId});

  final String cardId;

  @override
  State<_CardAgentConversationDialog> createState() =>
      _CardAgentConversationDialogState();
}

class _CardAgentConversationDialogState
    extends State<_CardAgentConversationDialog> {
  final _input = TextEditingController();
  late BoardController _board;
  late AgentDispatchService _service;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _board = context.read<BoardController>();
    final projectId =
        _board.activeProjectId ?? _board.board?.id ?? 'unknown-project';
    _service = AgentDispatchRegistry.instance.forProject(projectId);
    _board.addListener(_refresh);
    _service.addInteractionListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _board.removeListener(_refresh);
    _service.removeInteractionListener(_refresh);
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final pending = _service.pendingInteraction;
      if (pending?.cardId == widget.cardId) {
        final sent = await _service.submitInteractionReply(text);
        if (!sent && mounted) {
          showAppSnackBar(context, message: '回复发送失败，请确认 Worker 仍在运行');
          return;
        }
      } else {
        final columnId = _board.findColumnIdForCard(widget.cardId);
        final card = _board.findCardById(widget.cardId);
        if (columnId == null || card == null) {
          throw StateError('卡片不存在');
        }
        final feedback = ChecklistItem(
          id: const Uuid().v4(),
          text: 'Agent 追问：$text',
        );
        final error = await _board.updateCardFull(
          columnId,
          widget.cardId,
          verificationFeedback: [...card.verificationFeedback, feedback],
        );
        if (error != null) throw StateError(error);
        final live = _board.findCardById(widget.cardId);
        final markdown = _appendUserMessage(
          live?.agentConversationMarkdown,
          text,
        );
        final historyError =
            await _board.setCardAgentConversation(widget.cardId, markdown);
        if (historyError != null) throw StateError(historyError);
        if (mounted) {
          showAppSnackBar(
            context,
            message: '追问已写入对话并加入待返工；下次调度会继续读取上下文',
          );
        }
      }
      _input.clear();
    } catch (error) {
      if (mounted) showAppSnackBar(context, message: '发送失败：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openMarkdownFile() async {
    final card = _board.findCardById(widget.cardId);
    final columnId = _board.findColumnIdForCard(widget.cardId);
    final file = card?.fileAttachments
        .where(
          (attachment) =>
              attachment.fileName == KanbanCard.agentConversationFileName,
        )
        .firstOrNull;
    if (columnId == null || file == null) return;
    final error = await _board.openCardFileAttachment(
      columnId,
      widget.cardId,
      file.id,
    );
    if (error != null && mounted) {
      showAppSnackBar(context, message: error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _board.findCardById(widget.cardId);
    final history = card?.agentConversationMarkdown?.trim() ?? '';
    final hasMarkdownFile = card?.fileAttachments.any(
          (attachment) =>
              attachment.fileName == KanbanCard.agentConversationFileName,
        ) ??
        false;
    final pending = _service.pendingInteraction;
    final waiting = pending?.cardId == widget.cardId;
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Text(waiting ? 'Agent 等待回复' : 'Agent 对话'),
      content: SizedBox(
        width: (size.width - 80).clamp(420.0, 860.0).toDouble(),
        height: (size.height - 180).clamp(360.0, 720.0).toDouble(),
        child: Column(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: history.isEmpty
                    ? const Center(child: Text('暂无对话记录'))
                    : Markdown(
                        data: history,
                        selectable: true,
                        padding: const EdgeInsets.all(16),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              waiting
                  ? '当前卡片已暂停；回复后会在同一 Agent 会话继续。'
                  : '提交追问会写入同步 Markdown，并把卡片加入待返工；下次调度继续处理。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('card-agent-conversation-input'),
              controller: _input,
              enabled: !_sending,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: waiting ? '回复 Agent…' : '补充约束或继续追问…',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _send(),
            ),
          ],
        ),
      ),
      actions: [
        if (hasMarkdownFile)
          OutlinedButton.icon(
            onPressed: _openMarkdownFile,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('打开 Markdown 文件'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: const Icon(Icons.send, size: 18),
          label: Text(_sending ? '发送中…' : (waiting ? '回复' : '提交追问')),
        ),
      ],
    );
  }
}

String _appendUserMessage(String? current, String text) {
  final buffer = StringBuffer((current ?? '').trimRight());
  if (buffer.isNotEmpty) buffer.write('\n\n');
  buffer
    ..writeln('### 用户')
    ..write(text.trim());
  return '${buffer.toString().trimRight()}\n';
}
