import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'quick_capture_draft.dart';
import 'quick_capture_parser.dart';

Future<QuickCaptureDraft?> showQuickCaptureDialog(BuildContext context) {
  return showDialog<QuickCaptureDraft>(
    context: context,
    builder: (_) => const _QuickCaptureDialog(),
  );
}

class _QuickCaptureDialog extends StatefulWidget {
  const _QuickCaptureDialog();

  @override
  State<_QuickCaptureDialog> createState() => _QuickCaptureDialogState();
}

class _QuickCaptureDialogState extends State<_QuickCaptureDialog> {
  final _controller = TextEditingController();
  QuickCaptureDraft _draft = const QuickCaptureDraft(title: '');

  @override
  void initState() {
    super.initState();
    _controller.addListener(_parse);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_parse)
      ..dispose();
    super.dispose();
  }

  void _parse() {
    setState(() => _draft = parseQuickCapture(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('快速添加'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '任务标题 #标签 !高 @进行中 明天',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            Text(
              '支持 #标签、!高/!中/!低、@列名、今天/明天/后天/下周',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_draft.title.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (_draft.columnName != null)
                    Chip(label: Text('列：${_draft.columnName}')),
                  if (_draft.priority != null)
                    Chip(label: Text('优先级：${_draft.priority!.name}')),
                  if (_draft.dueDate != null)
                    Chip(
                      label: Text(
                        '到期：${DateFormat.yMMMd('zh_CN').format(_draft.dueDate!)}',
                      ),
                    ),
                  for (final label in _draft.labels)
                    Chip(label: Text('#$label')),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _draft.title.trim().isEmpty ? null : _submit,
          child: const Text('添加'),
        ),
      ],
    );
  }

  void _submit() {
    if (_draft.title.trim().isEmpty) return;
    Navigator.pop(context, _draft);
  }
}
