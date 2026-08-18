import 'package:flutter/material.dart';

/// 卡片详情中的 Git 提交号输入。
class CardDetailCommitRefSection extends StatelessWidget {
  const CardDetailCommitRefSection({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('提交号', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            hintText: 'Git 短哈希（7 位；完整 hash 保存时会自动缩短）',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
        ),
      ],
    );
  }
}
