import 'package:flutter/material.dart';

import '../../common/app_snack_bar.dart';
import 'agent_interaction.dart';

/// 运行中 ask_user 提问：在最近运行区展示选项菜单，并可弹出选择窗口。
class AgentInteractionPrompt extends StatefulWidget {
  const AgentInteractionPrompt({
    required this.event,
    required this.onReply,
    this.autoShowDialog = false,
    super.key,
  });

  final AgentInteractionEvent event;
  final Future<bool> Function(String text) onReply;
  final bool autoShowDialog;

  @override
  State<AgentInteractionPrompt> createState() => _AgentInteractionPromptState();
}

class _AgentInteractionPromptState extends State<AgentInteractionPrompt> {
  final _custom = TextEditingController();
  var _sending = false;
  String? _shownDialogRequestId;

  @override
  void initState() {
    super.initState();
    _scheduleDialog();
  }

  @override
  void didUpdateWidget(covariant AgentInteractionPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.requestId != widget.event.requestId) {
      _shownDialogRequestId = null;
      _custom.clear();
      _scheduleDialog();
    }
  }

  void _scheduleDialog() {
    if (!widget.autoShowDialog || widget.event.choices.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final requestId = widget.event.requestId;
      if (requestId == null || requestId == _shownDialogRequestId) return;
      _shownDialogRequestId = requestId;
      _openChoiceDialog();
    });
  }

  Future<void> _openChoiceDialog() async {
    final event = widget.event;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          key: const ValueKey('agent-dispatch-interaction-dialog'),
          title: const Text('Agent needs your choice'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(event.text),
                if (event.choices.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (var i = 0; i < event.choices.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: FilledButton.tonal(
                        key: ValueKey(
                          'agent-dispatch-interaction-dialog-choice-$i',
                        ),
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _submit(event.choices[i]);
                        },
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('${i + 1}. ${event.choices[i]}'),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Reply later in the run log'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submit(String text) async {
    final reply = text.trim();
    if (_sending || reply.isEmpty) return;
    setState(() => _sending = true);
    try {
      final sent = await widget.onReply(reply);
      if (!sent && mounted) {
        showAppSnackBar(context,
            message:
                'Failed to send reply; confirm that Worker is still running');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('agent-dispatch-interaction-prompt'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: _PromptBody(
        event: widget.event,
        custom: _custom,
        sending: _sending,
        onChoice: _submit,
        onCustom: () => _submit(_custom.text),
        onOpenMenu: widget.event.choices.isEmpty ? null : _openChoiceDialog,
      ),
    );
  }
}

class _PromptBody extends StatelessWidget {
  const _PromptBody({
    required this.event,
    required this.custom,
    required this.sending,
    required this.onChoice,
    required this.onCustom,
    this.onOpenMenu,
  });

  final AgentInteractionEvent event;
  final TextEditingController custom;
  final bool sending;
  final ValueChanged<String> onChoice;
  final VoidCallback onCustom;
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.touch_app_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                event.choices.isEmpty
                    ? 'Agent is waiting for a reply'
                    : 'Agent is waiting for your choice',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (onOpenMenu != null)
              TextButton(
                key: const ValueKey('agent-dispatch-interaction-open-menu'),
                onPressed: sending ? null : onOpenMenu,
                child: const Text('Open choices'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(event.text, style: theme.textTheme.bodyMedium),
        if (event.choices.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < event.choices.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: FilledButton.tonal(
                key: ValueKey('agent-dispatch-interaction-choice-$i'),
                onPressed: sending ? null : () => onChoice(event.choices[i]),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${i + 1}. ${event.choices[i]}'),
                ),
              ),
            ),
        ],
        const SizedBox(height: 4),
        TextField(
          key: const ValueKey('agent-dispatch-interaction-custom'),
          controller: custom,
          enabled: !sending,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: event.choices.isEmpty
                ? 'Reply to Agent…'
                : 'Or enter another reply…',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) => onCustom(),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const ValueKey('agent-dispatch-interaction-send'),
            onPressed: sending ? null : onCustom,
            icon: const Icon(Icons.send, size: 16),
            label: Text(sending ? 'Sending…' : 'Send reply'),
          ),
        ),
      ],
    );
  }
}
