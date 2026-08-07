import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../common/app_snack_bar.dart';
import '../../common/date_utils.dart';
import '../../common/help_tip_icon.dart';
import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../../settings/column_color_picker.dart';
import '../../utils/ime_guard.dart';
import '../../features/project/project_theme.dart';
import '../attachments/card_attachment_reorder_grid.dart';
import '../attachments/card_attachment_viewer.dart';
import '../attachments/card_image_add_sheet.dart';
import '../attachments/attachment_missing.dart';
import '../completed_auto_clear/completed_auto_clear.dart';
import 'confirm_delete_card.dart';
import 'description_expand_dialog.dart';
import 'description_markdown_preview.dart';
import 'commit_list_draft.dart';
import 'discard_blank_card.dart';
import 'due_date_shortcuts.dart';
import 'kanban_labels.dart';
import 'move_to_rework_on_new_feedback.dart';
import 'transfer_card_sheet.dart';
import 'verify_column.dart';

/// 卡片详情底部弹层：标题、备注、截止日期、优先级、标签、子任务
Future<void> showCardDetailSheet({
  required BuildContext context,
  required String columnId,
  required KanbanCard card,
  bool autofocusTitle = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _CardDetailSheet(
      columnId: columnId,
      card: card,
      autofocusTitle: autofocusTitle,
    ),
  );
}

class _CardDetailSheet extends StatefulWidget {
  const _CardDetailSheet({
    required this.columnId,
    required this.card,
    this.autofocusTitle = false,
  });

  final String columnId;
  final KanbanCard card;
  final bool autofocusTitle;

  @override
  State<_CardDetailSheet> createState() => _CardDetailSheetState();
}

class _CardDetailSheetState extends State<_CardDetailSheet> with ImeGuard {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  final FocusNode _descFocusNode = FocusNode();
  late BoardController _boardController;
  late bool _completed;
  DateTime? _dueDate;
  DateTime? _reminderAt;
  late CardRecurrence _recurrence;
  late CardPriority _priority;
  late List<String> _labels;
  late List<ChecklistItem> _checklist;
  late List<ChecklistItem> _verificationFeedback;
  late List<CardAttachment> _attachments;
  late List<CardLink> _links;
  late List<String> _blockedByIds;
  late List<String> _relatedIds;
  int? _colorValue;
  final _checklistInput = TextEditingController();
  final _verificationFeedbackInput = TextEditingController();
  bool _persisted = false;
  bool _skipPersist = false;
  late bool _previewMarkdown;
  /// 备注全屏放大打开时，详情页暂不挂载备注 TextField，避免双绑定同一 controller。
  bool _descriptionExpanded = false;
  bool _resolvingConflict = false;
  /// 解决成功后即使弹层未立刻关闭，也隐藏冲突条（widget.card 是打开时快照）。
  bool _conflictResolved = false;

  Iterable<TextEditingController> get _textControllers => [
        _titleController,
        _descController,
        _checklistInput,
        _verificationFeedbackInput,
      ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.card.title);
    _descController =
        TextEditingController(text: widget.card.description ?? '');
    _completed = widget.card.completed;
    _dueDate = widget.card.dueDate != null
        ? DateTime.fromMillisecondsSinceEpoch(widget.card.dueDate!)
        : null;
    _reminderAt = widget.card.reminderAt != null
        ? DateTime.fromMillisecondsSinceEpoch(widget.card.reminderAt!)
        : null;
    _recurrence = widget.card.recurrence;
    _priority = widget.card.priority;
    _labels = [...widget.card.labels];
    _checklist = [...widget.card.checklist];
    _verificationFeedback = [...widget.card.verificationFeedback];
    _attachments = [...widget.card.sortedAttachments];
    _links = [...widget.card.sortedLinks];
    _blockedByIds = [...widget.card.blockedByIds];
    _relatedIds = [...widget.card.relatedIds];
    _colorValue = widget.card.colorValue;
    bindImeGuard(_textControllers);
    _boardController = context.read<BoardController>();
    // 待验证列打开详情时备注默认预览，便于阅读长文本；仍可切回编辑。
    final columns = _boardController.board?.columns ?? const <KanbanColumn>[];
    _previewMarkdown = shouldDefaultPreviewMarkdown(
      columnId: widget.columnId,
      columns: columns,
    );
    _boardController.addListener(_onBoardChanged);
  }

  /// 当前卡是否仍在「待验证」列（用于完成按钮显隐）。
  bool get _isInVerifyColumn {
    final board = _boardController.board;
    if (board == null) return false;
    final columnId =
        _boardController.findColumnIdForCard(widget.card.id) ??
            widget.columnId;
    return isVerifyColumnId(columnId: columnId, columns: board.columns);
  }

  @override
  void dispose() {
    _boardController.removeListener(_onBoardChanged);
    _titleController.dispose();
    _descController.dispose();
    _descFocusNode.dispose();
    _checklistInput.dispose();
    _verificationFeedbackInput.dispose();
    super.dispose();
  }

  /// 标题框回车：切到可编辑备注并聚焦，便于连续输入。
  void _focusDescriptionFromTitle() {
    if (_previewMarkdown) {
      _safeSetState(() => _previewMarkdown = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _descriptionExpanded) return;
      _descFocusNode.requestFocus();
    });
  }

  void _onBoardChanged() => deferRebuildIfComposing(_textControllers);

  void _safeSetState(VoidCallback fn) => imeSafeSetState(fn, _textControllers);

  String get _effectiveTitle {
    final title = _titleController.text.trim();
    return title.isEmpty ? widget.card.title : title;
  }

  String? get _effectiveDescription {
    final desc = _descController.text.trim();
    return desc.isEmpty ? null : desc;
  }

  bool _isDirty() {
    final originalDesc = widget.card.description?.trim();
    final nextDesc = _effectiveDescription;
    final originalDue = widget.card.dueDate;
    final nextDue = _dueDate?.millisecondsSinceEpoch;
    final originalReminder = widget.card.reminderAt;
    final nextReminder = _reminderAt?.millisecondsSinceEpoch;
    if (_effectiveTitle != widget.card.title) return true;
    if (nextDesc !=
        (originalDesc == null || originalDesc.isEmpty ? null : originalDesc)) {
      return true;
    }
    if (_completed != widget.card.completed) return true;
    if (nextDue != originalDue) return true;
    if (nextReminder != originalReminder) return true;
    if (_recurrence != widget.card.recurrence) return true;
    if (_priority != widget.card.priority) return true;
    if (!_listEquals(_labels, widget.card.labels)) return true;
    if (!_checklistEquals(_checklist, widget.card.checklist)) return true;
    if (!_checklistEquals(
        _verificationFeedback, widget.card.verificationFeedback)) {
      return true;
    }
    if (_colorValue != widget.card.colorValue) return true;
    if (!_attachmentIdsEqual(_attachments, widget.card.sortedAttachments)) {
      return true;
    }
    if (!_linksEqual(_links, widget.card.sortedLinks)) return true;
    if (!_listEquals(_blockedByIds, widget.card.blockedByIds)) return true;
    if (!_listEquals(_relatedIds, widget.card.relatedIds)) return true;
    return false;
  }

  bool _linksEqual(List<CardLink> a, List<CardLink> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].url != b[i].url ||
          a[i].title != b[i].title ||
          a[i].order != b[i].order) {
        return false;
      }
    }
    return true;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _checklistEquals(List<ChecklistItem> a, List<ChecklistItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].text != b[i].text ||
          a[i].completed != b[i].completed) {
        return false;
      }
    }
    return true;
  }

  static bool _attachmentIdsEqual(
    List<CardAttachment> a,
    List<CardAttachment> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].order != b[i].order) return false;
    }
    return true;
  }

  /// 当前编辑态是否含标题/备注以外的可感知内容（清单、标签、日期等）。
  bool _hasOtherMetadata() {
    if (_completed) return true;
    if (_dueDate != null) return true;
    if (_reminderAt != null) return true;
    if (_recurrence != CardRecurrence.none) return true;
    if (_priority != CardPriority.none) return true;
    if (_labels.isNotEmpty) return true;
    if (_checklist.isNotEmpty) return true;
    if (_verificationFeedback.isNotEmpty) return true;
    if (_attachments.isNotEmpty) return true;
    if (_links.isNotEmpty) return true;
    if (_blockedByIds.isNotEmpty || _relatedIds.isNotEmpty) return true;
    if (_colorValue != null) return true;
    return false;
  }

  /// 持久化当前编辑；点击周边/关闭/返回时也会调用。
  Future<void> _persist() async {
    if (_persisted || _skipPersist) return;

    // 保存前把子任务/验证反馈输入框中未点「+」的非空草稿自动入列。
    _commitPendingListDrafts();

    // 新建空白卡关闭时：标题与备注皆空则删除，避免留下空壳卡。
    if (shouldDiscardBlankCard(
      editedTitle: _titleController.text,
      originalTitle: widget.card.title,
      editedDescription: _descController.text,
      hasOtherMetadata: _hasOtherMetadata(),
    )) {
      _persisted = true;
      _skipPersist = true;
      try {
        await _boardController.deleteCard(widget.columnId, widget.card.id);
      } catch (_) {
        // 失败后允许再次保存/关闭重试，避免「已标记已保存却仍停在详情页」。
        _persisted = false;
        _skipPersist = false;
        rethrow;
      }
      return;
    }

    if (!_isDirty()) {
      _persisted = true;
      return;
    }

    // 在可能 dispose 之前同步快照，再异步写入。
    final title = _effectiveTitle;
    final description = _effectiveDescription;
    final completed = _completed;
    final dueDate = _dueDate?.millisecondsSinceEpoch;
    final clearDueDate = _dueDate == null;
    final reminderAt = _reminderAt?.millisecondsSinceEpoch;
    final clearReminder = _reminderAt == null;
    final recurrence = _recurrence;
    final priority = _priority;
    final labels = List<String>.from(_labels);
    final checklist = List<ChecklistItem>.from(_checklist);
    final verificationFeedback =
        List<ChecklistItem>.from(_verificationFeedback);
    final attachments = List<CardAttachment>.from(_attachments);
    final links = List<CardLink>.from(_links);
    final blockedByIds = List<String>.from(_blockedByIds);
    final relatedIds = List<String>.from(_relatedIds);
    final colorValue = _colorValue;
    final clearColor = _colorValue == null;

    // 先占位防 PopScope/连点重复写入；失败时回滚以便重试。
    _persisted = true;
    try {
      await _boardController.updateCardFull(
        widget.columnId,
        widget.card.id,
        title: title,
        description: description,
        clearDescription: description == null,
        completed: completed,
        dueDate: dueDate,
        clearDueDate: clearDueDate,
        reminderAt: reminderAt,
        clearReminder: clearReminder,
        recurrence: recurrence,
        priority: priority,
        labels: labels,
        checklist: checklist,
        verificationFeedback: verificationFeedback,
        attachments: attachments,
        links: links,
        blockedByIds: blockedByIds,
        relatedIds: relatedIds,
        colorValue: colorValue,
        clearColor: clearColor,
      );
      await _moveToReworkIfNewFeedbackAdded(verificationFeedback);
    } catch (_) {
      _persisted = false;
      rethrow;
    }
  }

  /// 本次保存相对打开快照新增了验证反馈项时，自动移到「待返工」列。
  Future<void> _moveToReworkIfNewFeedbackAdded(
    List<ChecklistItem> nextFeedback,
  ) async {
    final board = _boardController.board;
    if (board == null) return;
    final fromColumnId =
        _boardController.findColumnIdForCard(widget.card.id) ??
            widget.columnId;
    final toColumnId = targetReworkColumnIdIfNeeded(
      originalFeedback: widget.card.verificationFeedback,
      nextFeedback: nextFeedback,
      currentColumnId: fromColumnId,
      columns: board.columns,
    );
    if (toColumnId == null) return;
    final rework = findReworkColumn(board.columns);
    if (rework == null) return;
    await _boardController.moveCard(
      cardId: widget.card.id,
      fromColumnId: fromColumnId,
      toColumnId: toColumnId,
      toDisplayIndex: rework.cards.length,
    );
  }

  /// 保存并关闭。与遮罩关闭共用 [_persist]：空标题回退原标题；空白新建卡则丢弃。
  /// 不再因标题框为空静默 return（新建空白卡点保存会表现为「有时关不掉」）。
  Future<void> _save() async {
    try {
      await _persist();
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: '保存失败：$error');
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  /// 待验证详情：先保存编辑，再按看板完成逻辑移入「已完成」并关闭。
  Future<void> _completeAndClose() async {
    // 允许失败重试时再次写入编辑内容。
    _persisted = false;
    // 完成移动由 toggle/move 负责；避免 _persist 仅打勾却仍留在待验证。
    final markCompletedLocally = _completed;
    _completed = widget.card.completed;
    try {
      await _persist();
    } catch (error) {
      _completed = markCompletedLocally;
      if (!mounted) return;
      showAppSnackBar(context, message: '保存失败：$error');
      return;
    }
    _completed = true;

    final columnId =
        _boardController.findColumnIdForCard(widget.card.id) ??
            widget.columnId;
    final live = _boardController.findCardById(widget.card.id);
    if (live == null) {
      if (mounted) _closeWithoutPersist();
      return;
    }

    try {
      if (!live.completed) {
        // 与卡片瓦片 / complete_card 一致：标记完成并移入已完成列。
        await _boardController.toggleCardCompleted(columnId, widget.card.id);
      } else {
        // 详情勾选后已保存为完成但尚未挪列时，补一次移入已完成。
        final board = _boardController.board;
        if (board != null) {
          final done = findDoneColumn(
            board,
            doneColumnName: _boardController.projectSettings.doneColumnName,
          );
          if (done != null && done.id != columnId) {
            await _boardController.moveCard(
              cardId: widget.card.id,
              fromColumnId: columnId,
              toColumnId: done.id,
              toDisplayIndex: done.cards.length,
              completed: true,
              completedAt: live.completedAt ??
                  DateTime.now().millisecondsSinceEpoch,
            );
          }
        }
      }
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: '完成失败：$error');
      return;
    }
    if (mounted) _closeWithoutPersist();
  }

  Future<void> _saveAsTemplate() async {
    final nameController = TextEditingController(text: '$_effectiveTitle 模板');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存为模板'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: '模板名称'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (!mounted || name == null || name.isEmpty) return;
    await _persist();
    final card = _boardController.board?.columns
        .where((column) => column.id == widget.columnId)
        .expand((column) => column.cards)
        .where((card) => card.id == widget.card.id)
        .firstOrNull;
    if (card == null) return;
    await _boardController.saveCardAsTemplate(card: card, name: name);
    _persisted = false;
    if (!mounted) return;
    showAppSnackBar(context, message: '已保存模板「$name」');
  }

  Future<void> _transferToOtherProject() async {
    final controller = context.read<BoardController>();
    if (controller.projects.length <= 1) {
      showAppSnackBar(context, message: '没有其他可转移的项目');
      return;
    }
    try {
      await _persist();
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, message: '保存失败：$error');
      return;
    }
    if (!mounted) return;
    final ok = await showTransferCardToProjectFlow(
      context: context,
      columnId: widget.columnId,
      cardId: widget.card.id,
      cardTitle: _effectiveTitle,
    );
    if (ok && mounted) {
      _closeWithoutPersist();
    }
  }

  void _closeWithoutPersist() {
    _skipPersist = true;
    Navigator.pop(context);
  }

  KanbanCard? get _liveCard {
    final board = _boardController.board;
    if (board == null) return null;
    for (final column in board.columns) {
      for (final card in column.cards) {
        if (card.id == widget.card.id) return card;
      }
    }
    return null;
  }

  bool get _showConflictBanner {
    if (_conflictResolved) return false;
    final live = _liveCard;
    if (live != null) return live.hasConflict;
    return widget.card.hasConflict;
  }

  Future<void> _resolveConflict(CardConflictResolution resolution) async {
    if (_resolvingConflict) return;
    _safeSetState(() => _resolvingConflict = true);
    try {
      await _boardController.resolveCardConflict(
        widget.columnId,
        widget.card.id,
        resolution,
      );
      if (!mounted) return;
      _conflictResolved = true;
      _closeWithoutPersist();
    } catch (error) {
      if (!mounted) return;
      _safeSetState(() => _resolvingConflict = false);
      showAppSnackBar(context, message: '解决冲突失败：$error');
    }
  }

  Future<void> _openDescriptionExpanded() async {
    _safeSetState(() => _descriptionExpanded = true);
    await showDescriptionExpandDialog(
      context: context,
      controller: _descController,
      initialPreview: _previewMarkdown,
    );
    if (mounted) {
      _safeSetState(() => _descriptionExpanded = false);
    }
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

  void _applyDueDateShortcut(DueDateShortcut shortcut) {
    _safeSetState(() => _dueDate = shortcut.resolve(DateTime.now()));
  }

  /// 截止日期快捷预设与「设置日期」同一行；小屏可横向滚动。
  Widget _buildDueDateRow() {
    final now = DateTime.now();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final shortcut in DueDateShortcut.values) ...[
            FilterChip(
              label: Text(shortcut.label),
              selected: isSameLocalDay(_dueDate, shortcut.resolve(now)),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onSelected: (_) => _applyDueDateShortcut(shortcut),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.tonalIcon(
            onPressed: _pickDueDate,
            icon: const Icon(Icons.event, size: 18),
            label: Text(
              _dueDate == null
                  ? '设置日期'
                  : DateFormat.yMMMd('zh_CN').format(_dueDate!),
            ),
          ),
          if (_dueDate != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _safeSetState(() => _dueDate = null),
              child: const Text('清除'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final initial = _reminderAt ?? _dueDate ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 5),
      helpText: '选择提醒日期',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: '选择提醒时间',
    );
    if (time == null || !mounted) return;
    _safeSetState(
      () => _reminderAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  /// 当前色不在快捷预设中时，视为自定义色。
  bool get _isCustomCardColor {
    final value = _colorValue;
    if (value == null) return false;
    return !kQuickColorPresets.any((c) => c.toARGB32() == value);
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

  Future<void> _addLink() async {
    final titleController = TextEditingController();
    final urlController = TextEditingController(text: 'https://');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加链接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: '标题（可选）'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '网址'),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    final title = titleController.text.trim();
    var url = urlController.text.trim();
    titleController.dispose();
    urlController.dispose();
    if (confirmed != true || url.isEmpty || !mounted) return;
    if (!url.contains('://')) url = 'https://$url';
    _safeSetState(() {
      _links = [
        ..._links,
        CardLink(
          id: const Uuid().v4(),
          url: url,
          title: title,
          order: _links.length,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ];
    });
  }

  Future<void> _pickRelatedCard({
    required String title,
    required ValueChanged<String> onPicked,
  }) async {
    final board = _boardController.board;
    if (board == null) return;
    final candidates = <({String id, String title, String column})>[];
    for (final column in board.columns) {
      for (final card in column.cards) {
        if (card.id == widget.card.id) continue;
        candidates.add((id: card.id, title: card.title, column: column.title));
      }
    }
    if (candidates.isEmpty) {
      showAppSnackBar(context, message: '当前看板没有其他可关联的卡片');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final item in candidates)
              ListTile(
                title: Text(item.title),
                subtitle: Text(item.column),
                onTap: () => Navigator.pop(ctx, item.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onPicked(picked);
  }

  List<Widget> _relationTiles({
    required List<String> ids,
    required ValueChanged<String> onRemove,
  }) {
    if (ids.isEmpty) return const [];
    return [
      for (final id in ids)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(_boardController.findCardById(id)?.title ?? '未知卡片'),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => onRemove(id),
          ),
          onTap: () {
            final card = _boardController.findCardById(id);
            final columnId = _boardController.findColumnIdForCard(id);
            if (card == null || columnId == null) return;
            showCardDetailSheet(
              context: context,
              columnId: columnId,
              card: card,
            );
          },
        ),
    ];
  }

  /// 将子任务与验证反馈输入框中的非空草稿写入对应列表（空白忽略）。
  void _commitPendingListDrafts() {
    final nextChecklist = commitChecklistDraft(
      items: _checklist,
      draftText: _checklistInput.text,
      newId: () => const Uuid().v4(),
    );
    if (!identical(nextChecklist, _checklist)) {
      _checklist = nextChecklist;
      _checklistInput.clear();
    }
    final nextFeedback = commitChecklistDraft(
      items: _verificationFeedback,
      draftText: _verificationFeedbackInput.text,
      newId: () => const Uuid().v4(),
    );
    if (!identical(nextFeedback, _verificationFeedback)) {
      _verificationFeedback = nextFeedback;
      _verificationFeedbackInput.clear();
    }
  }

  void _addChecklistItem() {
    final next = commitChecklistDraft(
      items: _checklist,
      draftText: _checklistInput.text,
      newId: () => const Uuid().v4(),
    );
    if (identical(next, _checklist)) return;
    _safeSetState(() {
      _checklist = next;
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

  Future<void> _editChecklistItem(String id) async {
    await _editChecklistLikeItem(
      id: id,
      items: _checklist,
      onApply: (next) => _checklist = next,
      dialogTitle: '编辑子任务',
    );
  }

  void _addVerificationFeedbackItem() {
    final next = commitChecklistDraft(
      items: _verificationFeedback,
      draftText: _verificationFeedbackInput.text,
      newId: () => const Uuid().v4(),
    );
    if (identical(next, _verificationFeedback)) return;
    _safeSetState(() {
      _verificationFeedback = next;
      _verificationFeedbackInput.clear();
    });
  }

  void _toggleVerificationFeedbackItem(String id) {
    _safeSetState(() {
      _verificationFeedback = _verificationFeedback
          .map(
            (item) => item.id == id
                ? item.copyWith(completed: !item.completed)
                : item,
          )
          .toList();
    });
  }

  void _removeVerificationFeedbackItem(String id) {
    _safeSetState(() {
      _verificationFeedback =
          _verificationFeedback.where((item) => item.id != id).toList();
    });
  }

  Future<void> _editVerificationFeedbackItem(String id) async {
    await _editChecklistLikeItem(
      id: id,
      items: _verificationFeedback,
      onApply: (next) => _verificationFeedback = next,
      dialogTitle: '编辑验证反馈',
    );
  }

  Future<void> _editChecklistLikeItem({
    required String id,
    required List<ChecklistItem> items,
    required void Function(List<ChecklistItem> next) onApply,
    required String dialogTitle,
  }) async {
    final current = items.where((item) => item.id == id).firstOrNull;
    if (current == null) return;
    final controller = TextEditingController(text: current.text);
    final nextText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(dialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || nextText == null || nextText.isEmpty) return;
    _safeSetState(() {
      onApply([
        for (final item in items)
          if (item.id == id) item.copyWith(text: nextText) else item,
      ]);
    });
  }

  Future<void> _pickAttachments() async {
    if (_attachments.length >= KanbanCard.maxAttachments) {
      if (!mounted) return;
      showAppSnackBar(context, message: '每张卡片最多 ${KanbanCard.maxAttachments} 张图片');
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
      showAppSnackBar(context, message: error);
      return;
    }

    _reloadAttachmentsFromBoard();
  }

  void _reloadAttachmentsFromBoard() {
    final updated = context
        .read<BoardController>()
        .board
        ?.columns
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
        for (var i = 0; i < others.length; i++)
          others[i].copyWith(order: i + 1),
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
    final conflictCard = _liveCard ?? widget.card;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // 点击遮罩/关闭/系统返回时自动保存；删除与冲突解决会跳过。
          _persist();
        }
      },
      child: Padding(
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
                            autofocus: widget.autofocusTitle,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => _focusDescriptionFromTitle(),
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
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_showConflictBanner)
                    Material(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              conflictCard.conflictDeleted
                                  ? '同步冲突：另一侧删除了此卡片'
                                  : '同步冲突：存在另一份副本',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (conflictCard.conflictSide != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                '另一份：${conflictCard.conflictSide!.title}'
                                '${conflictCard.conflictSide!.description == null || conflictCard.conflictSide!.description!.isEmpty ? '' : ' — ${conflictCard.conflictSide!.description}'}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton(
                                  onPressed: _resolvingConflict
                                      ? null
                                      : () => _resolveConflict(
                                            CardConflictResolution.keepPrimary,
                                          ),
                                  child: Text(
                                    _resolvingConflict ? '处理中…' : '保留当前',
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: _resolvingConflict
                                      ? null
                                      : () => _resolveConflict(
                                            CardConflictResolution.keepOther,
                                          ),
                                  child: Text(
                                    _resolvingConflict
                                        ? '处理中…'
                                        : (conflictCard.conflictDeleted
                                            ? '确认删除'
                                            : '保留另一份'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            Text('备注', style: theme.textTheme.titleSmall),
                            const Spacer(),
                            IconButton(
                              tooltip: '放大编辑',
                              onPressed: _openDescriptionExpanded,
                              icon: const Icon(Icons.open_in_full, size: 20),
                              visualDensity: VisualDensity.compact,
                            ),
                            TextButton(
                              onPressed: () => _safeSetState(
                                () => _previewMarkdown = !_previewMarkdown,
                              ),
                              child: Text(_previewMarkdown ? '编辑' : '预览'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_previewMarkdown)
                          DescriptionMarkdownPreview(
                            data: _descController.text,
                            minHeight: 120,
                          )
                        else if (_descriptionExpanded)
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(minHeight: 120),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '正在放大编辑…',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          TextField(
                            key: const ValueKey('card-detail-desc'),
                            controller: _descController,
                            focusNode: _descFocusNode,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              hintText: '支持 Markdown…',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Text('卡片背景色', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        // 快捷色与「更多颜色」同一行；小屏可横向滚动。
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ColorQuickSwatches(
                                selectedColorValue: _colorValue,
                                onSelected: (value) {
                                  if (value == _colorValue) return;
                                  _safeSetState(() => _colorValue = value);
                                },
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonalIcon(
                                onPressed: _pickCardColor,
                                icon: const Icon(
                                  Icons.palette_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  _isCustomCardColor ? '自定义…' : '更多颜色…',
                                ),
                              ),
                              if (_colorValue != null) ...[
                                const SizedBox(width: 8),
                                if (_isCustomCardColor)
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Color(_colorValue!),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color:
                                            theme.colorScheme.outlineVariant,
                                      ),
                                    ),
                                  ),
                                if (_isCustomCardColor)
                                  const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () =>
                                      _safeSetState(() => _colorValue = null),
                                  child: const Text('清除'),
                                ),
                              ],
                            ],
                          ),
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
                          onPressed:
                              _attachments.length >= KanbanCard.maxAttachments
                                  ? null
                                  : _pickAttachments,
                          icon: const Icon(Icons.add_photo_alternate_outlined,
                              size: 18),
                          label: const Text('添加图片'),
                        ),
                        const SizedBox(height: 20),
                        Text('截止日期', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        _buildDueDateRow(),
                        const SizedBox(height: 20),
                        Text('提醒', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _pickReminder,
                              icon: const Icon(
                                Icons.notifications_outlined,
                                size: 18,
                              ),
                              label: Text(
                                _reminderAt == null
                                    ? '设置提醒'
                                    : DateFormat('MMMd HH:mm', 'zh_CN')
                                        .format(_reminderAt!),
                              ),
                            ),
                            if (_reminderAt != null) ...[
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () =>
                                    _safeSetState(() => _reminderAt = null),
                                child: const Text('清除'),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text('重复', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final recurrence in CardRecurrence.values)
                              ChoiceChip(
                                label: Text(recurrence.label),
                                selected: _recurrence == recurrence,
                                onSelected: (_) => _safeSetState(
                                  () => _recurrence = recurrence,
                                ),
                              ),
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
                              showCheckmark: false,
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
                            title: GestureDetector(
                              onTap: () => _editChecklistItem(item.id),
                              child: Text(
                                item.text,
                                style: item.completed
                                    ? const TextStyle(
                                        decoration: TextDecoration.lineThrough,
                                      )
                                    : null,
                              ),
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
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text('验证反馈', style: theme.textTheme.titleSmall),
                            if (_verificationFeedback.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                '${_verificationFeedback.where((i) => i.completed).length}/${_verificationFeedback.length}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._verificationFeedback.map(
                          (item) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: item.completed,
                            title: GestureDetector(
                              onTap: () =>
                                  _editVerificationFeedbackItem(item.id),
                              child: Text(
                                item.text,
                                style: item.completed
                                    ? const TextStyle(
                                        decoration: TextDecoration.lineThrough,
                                      )
                                    : null,
                              ),
                            ),
                            onChanged: (_) =>
                                _toggleVerificationFeedbackItem(item.id),
                            secondary: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  _removeVerificationFeedbackItem(item.id),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey(
                                  'card-detail-verification-feedback',
                                ),
                                controller: _verificationFeedbackInput,
                                decoration: const InputDecoration(
                                  hintText: '添加验证反馈…',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onSubmitted: (_) =>
                                    _addVerificationFeedbackItem(),
                              ),
                            ),
                            IconButton(
                              onPressed: _addVerificationFeedbackItem,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text('链接', style: theme.textTheme.titleSmall),
                            const HelpTipIcon(
                              message:
                                  '可添加外部网页书签（打开网址用，不是卡片之间的依赖/关联）',
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _addLink,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('添加'),
                            ),
                          ],
                        ),
                        for (final link in _links)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.link),
                            title: Text(link.displayTitle),
                            subtitle: Text(
                              link.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: '删除链接',
                              onPressed: () => _safeSetState(
                                () => _links = _links
                                    .where((item) => item.id != link.id)
                                    .toList(),
                              ),
                              icon: const Icon(Icons.close),
                            ),
                            onTap: () => launchUrl(
                              Uri.parse(link.url),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(
                              '依赖（阻塞本卡）',
                              style: theme.textTheme.titleSmall,
                            ),
                            const HelpTipIcon(
                              message:
                                  '前置卡未完成前，本卡应视为被阻塞；点条目可跳转查看。',
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _pickRelatedCard(
                                title: '选择阻塞本卡的前置任务',
                                onPicked: (id) {
                                  if (_blockedByIds.contains(id) ||
                                      id == widget.card.id) {
                                    return;
                                  }
                                  _safeSetState(
                                    () => _blockedByIds = [
                                      ..._blockedByIds,
                                      id,
                                    ],
                                  );
                                },
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('添加'),
                            ),
                          ],
                        ),
                        ..._relationTiles(
                          ids: _blockedByIds,
                          onRemove: (id) => _safeSetState(
                            () => _blockedByIds = _blockedByIds
                                .where((item) => item != id)
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(
                              '关联（相关卡片）',
                              style: theme.textTheme.titleSmall,
                            ),
                            const HelpTipIcon(
                              message: '无先后关系，仅便于跳转与追溯；不会阻塞本卡。',
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _pickRelatedCard(
                                title: '选择关联卡片',
                                onPicked: (id) {
                                  if (_relatedIds.contains(id) ||
                                      id == widget.card.id) {
                                    return;
                                  }
                                  _safeSetState(
                                    () =>
                                        _relatedIds = [..._relatedIds, id],
                                  );
                                },
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('添加'),
                            ),
                          ],
                        ),
                        ..._relationTiles(
                          ids: _relatedIds,
                          onRemove: (id) => _safeSetState(
                            () => _relatedIds = _relatedIds
                                .where((item) => item != id)
                                .toList(),
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final metaCard = _liveCard ?? widget.card;
                            final line = formatCardDetailTimestamps(
                              createdAt: metaCard.createdAt,
                              updatedAt: metaCard.updatedAt,
                              completedAt: metaCard.completed
                                  ? metaCard.completedAt
                                  : null,
                            );
                            if (line == null) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Text(
                                line,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed: _saveAsTemplate,
                                  icon: const Icon(Icons.bookmark_add_outlined),
                                  label: const Text('存为模板'),
                                ),
                                Builder(
                                  builder: (context) {
                                    final canTransfer = context
                                            .watch<BoardController>()
                                            .projects
                                            .length >
                                        1;
                                    return TextButton(
                                      onPressed: _transferToOtherProject,
                                      child: Text(
                                        '转移到…',
                                        style: TextStyle(
                                          color: canTransfer
                                              ? null
                                              : Theme.of(context).disabledColor,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final controller =
                                        context.read<BoardController>();
                                    final ok = await confirmDeleteCardIfNeeded(
                                      context: context,
                                      cardTitle: widget.card.title,
                                      confirmBeforeDelete: controller
                                          .appSettings.confirmBeforeDeleteCard,
                                    );
                                    if (ok && context.mounted) {
                                      await controller.deleteCard(
                                        widget.columnId,
                                        widget.card.id,
                                      );
                                      if (context.mounted) {
                                        _closeWithoutPersist();
                                      }
                                    }
                                  },
                                  child: Text(
                                    '删除',
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_isInVerifyColumn) ...[
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            key: const ValueKey('card-detail-complete'),
                            onPressed: _completeAndClose,
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('完成'),
                          ),
                          const SizedBox(width: 8),
                        ],
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
