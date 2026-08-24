import 'package:flutter/material.dart';

import 'card_template.dart';
import 'create_card_choice.dart';

/// 弹出单一列表：第一项「空白」（默认选中），其下为已有模板；可删除模板。
Future<CreateCardChoice?> showCreateCardChoiceSheet({
  required BuildContext context,
  required String columnTitle,
  required List<CardTemplate> templates,
  required Future<void> Function(String templateId) onDeleteTemplate,
}) {
  return showModalBottomSheet<CreateCardChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _CreateCardChoiceSheet(
      columnTitle: columnTitle,
      initialTemplates: templates,
      onDeleteTemplate: onDeleteTemplate,
    ),
  );
}

class _CreateCardChoiceSheet extends StatefulWidget {
  const _CreateCardChoiceSheet({
    required this.columnTitle,
    required this.initialTemplates,
    required this.onDeleteTemplate,
  });

  final String columnTitle;
  final List<CardTemplate> initialTemplates;
  final Future<void> Function(String templateId) onDeleteTemplate;

  @override
  State<_CreateCardChoiceSheet> createState() => _CreateCardChoiceSheetState();
}

class _CreateCardChoiceSheetState extends State<_CreateCardChoiceSheet> {
  /// 空白项的哨兵值（模板 id 为 UUID，不会冲突）。
  static const _blankValue = '';

  late List<CardTemplate> _templates;
  String _selectedValue = _blankValue;

  @override
  void initState() {
    super.initState();
    _templates = List<CardTemplate>.of(widget.initialTemplates);
  }

  Future<void> _deleteTemplate(CardTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text(
            '“${template.name}” will be permanently deleted and cannot be restored.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await widget.onDeleteTemplate(template.id);
    if (!mounted) return;

    setState(() {
      _templates = removeCardTemplateById(_templates, template.id);
      if (_selectedValue == template.id) {
        _selectedValue = _blankValue;
      }
    });
  }

  void _confirm() {
    Navigator.pop(
      context,
      _selectedValue == _blankValue
          ? const CreateCardChoice.blank()
          : CreateCardChoice.fromTemplate(_selectedValue),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Add card to “${widget.columnTitle}”',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: RadioGroup<String>(
                groupValue: _selectedValue,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedValue = value);
                },
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const RadioListTile<String>(
                      value: _blankValue,
                      secondary: Icon(Icons.note_add_outlined),
                      title: Text('Blank card'),
                      subtitle: Text('Open details after creating'),
                    ),
                    for (final template in _templates)
                      RadioListTile<String>(
                        value: template.id,
                        secondary: IconButton(
                          tooltip: 'Delete template',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteTemplate(template),
                        ),
                        title: Text(template.name),
                        subtitle: template.title.isEmpty
                            ? null
                            : Text(
                                template.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _confirm,
                  child: const Text('Create'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
