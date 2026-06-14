import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../../settings/column_color_picker.dart';
import '../../utils/ime_guard.dart';
import '../../features/project/project_theme.dart';
import '../attachments/card_attachment_reorder_grid.dart';
import '../attachments/card_attachment_viewer.dart';
import '../attachments/card_image_add_sheet.dart';
import '../attachments/attachment_missing.dart';
import 'kanban_labels.dart';

/// 卡片详情底部弹层：标题、备注、截止日期、优先级、标签、子任务
Future<void> showCardDetailSheet({
  required BuildContext context,
  required String columnId,
  required KanbanCard card,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _CardDetailSheet(columnId: columnId, card: card),
  );
}

class _CardDetailSheet extends StatefulWidget {
  const _CardDetailSheet({required this.columnId, required this.card});

  final String columnId;
  final KanbanCard card;

  @override
  State<_CardDetailSheet> createState() => _CardDetailSheetState();
}

class _CardDetailSheetState extends State<_CardDetailSheet> with ImeGuard {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late BoardController _boardController;
  late bool _completed;
  DateTime? _dueDate;
  late CardPriority _priority;
  late List<String> _labels;
  late List<ChecklistItem> _checklist;
  late List<CardAttachment> _attachments;
  int? _colorValue;
  final _checklistInput = TextEditingController();

  Iterable<TextEditingController> get _textControllers =>
      [_titleController, _descController, _checklistInput];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.card.title);
    _descController = TextEditingController(text: widget.card.description ?? '');
    _completed = widget.card.completed;
    _dueDate = widget.card.dueDate != null
        ? DateTime.fromMillisecondsSinceEpoch(widget.card.dueDate!)
        : null;
    _priority = widget.card.priority;
    _labels = [...widget.card.labels];
    _checklist = [...widget.card.checklist];
    _attachments = [...widget.card.sortedAttachments];
    _colorValue = widget.card.colorValue;
    bindImeGuard(_textControllers);
    _boardController = context.read<BoardController>();
    _boardController.addListener(_onBoardChanged);
  }

  @override
  void dispose() {
    _boardController.removeListener(_onBoardChanged);
    _titleController.dispose();
    _descController.dispose();
    _checklistInput.dispose();
    super.dispose();
  }

  void _onBoardChanged() => deferRebuildIfComposing(_textControllers);

  void _safeSetState(VoidCallback fn) =>
      imeSafeSetState(fn, _textControllers);

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final controller = context.read<BoardController>();
    await controller.updateCardFull(
      widget.columnId,
      widget.card.id,
      title: title,
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      completed: _completed,
      dueDate: _dueDate?.millisecondsSinceEpoch,
      clearDueDate: _dueDate == null,
      priority: _priority,
      labels: _labels,
      checklist: _checklist,
      attachments: _attachments,
      colorValue: _colorValue,
      clearColor: _colorValue == null,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: '选择截止日期',
    );
    if (picked != null && mounted) {
      _safeSetState(() => _dueDate = picked);
    }
  }

  Future<void> _pickCardColor() async {
    final picked = await showColumnColorPicker(
      context: context,
      currentColorValue: _colorValue,
      title: '卡片背景色',
    );
    if (!mounted || picked == _colorValue) return;
    _safeSetState(() => _colorValue = picked);
  }

  void _toggleLabel(String key) {
    _safeSetState(() {
      if (_labels.contains(key)) {
        _labels.remove(key);
      } else {
        _labels.add(key);
      }
    });
  }

  Future<void> _showAddLabelDialog() async {
    final nameController = TextEditingController();
    int labelColor = projectThemeForId(
      _boardController.projectSettings.themeId,
    ).defaultLabelColor.toARGB32();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('新建标签'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '标签名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(labelColor),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final picked = await showColumnColorPicker(
                          context: context,
                          currentColorValue: labelColor,
                          title: '标签颜色',
                          allowDefault: false,
                        );
                        if (picked != null) {
                          setDialogState(() => labelColor = picked);
                        }
                      },
                      child: const Text('选择颜色'),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (nameController.text.trim().isEmpty) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );

    final name = nameController.text.trim();
    nameController.dispose();

    if (result == true && name.isNotEmpty && mounted) {
      final controller = context.read<BoardController>();
      final key = await controller.addCustomLabel(name, labelColor);
      _safeSetState(() => _labels.add(key));
    }
  }

  void _addChecklistItem() {
    final text = _checklistInput.text.trim();
    if (text.isEmpty) return;
    _safeSetState(() {
      _checklist = [
        ..._checklist,
        ChecklistItem(id: const Uuid().v4(), text: text),
      ];
      _checklistInput.clear();
    });
  }

  void _toggleChecklistItem(String id) {
    _safeSetState(() {
      _checklist = _checklist
          .map(
            (item) => item.id == id
                ? item.copyWith(completed: !item.completed)
                : item,
          )
          .toList();
    });
  }

  void _removeChecklistItem(String id) {
    _safeSetState(() {
      _checklist = _checklist.where((item) => item.id != id).toList();
    });
  }

  Future<void> _pickAttachments() async {
    if (_attachments.length >= KanbanCard.maxAttachments) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('每张卡片最多 ${KanbanCard.maxAttachments} 张图片'),
        ),
      );
      return;
    }

    final source = await showCardImageAddSourceSheet(context);
    if (!mounted || source == null) return;

    final controller = context.read<BoardController>();
    final error = await controller.addCardAttachmentsFromSource(
      widget.columnId,
      widget.card.id,
      source,
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    _reloadAttachmentsFromBoard();
  }

  void _reloadAttachmentsFromBoard() {
    final updated = context.read<BoardController>().board?.columns
        .where((col) => col.id == widget.columnId)
        .expand((col) => col.cards)
        .where((card) => card.id == widget.card.id)
        .firstOrNull;
    if (updated != null) {
      _safeSetState(() => _attachments = [...updated.sortedAttachments]);
    }
  }

  Future<void> _removeAttachment(String attachmentId) async {
    await context.read<BoardController>().removeCardAttachment(
          widget.columnId,
          widget.card.id,
          attachmentId,
        );
    if (!mounted) return;
    _safeSetState(() {
      _attachments =
          _attachments.where((item) => item.id != attachmentId).toList();
    });
  }

  Future<void> _setCover(String attachmentId) async {
    await context.read<BoardController>().setCardAttachmentCover(
          widget.columnId,
          widget.card.id,
          attachmentId,
        );
    if (!mounted) return;
    _safeSetState(() {
      final selected = _attachments.firstWhere((a) => a.id == attachmentId);
      final others = _attachments.where((a) => a.id != attachmentId).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      _attachments = [
        selected.copyWith(order: 0),
        for (var i = 0; i < others.length; i++) others[i].copyWith(order: i + 1),
      ];
    });
  }

  Future<void> _reorderAttachments(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final next = [..._attachments];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    _safeSetState(() => _attachments = next);
    await context.read<BoardController>().reorderCardAttachments(
          widget.columnId,
          widget.card.id,
          next,
        );
  }

  void _openAttachmentViewer(int index) {
    showCardAttachmentViewer(
      context: context,
      attachments: _attachments,
      initialIndex: index,
      columnId: widget.columnId,
      cardId: widget.card.id,
      onAttachmentsChanged: (attachments) {
        if (!mounted) return;
        _safeSetState(() => _attachments = [...attachments]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final customLabels = _boardController.appSettings.customLabels;
    final themeId = _boardController.projectSettings.themeId;
    final themePreset = projectThemeForId(themeId);
    final allLabels = allKanbanLabels(customLabels, themeId: themeId);
    final missingCount = countMissingAttachmentsForCard(
      widget.card.copyWith(attachments: _attachments),
      _boardController.missingAttachmentIds,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Material(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _completed,
                        onChanged: (v) =>
                            _safeSetState(() => _completed = v ?? false),
                      ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('card-detail-title'),
                          controller: _titleController,
                          style: theme.textTheme.titleLarge?.copyWith(
                            decoration: _completed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          decoration: const InputDecoration(
                            hintText: '卡片标题',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      _CardPinButton(
                        columnId: widget.columnId,
                        cardId: widget.card.id,
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('备注', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('card-detail-desc'),
                        controller: _descController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: '添加详细说明…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('卡片背景色', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _pickCardColor,
                            icon: const Icon(Icons.palette_outlined, size: 18),
                            label: Text(
                              _colorValue == null
                                  ? '设置颜色'
                                  : '已设置',
                            ),
                          ),
                          if (_colorValue != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Color(_colorValue!),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () =>
                                  _safeSetState(() => _colorValue = null),
                              child: const Text('清除'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Text('图片', style: theme.textTheme.titleSmall),
                          const Spacer(),
                          Text(
                            '${_attachments.length}/${KanbanCard.maxAttachments}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (missingCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: MaterialBanner(
                            content: Text('有 $missingCount 张图片未下载到本机，请检查同步'),
                            leading: Icon(
                              Icons.cloud_off_outlined,
                              color: theme.colorScheme.error,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    context.read<BoardController>().syncNow(),
                                child: const Text('立即同步'),
                              ),
                            ],
                          ),
                        ),
                      if (_attachments.isNotEmpty)
                        CardAttachmentReorderGrid(
                          attachments: _attachments,
                          missingAttachmentIds:
                              _boardController.missingAttachmentIds,
                          onReorder: _reorderAttachments,
                          onTap: _openAttachmentViewer,
                          onLongPress: (index) async {
                            final attachment = _attachments[index];
                            final isCover = index == 0;
                            final action = await showModalBottomSheet<String>(
                              context: context,
                              builder: (ctx) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isCover)
                                      ListTile(
                                        leading: const Icon(Icons.photo),
                                        title: const Text('设为封面'),
                                        onTap: () =>
                                            Navigator.pop(ctx, 'cover'),
                                      ),
                                    ListTile(
                                      leading: Icon(
                                        Icons.delete_outline,
                                        color: theme.colorScheme.error,
                                      ),
                                      title: Text(
                                        '删除图片',
                                        style: TextStyle(
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                      onTap: () =>
                                          Navigator.pop(ctx, 'delete'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            if (!mounted || action == null) return;
                            if (action == 'cover') {
                              await _setCover(attachment.id);
                            } else if (action == 'delete') {
                              await _removeAttachment(attachment.id);
                            }
                          },
                        ),
                      const SizedBox(height: 8),
                      Text(
                        '长按拖动可调整顺序',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: _attachments.length >= KanbanCard.maxAttachments
                            ? null
                            : _pickAttachments,
                        icon: const Icon(Icons.add_photo_alternate_outlined,
                            size: 18),
                        label: const Text('添加图片'),
                      ),
                      const SizedBox(height: 20),
                      Text('截止日期', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _pickDueDate,
                            icon: const Icon(Icons.event, size: 18),
                            label: Text(
                              _dueDate == null
                                  ? '设置日期'
                                  : DateFormat.yMMMd('zh_CN')
                                      .format(_dueDate!),
                            ),
                          ),
                          if (_dueDate != null) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () =>
                                  _safeSetState(() => _dueDate = null),
                              child: const Text('清除'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('优先级', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: CardPriority.values.map((p) {
                          final selected = _priority == p;
                          return FilterChip(
                            label: Text(p.label),
                            selected: selected,
                            onSelected: (_) =>
                                _safeSetState(() => _priority = p),
                            avatar: p == CardPriority.none
                                ? null
                                : Icon(
                                    Icons.flag,
                                    size: 16,
                                    color: p.color(
                                      theme.colorScheme,
                                      theme: themePreset,
                                    ),
                                  ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Text('标签', style: theme.textTheme.titleSmall),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _showAddLabelDialog,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('新建'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final label in allLabels)
                            FilterChip(
                              label: Text(label.name),
                              selected: _labels.contains(label.key),
                              onSelected: (_) => _toggleLabel(label.key),
                              backgroundColor:
                                  label.color.withValues(alpha: 0.12),
                              selectedColor:
                                  label.color.withValues(alpha: 0.35),
                              checkmarkColor: label.color,
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Text('子任务', style: theme.textTheme.titleSmall),
                          if (_checklist.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${_checklist.where((i) => i.completed).length}/${_checklist.length}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._checklist.map(
                        (item) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: item.completed,
                          title: Text(
                            item.text,
                            style: item.completed
                                ? const TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                  )
                                : null,
                          ),
                          onChanged: (_) => _toggleChecklistItem(item.id),
                          secondary: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _removeChecklistItem(item.id),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('card-detail-checklist'),
                              controller: _checklistInput,
                              decoration: const InputDecoration(
                                hintText: '添加子任务…',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _addChecklistItem(),
                            ),
                          ),
                          IconButton(
                            onPressed: _addChecklistItem,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('删除卡片？'),
                              content: Text('「${widget.card.title}」将移至回收站'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true && context.mounted) {
                            await context
                                .read<BoardController>()
                                .deleteCard(widget.columnId, widget.card.id);
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                        child: Text(
                          '删除',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _save,
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CardPinButton extends StatelessWidget {
  const _CardPinButton({
    required this.columnId,
    required this.cardId,
  });

  final String columnId;
  final String cardId;

  @override
  Widget build(BuildContext context) {
    final pinned = context.select<BoardController, bool>(
      (c) => c.isCardPinned(columnId, cardId),
    );
    final controller = context.read<BoardController>();

    return IconButton(
      tooltip: pinned ? '取消置顶' : '置顶',
      onPressed: () => controller.toggleCardPin(columnId, cardId),
      icon: Icon(
        pinned ? Icons.push_pin : Icons.push_pin_outlined,
        color: pinned ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }
}
