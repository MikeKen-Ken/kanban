import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'description_markdown_preview.dart';

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
  late final FocusNode _descFocusNode;

  @override
  void initState() {
    super.initState();
    _previewMarkdown = widget.initialPreview;
    _descFocusNode = FocusNode(onKeyEvent: _onDescKeyEvent);
  }

  @override
  void dispose() {
    _descFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onDescKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      final value = widget.controller.value;
      if (value.composing.isValid) {
        widget.controller.value =
            value.copyWith(composing: TextRange.empty);
      }
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
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
              ? DescriptionMarkdownPreview(
                  data: widget.controller.text,
                  scrollable: true,
                  expand: true,
                )
              : TextField(
                  key: const ValueKey('card-detail-desc-expanded'),
                  controller: widget.controller,
                  focusNode: _descFocusNode,
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
