import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// 全屏备注编辑/预览，复用外部 [controller]，关闭后内容自动同步回详情页。
Future<void> showDescriptionExpandDialog({
  required BuildContext context,
  required TextEditingController controller,
  bool initialPreview = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => DescriptionExpandDialog(
      controller: controller,
      initialPreview: initialPreview,
    ),
  );
}

/// 接近全屏的备注放大视图。
class DescriptionExpandDialog extends StatefulWidget {
  const DescriptionExpandDialog({
    super.key,
    required this.controller,
    this.initialPreview = false,
  });

  final TextEditingController controller;
  final bool initialPreview;

  @override
  State<DescriptionExpandDialog> createState() =>
      _DescriptionExpandDialogState();
}

class _DescriptionExpandDialogState extends State<DescriptionExpandDialog> {
  late bool _previewMarkdown;

  @override
  void initState() {
    super.initState();
    _previewMarkdown = widget.initialPreview;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '缩小',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_fullscreen),
          ),
          title: const Text('备注'),
          actions: [
            TextButton(
              onPressed: () => setState(
                () => _previewMarkdown = !_previewMarkdown,
              ),
              child: Text(_previewMarkdown ? '编辑' : '预览'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _previewMarkdown
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: MarkdownBody(
                      data: widget.controller.text.isEmpty
                          ? '_暂无备注_'
                          : widget.controller.text,
                      onTapLink: (text, href, title) {
                        if (href == null) return;
                        launchUrl(
                          Uri.parse(href),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ),
                )
              : TextField(
                  key: const ValueKey('card-detail-desc-expanded'),
                  controller: widget.controller,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '支持 Markdown…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
        ),
      ),
    );
  }
}
