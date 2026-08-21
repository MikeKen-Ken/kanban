import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import 'agent_dispatch_registry.dart';
import 'agent_dispatch_service.dart';
import 'agent_interaction.dart';
import 'agent_interaction_prompt.dart';
import 'card_agent_follow_up_panel.dart';

class CardAgentConversationSection extends StatelessWidget {
  const CardAgentConversationSection({
    required this.cardId,
    Future<void> Function()? onConversationChanged,
    Future<void> Function()? onSubmittedClose,
    super.key,
  }) : onConversationChanged = onConversationChanged ?? onSubmittedClose;

  final String cardId;

  /// 追问增删改写入看板后回调，供卡片详情同步本地验证反馈列表（不关闭详情）。
  final Future<void> Function()? onConversationChanged;

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
          : () {
              showCardAgentConversationDialog(
                context: context,
                cardId: cardId,
                onConversationChanged: onConversationChanged,
              );
            },
      icon: Icon(hasHistory ? Icons.forum : Icons.forum_outlined),
      label: Text(hasHistory ? 'View / ask Agent' : 'Agent conversation'),
    );
  }
}

Future<void> showCardAgentConversationDialog({
  required BuildContext context,
  required String cardId,
  Future<void> Function()? onConversationChanged,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CardAgentConversationDialog(
      cardId: cardId,
      onConversationChanged: onConversationChanged,
    ),
  );
}

class _CardAgentConversationDialog extends StatefulWidget {
  const _CardAgentConversationDialog({
    required this.cardId,
    this.onConversationChanged,
  });

  final String cardId;
  final Future<void> Function()? onConversationChanged;

  @override
  State<_CardAgentConversationDialog> createState() =>
      _CardAgentConversationDialogState();
}

class _CardAgentConversationDialogState
    extends State<_CardAgentConversationDialog> {
  final _input = TextEditingController();
  final _selectedFollowUpIds = <String>{};
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
    if (!mounted) return;
    final live = _board.findCardById(widget.cardId);
    final validIds = {
      for (final item in agentFollowUpFeedbackItems(
        live?.verificationFeedback ?? const [],
      ))
        item.id,
    };
    _selectedFollowUpIds.removeWhere((id) => !validIds.contains(id));
    setState(() {});
  }

  @override
  void dispose() {
    _board.removeListener(_refresh);
    _service.removeInteractionListener(_refresh);
    _input.dispose();
    super.dispose();
  }

  Future<void> _notifyConversationChanged() async {
    final callback = widget.onConversationChanged;
    if (callback == null) return;
    await callback();
  }

  Future<void> _closeDialog({bool notify = true}) async {
    if (!mounted) {
      if (notify) await _notifyConversationChanged();
      return;
    }
    Navigator.of(context, rootNavigator: true).pop();
    if (notify) await _notifyConversationChanged();
  }

  Future<void> _onBarrierTap() async {
    if (_sending) return;
    if (_input.text.trim().isEmpty) {
      await _closeDialog();
      return;
    }
    // 先关闭界面，再在后台完成持久化，避免空白处点击一直等待磁盘写入。
    await _send(closeDialogImmediately: true);
  }

  Future<void> _send({bool closeDialogImmediately = false}) async {
    final text = _input.text.trim();
    if (_sending || text.isEmpty) return;
    // 提前捕获：立即关对话框后 State 可能已 dispose，仍需通知详情刷新。
    final onChanged = widget.onConversationChanged;
    setState(() => _sending = true);
    if (closeDialogImmediately && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    try {
      final pending = _service.pendingInteraction;
      if (pending?.cardId == widget.cardId) {
        final sent = await _service.submitInteractionReply(text);
        if (!sent) {
          if (mounted) {
            showAppSnackBar(context,
                message:
                    'Failed to send reply; confirm that Worker is still running');
          }
          return;
        }
      } else {
        final columnId = _board.findColumnIdForCard(widget.cardId);
        final card = _board.findCardById(widget.cardId);
        if (columnId == null || card == null) {
          throw StateError('Card not found');
        }
        final feedback = ChecklistItem(
          id: const Uuid().v4(),
          text: '$agentFollowUpFeedbackPrefix$text',
        );
        final error = await _board.updateCardFull(
          columnId,
          widget.cardId,
          verificationFeedback: [...card.verificationFeedback, feedback],
        );
        if (error != null) throw StateError(error);
        final live = _board.findCardById(widget.cardId);
        final markdown = appendAgentConversationUserReply(
          live?.agentConversationMarkdown,
          text,
        );
        final historyError =
            await _board.setCardAgentConversation(widget.cardId, markdown);
        if (historyError != null) throw StateError(historyError);
      }
      if (mounted) {
        _input.clear();
        if (!closeDialogImmediately) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
      await onChanged?.call();
    } catch (error) {
      if (mounted) showAppSnackBar(context, message: 'Send failed: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _persistFollowUpFeedbackRemoval(Set<String> removeIds) async {
    final columnId = _board.findColumnIdForCard(widget.cardId);
    final card = _board.findCardById(widget.cardId);
    if (columnId == null || card == null || removeIds.isEmpty) return;

    final removedBodies = <String>[];
    final nextFeedback = <ChecklistItem>[];
    for (final item in card.verificationFeedback) {
      if (!removeIds.contains(item.id)) {
        nextFeedback.add(item);
        continue;
      }
      final body = agentFollowUpFeedbackBody(item.text);
      if (body != null) removedBodies.add(body);
    }
    if (removedBodies.isEmpty &&
        nextFeedback.length == card.verificationFeedback.length) {
      return;
    }

    final error = await _board.updateCardFull(
      columnId,
      widget.cardId,
      verificationFeedback: nextFeedback,
    );
    if (error != null) throw StateError(error);
    var markdown =
        _board.findCardById(widget.cardId)?.agentConversationMarkdown ?? '';
    for (final body in removedBodies) {
      markdown = removeAgentConversationUserReply(markdown, body);
    }
    final historyError =
        await _board.setCardAgentConversation(widget.cardId, markdown);
    if (historyError != null) throw StateError(historyError);
    _selectedFollowUpIds.removeWhere(removeIds.contains);
    await _notifyConversationChanged();
  }

  Future<void> _deleteSelectedFollowUps() async {
    if (_sending || _selectedFollowUpIds.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _persistFollowUpFeedbackRemoval(
        Set<String>.from(_selectedFollowUpIds),
      );
    } catch (error) {
      if (mounted) {
        showAppSnackBar(context, message: 'Delete follow-up failed: $error');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _editFollowUp(String id) async {
    if (_sending) return;
    final columnId = _board.findColumnIdForCard(widget.cardId);
    final card = _board.findCardById(widget.cardId);
    if (columnId == null || card == null) return;
    final current =
        card.verificationFeedback.where((item) => item.id == id).firstOrNull;
    final oldBody =
        current == null ? null : agentFollowUpFeedbackBody(current.text);
    if (current == null || oldBody == null) return;

    final controller = TextEditingController(text: oldBody);
    final nextBody = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit follow-up'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Follow-up text',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || nextBody == null) return;
    if (nextBody == oldBody) return;

    setState(() => _sending = true);
    try {
      if (nextBody.isEmpty) {
        await _persistFollowUpFeedbackRemoval({id});
        return;
      }
      final nextFeedback = [
        for (final item in card.verificationFeedback)
          if (item.id == id)
            item.copyWith(text: '$agentFollowUpFeedbackPrefix$nextBody')
          else
            item,
      ];
      final error = await _board.updateCardFull(
        columnId,
        widget.cardId,
        verificationFeedback: nextFeedback,
      );
      if (error != null) throw StateError(error);
      final markdown = replaceAgentConversationUserReply(
        _board.findCardById(widget.cardId)?.agentConversationMarkdown,
        oldBody,
        nextBody,
      );
      final historyError =
          await _board.setCardAgentConversation(widget.cardId, markdown);
      if (historyError != null) throw StateError(historyError);
      await _notifyConversationChanged();
    } catch (error) {
      if (mounted) {
        showAppSnackBar(context, message: 'Edit follow-up failed: $error');
      }
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

  Future<void> _openMarkdownDirectory() async {
    final card = _board.findCardById(widget.cardId);
    final columnId = _board.findColumnIdForCard(widget.cardId);
    final file = card?.fileAttachments
        .where(
          (attachment) =>
              attachment.fileName == KanbanCard.agentConversationFileName,
        )
        .firstOrNull;
    if (columnId == null || file == null) return;
    final error = await _board.openCardFileAttachmentDirectory(
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
    final followUps = agentFollowUpFeedbackItems(
      card?.verificationFeedback ?? const [],
    );
    final hasMarkdownFile = card?.fileAttachments.any(
          (attachment) =>
              attachment.fileName == KanbanCard.agentConversationFileName,
        ) ??
        false;
    final pending = _service.pendingInteraction;
    final waiting = pending?.cardId == widget.cardId;
    final size = MediaQuery.sizeOf(context);
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              key: const ValueKey('card-agent-conversation-barrier'),
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _onBarrierTap(),
            ),
          ),
          AlertDialog(
            title: Text(waiting
                ? 'Agent is waiting for a reply'
                : 'Agent conversation'),
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
                          ? const Center(child: Text('No conversation history'))
                          : Markdown(
                              data: history,
                              selectable: true,
                              padding: const EdgeInsets.all(16),
                            ),
                    ),
                  ),
                  if (!waiting)
                    CardAgentFollowUpPanel(
                      items: followUps,
                      selectedIds: _selectedFollowUpIds,
                      enabled: !_sending,
                      onToggleSelected: (id) {
                        setState(() {
                          if (_selectedFollowUpIds.contains(id)) {
                            _selectedFollowUpIds.remove(id);
                          } else {
                            _selectedFollowUpIds.add(id);
                          }
                        });
                      },
                      onEdit: _editFollowUp,
                      onDeleteSelected: _deleteSelectedFollowUps,
                    ),
                  const SizedBox(height: 12),
                  if (waiting && pending != null)
                    Flexible(
                      child: SingleChildScrollView(
                        child: AgentInteractionPrompt(
                          event: pending,
                          onReply: (text) async {
                            final onChanged = widget.onConversationChanged;
                            final sent = await _service.submitInteractionReply(
                              text,
                            );
                            if (!sent && mounted) {
                              showAppSnackBar(
                                context,
                                message:
                                    'Failed to send reply; confirm that Worker is still running',
                              );
                              return false;
                            }
                            if (sent) {
                              if (mounted) {
                                _input.clear();
                                Navigator.of(context, rootNavigator: true)
                                    .pop();
                              }
                              await onChanged?.call();
                            }
                            return sent;
                          },
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      'Submitting a follow-up writes to synced Markdown and moves the card to Rework; the next dispatch continues it.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('card-agent-conversation-input'),
                      controller: _input,
                      enabled: !_sending,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Add constraints or ask a follow-up…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (hasMarkdownFile)
                OutlinedButton.icon(
                  key: const ValueKey(
                    'card-agent-conversation-open-markdown-directory',
                  ),
                  onPressed: _openMarkdownDirectory,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Open containing folder'),
                ),
              if (hasMarkdownFile)
                OutlinedButton.icon(
                  key: const ValueKey('card-agent-conversation-open-markdown'),
                  onPressed: _openMarkdownFile,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open Markdown file'),
                ),
              TextButton(
                onPressed: _sending ? null : () => _closeDialog(),
                child: const Text('Close'),
              ),
              if (!waiting)
                FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send, size: 18),
                  label: Text(_sending ? 'Sending…' : 'Submit follow-up'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
