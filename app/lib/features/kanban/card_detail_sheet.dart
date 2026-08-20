import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../common/app_snack_bar.dart';
import '../../common/date_utils.dart';
import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';
import '../../settings/column_color_picker.dart';
import '../../utils/ime_guard.dart';
import '../../features/project/project_theme.dart';
import '../completed_auto_clear/completed_auto_clear.dart';
import '../agent_dispatch/card_agent_conversation_section.dart';
import '../agent_dispatch/agent_interaction.dart';
import '../labels/label_editor_dialog.dart';
import 'card_complete_motion.dart';
import 'card_detail_actions_bar.dart';
import 'card_detail_agent_model_section.dart';
import 'card_detail_attachments_section.dart';
import 'card_detail_file_attachments_section.dart';
import 'card_detail_checklist_section.dart';
import 'card_detail_conflict_banner.dart';
import 'card_detail_commit_ref_section.dart';
import 'card_detail_due_reminder_section.dart';
import 'card_detail_pin_button.dart';
import 'card_detail_relations_section.dart';
import 'description_expand_dialog.dart';
import 'description_markdown_preview.dart';
import 'commit_list_draft.dart';
import 'discard_blank_card.dart';
import 'kanban_labels.dart';
import 'move_to_rework_on_new_feedback.dart';
import 'transfer_card_sheet.dart';
import 'verify_column.dart';

/// 卡片详情 BottomSheet 是否允许整页垂直拖拽。
///
/// 必须为 false：电脑端默认 enableDrag 会在按钮上挂垂直拖动手势，
/// 与点击竞争并表现为「穿透」拖面板。高度调整交给 [DraggableScrollableSheet]。
@visibleForTesting
const bool kCardDetailSheetEnableDrag = false;

/// 电脑端 Material 3 默认底栏最大宽度约 640，详情里多列选项会挤。
@visibleForTesting
const double kCardDetailSheetMaxWidth = 880;

/// 卡片详情底部弹层：标题、备注、标签、验证反馈、子任务、优先级、卡片背景色、截止日期、关联、提交号等
Future<void> showCardDetailSheet({
  required BuildContext context,
  required String columnId,
  required KanbanCard card,
  bool autofocusTitle = false,
  bool isNewCard = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // 关闭整页垂直拖拽：电脑端鼠标在按钮上轻微移动会抢走点击，表现为「穿透」拖面板。
    // 面板高度仍由下方 DraggableScrollableSheet + 内容区滚动手势调整；关闭靠按钮/遮罩。
    enableDrag: kCardDetailSheetEnableDrag,
    // 仅顶部手柄可拖拽关闭，避免按钮/内容控件参与 BottomSheet 拖动手势。
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: kCardDetailSheetMaxWidth),
    builder: (ctx) => _CardDetailSheet(
      columnId: columnId,
      card: card,
      autofocusTitle: autofocusTitle,
      isNewCard: isNewCard,
    ),
  );
}

class _CardDetailSheet extends StatefulWidget {
  const _CardDetailSheet({
    required this.columnId,
    required this.card,
    this.autofocusTitle = false,
    this.isNewCard = false,
  });

  final String columnId;
  final KanbanCard card;
  final bool autofocusTitle;
  final bool isNewCard;

  @override
  State<_CardDetailSheet> createState() => _CardDetailSheetState();
}

class _CardDetailSheetState extends State<_CardDetailSheet> with ImeGuard {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _commitRefController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _descFocusNode;
  late final FocusNode _checklistFocusNode;
  late final FocusNode _verificationFeedbackFocusNode;
  late BoardController _boardController;
  late bool _completed;
  DateTime? _dueDate;
  DateTime? _reminderAt;
  late CardRecurrence _recurrence;
  late int _recurrenceInterval;
  late CardPriority _priority;
  late List<String> _labels;
  late List<ChecklistItem> _checklist;
  late List<ChecklistItem> _verificationFeedback;
  late List<CardAttachment> _attachments;
  late List<CardFileAttachment> _fileAttachments;
  late List<CardLink> _links;
  late List<String> _blockedByIds;
  late List<String> _relatedIds;
  String? _agentEngine;
  String? _agentModelId;
  late Map<String, String> _agentModelParamValues;
  bool? _agentAllowDirtyWorkspace;
  bool? _agentEnableSandbox;
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
        _commitRefController,
        _checklistInput,
        _verificationFeedbackInput,
      ];

  @override
  void initState() {
    super.initState();
    _titleFocusNode = FocusNode(onKeyEvent: _onTitleKeyEvent);
    _descFocusNode = FocusNode(onKeyEvent: _onDescKeyEvent);
    _checklistFocusNode = FocusNode(onKeyEvent: _onChecklistKeyEvent);
    _verificationFeedbackFocusNode =
        FocusNode(onKeyEvent: _onVerificationFeedbackKeyEvent);
    _titleController = TextEditingController(text: widget.card.title);
    _descController =
        TextEditingController(text: widget.card.description ?? '');
    _commitRefController =
        TextEditingController(text: widget.card.commitRef ?? '');
    _completed = widget.card.completed;
    _dueDate = widget.card.dueDate != null
        ? DateTime.fromMillisecondsSinceEpoch(widget.card.dueDate!)
        : null;
    _reminderAt = widget.card.reminderAt != null
        ? DateTime.fromMillisecondsSinceEpoch(widget.card.reminderAt!)
        : null;
    _recurrence = widget.card.recurrence;
    _recurrenceInterval = widget.card.recurrenceInterval;
    _priority = widget.card.priority;
    _labels = [...widget.card.labels];
    _checklist = [...widget.card.checklist];
    _verificationFeedback = [...widget.card.verificationFeedback];
    _attachments = [...widget.card.sortedAttachments];
    _fileAttachments = [...widget.card.sortedFileAttachments];
    _links = [...widget.card.sortedLinks];
    _blockedByIds = [...widget.card.blockedByIds];
    _relatedIds = [...widget.card.relatedIds];
    _agentEngine = widget.card.agentEngine;
    _agentModelId = widget.card.agentModelId;
    _agentModelParamValues = {
      ...?widget.card.agentModelParamValues,
    };
    _agentAllowDirtyWorkspace = widget.card.agentAllowDirtyWorkspace;
    _agentEnableSandbox = widget.card.agentEnableSandbox;
    _colorValue = widget.card.colorValue;
    bindImeGuard(_textControllers);
    _boardController = context.read<BoardController>();
    // 进行中 / 待验证 / 待返工 / 阻塞中 / 已完成打开详情时备注默认预览，便于阅读长文本；
    // 备注为空时默认进入编辑态，便于直接输入；仍可手动切换。
    final columns = _boardController.board?.columns ?? const <KanbanColumn>[];
    final descriptionEmpty = widget.card.description?.trim().isEmpty ?? true;
    _previewMarkdown = descriptionEmpty
        ? false
        : shouldDefaultPreviewMarkdown(
            columnId: widget.columnId,
            columns: columns,
            doneColumnName: _boardController.projectSettings.doneColumnName,
          );
    _boardController.addListener(_onBoardChanged);
  }

  /// 当前卡是否仍在「已完成」列（已完成卡不再展示重复的完成操作）。
  bool get _isInDoneColumn {
    final board = _boardController.board;
    if (board == null) return false;
    final columnId =
        _boardController.findColumnIdForCard(widget.card.id) ?? widget.columnId;
    return isDoneColumnId(
      columnId: columnId,
      columns: board.columns,
      doneColumnName: _boardController.projectSettings.doneColumnName,
    );
  }

  @override
  void dispose() {
    _boardController.removeListener(_onBoardChanged);
    _titleController.dispose();
    _titleFocusNode.dispose();
    _descController.dispose();
    _commitRefController.dispose();
    _descFocusNode.dispose();
    _checklistFocusNode.dispose();
    _verificationFeedbackFocusNode.dispose();
    _checklistInput.dispose();
    _verificationFeedbackInput.dispose();
    super.dispose();
  }

  void _clearComposing(TextEditingController controller) {
    final value = controller.value;
    if (value.composing.isValid) {
      controller.value = value.copyWith(composing: TextRange.empty);
    }
  }

  /// 标题框 Tab：切到备注输入框（与回车行为一致）。
  KeyEventResult _onTitleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
      _focusDescriptionFromTitle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 备注框 Enter 保存；Shift+Enter 换行；Tab 切到验证反馈输入框。
  KeyEventResult _onDescKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      _clearComposing(_descController);
      _save();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _verificationFeedbackFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 验证反馈输入框 Tab：切到子任务输入框。
  KeyEventResult _onVerificationFeedbackKeyEvent(
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
      _checklistFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 子任务输入框 Tab：切到标题输入框。
  KeyEventResult _onChecklistKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
      _titleFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 标题框回车/Tab：先结束标题框的 IME 组字（与回车提交一致），
  /// 再退出 Markdown 预览并聚焦备注，便于连续输入。
  ///
  /// 备注 TextField 仅在非预览、非展开时才挂载；ImeGuard 在组字期间会延迟 setState，
  /// 若不先结束组字，预览→编辑的重建会被推迟到组字结束，备注框迟迟无法挂载，
  /// 焦点请求只能等重建后才生效，表现为「按 Tab 延迟」。这里先清除标题框的组字
  /// 区间，让后续 [_safeSetState] 立即生效；随后直接 requestFocus——备注框已挂载时
  /// 立即聚焦，尚未挂载（重建中）时 Flutter 会在其挂载后自动补上该焦点请求，
  /// 不再依赖帧回调的时序。
  void _focusDescriptionFromTitle() {
    if (!mounted || _descriptionExpanded) return;
    _clearComposing(_titleController);
    if (_previewMarkdown) {
      _safeSetState(() => _previewMarkdown = false);
    }
    _descFocusNode.requestFocus();
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
    final originalCommitRef = widget.card.commitRef?.trim();
    final nextCommitRef = _commitRefController.text.trim();
    if (nextCommitRef !=
        (originalCommitRef == null || originalCommitRef.isEmpty
            ? ''
            : originalCommitRef)) {
      return true;
    }
    if (_completed != widget.card.completed) return true;
    if (nextDue != originalDue) return true;
    if (nextReminder != originalReminder) return true;
    if (_recurrence != widget.card.recurrence) return true;
    if (_recurrenceInterval != widget.card.recurrenceInterval) return true;
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
    if (!_fileAttachmentIdsEqual(
        _fileAttachments, widget.card.sortedFileAttachments)) {
      return true;
    }
    if (!_linksEqual(_links, widget.card.sortedLinks)) return true;
    if (!_listEquals(_blockedByIds, widget.card.blockedByIds)) return true;
    if (!_listEquals(_relatedIds, widget.card.relatedIds)) return true;
    if (_agentEngine != widget.card.agentEngine) return true;
    if (_agentModelId != widget.card.agentModelId) return true;
    if (!_stringMapEquals(
      _agentModelParamValues,
      widget.card.agentModelParamValues ?? const {},
    )) {
      return true;
    }
    if (_agentAllowDirtyWorkspace != widget.card.agentAllowDirtyWorkspace) {
      return true;
    }
    if (_agentEnableSandbox != widget.card.agentEnableSandbox) {
      return true;
    }
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

  static bool _stringMapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
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

  static bool _fileAttachmentIdsEqual(
    List<CardFileAttachment> a,
    List<CardFileAttachment> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].order != b[i].order) return false;
    }
    return true;
  }

  /// 间隔可选上限：天 30、周/月 12。
  static int _maxRecurrenceInterval(CardRecurrence recurrence) {
    return switch (recurrence) {
      CardRecurrence.daily => 30,
      CardRecurrence.weekly || CardRecurrence.monthly => 12,
      CardRecurrence.none => 1,
    };
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
    if (_fileAttachments.isNotEmpty) return true;
    if (_links.isNotEmpty) return true;
    if (_blockedByIds.isNotEmpty || _relatedIds.isNotEmpty) return true;
    if (_colorValue != null) return true;
    if (_commitRefController.text.trim().isNotEmpty) return true;
    if (_agentEngine != null ||
        _agentModelId != null ||
        _agentModelParamValues.isNotEmpty ||
        _agentAllowDirtyWorkspace != null ||
        _agentEnableSandbox != null) {
      return true;
    }
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
        await _boardController.discardBlankNewCard(
          widget.columnId,
          widget.card.id,
        );
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
    final commitRefText = _commitRefController.text.trim();
    final commitRef = commitRefText.isEmpty ? null : commitRefText;
    final clearCommitRef = commitRefText.isEmpty;
    final completed = _completed;
    final dueDate = _dueDate?.millisecondsSinceEpoch;
    final clearDueDate = _dueDate == null;
    final reminderAt = _reminderAt?.millisecondsSinceEpoch;
    final clearReminder = _reminderAt == null;
    final recurrence = _recurrence;
    final recurrenceInterval =
        recurrence == CardRecurrence.none ? 1 : _recurrenceInterval;
    final priority = _priority;
    final labels = List<String>.from(_labels);
    final checklist = List<ChecklistItem>.from(_checklist);
    final verificationFeedback =
        List<ChecklistItem>.from(_verificationFeedback);
    final removedAgentFollowUpTexts = widget.card.verificationFeedback
        .where(
          (original) =>
              original.text.startsWith(agentFollowUpFeedbackPrefix) &&
              !verificationFeedback.any((next) => next.id == original.id),
        )
        .map(
          (item) => item.text.substring(agentFollowUpFeedbackPrefix.length),
        )
        .toList();
    final attachments = List<CardAttachment>.from(_attachments);
    final fileAttachments = List<CardFileAttachment>.from(_fileAttachments);
    final links = List<CardLink>.from(_links);
    final blockedByIds = List<String>.from(_blockedByIds);
    final relatedIds = List<String>.from(_relatedIds);
    final agentEngine = _agentEngine;
    final agentModelId = _agentModelId;
    final agentModelParamValues = Map<String, String>.from(
      _agentModelParamValues,
    );
    final agentAllowDirtyWorkspace = _agentAllowDirtyWorkspace;
    final agentEnableSandbox = _agentEnableSandbox;
    final colorValue = _colorValue;
    final clearColor = _colorValue == null;

    // 先占位防 PopScope/连点重复写入；失败时回滚以便重试。
    _persisted = true;
    try {
      final persistColumnId =
          _boardController.findColumnIdForCard(widget.card.id) ??
              widget.columnId;
      final updateError = await _boardController.updateCardFull(
        persistColumnId,
        widget.card.id,
        title: title,
        description: description,
        clearDescription: description == null,
        commitRef: commitRef,
        clearCommitRef: clearCommitRef,
        completed: hasIncompleteVerificationFeedback(verificationFeedback)
            ? false
            : completed,
        dueDate: dueDate,
        clearDueDate: clearDueDate,
        reminderAt: reminderAt,
        clearReminder: clearReminder,
        recurrence: recurrence,
        recurrenceInterval: recurrenceInterval,
        priority: priority,
        labels: labels,
        checklist: checklist,
        verificationFeedback: verificationFeedback,
        attachments: attachments,
        fileAttachments: fileAttachments,
        links: links,
        blockedByIds: blockedByIds,
        relatedIds: relatedIds,
        agentEngine: agentEngine,
        clearAgentEngine: agentEngine == null,
        agentModelId: agentModelId,
        clearAgentModelId: agentModelId == null,
        agentModelParamValues: agentModelParamValues,
        clearAgentModelParamValues: agentModelParamValues.isEmpty,
        agentAllowDirtyWorkspace: agentAllowDirtyWorkspace,
        clearAgentAllowDirtyWorkspace: agentAllowDirtyWorkspace == null,
        agentEnableSandbox: agentEnableSandbox,
        clearAgentEnableSandbox: agentEnableSandbox == null,
        colorValue: colorValue,
        clearColor: clearColor,
      );
      if (updateError != null) throw StateError(updateError);
      if (removedAgentFollowUpTexts.isNotEmpty) {
        var markdown = _boardController
                .findCardById(widget.card.id)
                ?.agentConversationMarkdown ??
            '';
        for (final text in removedAgentFollowUpTexts) {
          markdown = removeAgentConversationUserReply(markdown, text);
        }
        final historyError = await _boardController.setCardAgentConversation(
          widget.card.id,
          markdown,
        );
        if (historyError != null) throw StateError(historyError);
      }
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
    if (!hasAddedVerificationFeedbackItems(
      original: widget.card.verificationFeedback,
      next: nextFeedback,
    )) {
      return;
    }
    final board = _boardController.board;
    if (board == null) return;
    final fromColumnId =
        _boardController.findColumnIdForCard(widget.card.id) ?? widget.columnId;
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

  /// 追问已写入看板后，同步详情本地列表再保存关闭，避免打开快照覆盖反馈/附件。
  Future<void> _saveAndCloseAfterAgentFollowUp() async {
    final live = _liveCard;
    if (live != null) {
      _verificationFeedback = [...live.verificationFeedback];
      _fileAttachments = [...live.sortedFileAttachments];
    }
    await _save();
  }

  /// 待验证详情：先保存编辑，再按看板完成逻辑移入「已完成」并关闭。
  ///
  /// 若存在未完成验证反馈（含本次新增），待返工优先于已完成：只落「待返工」，不标记完成。
  Future<void> _completeAndClose() async {
    // 允许失败重试时再次写入编辑内容。
    _persisted = false;
    // 完成移动由 toggle/move 负责；避免 _persist 仅打勾却仍留在待验证。
    final markCompletedLocally = _completed;
    _completed = widget.card.completed;
    final feedbackSnapshot = List<ChecklistItem>.from(_verificationFeedback);
    try {
      await _persist();
    } catch (error) {
      _completed = markCompletedLocally;
      if (!mounted) return;
      showAppSnackBar(context, message: '保存失败：$error');
      return;
    }

    // 未完成验证反馈时优先待返工，避免随后的「已完成」迁移盖过。
    if (shouldPreferReworkOverComplete(nextFeedback: feedbackSnapshot)) {
      try {
        await _ensureInReworkForIncompleteFeedback(feedbackSnapshot);
      } catch (error) {
        if (!mounted) return;
        showAppSnackBar(context, message: '移入待返工失败：$error');
        return;
      }
      if (mounted) _closeWithoutPersist();
      return;
    }

    _completed = true;

    final columnId =
        _boardController.findColumnIdForCard(widget.card.id) ?? widget.columnId;
    final live = _boardController.findCardById(widget.card.id);
    if (live == null) {
      if (mounted) _closeWithoutPersist();
      return;
    }

    final board = _boardController.board;
    final done = board == null
        ? null
        : findDoneColumn(
            board,
            doneColumnName: _boardController.projectSettings.doneColumnName,
          );
    final fromRect = CardLayoutRegistry.instance.rectForCard(widget.card.id);

    if (!mounted) return;
    try {
      final completionError = await playCardCompleteFlight(
        context: context,
        cardId: widget.card.id,
        fromRect: fromRect,
        replica: _DetailCompleteFlightReplica(title: live.title),
        doneColumnId: done?.id,
        mutate: () async {
          if (!live.completed) {
            // 与卡片瓦片 / complete_card 一致：标记完成并移入已完成列。
            return _boardController.toggleCardCompleted(
              columnId,
              widget.card.id,
            );
          }
          // 详情勾选后已保存为完成但尚未挪列时，补一次移入已完成。
          if (done != null && done.id != columnId) {
            return _boardController.moveCard(
              cardId: widget.card.id,
              fromColumnId: columnId,
              toColumnId: done.id,
              toDisplayIndex: done.cards.length,
              completed: true,
              completedAt:
                  live.completedAt ?? DateTime.now().millisecondsSinceEpoch,
            );
          }
          return null;
        },
      );
      if (completionError != null) throw StateError(completionError);
    } catch (error) {
      // 卡片状态和移列已先于提醒、重复任务、活动记录等附带处理完成时，
      // 不能因后续附带处理报错把已完成的详情页留在界面上。
      if (_boardController.findCardById(widget.card.id)?.completed ?? false) {
        if (mounted) _closeWithoutPersist();
        return;
      }
      if (!mounted) return;
      showAppSnackBar(context, message: '完成失败：$error');
      return;
    }
    if (mounted) _closeWithoutPersist();
  }

  /// 存在未完成验证反馈时确保卡片在「待返工」（已在则跳过）。
  Future<void> _ensureInReworkForIncompleteFeedback(
    List<ChecklistItem> feedback,
  ) async {
    if (!hasIncompleteVerificationFeedback(feedback)) return;
    final board = _boardController.board;
    if (board == null) return;
    final fromColumnId =
        _boardController.findColumnIdForCard(widget.card.id) ?? widget.columnId;
    final toColumnId = targetReworkColumnIdIfIncompleteFeedback(
      feedback: feedback,
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
    final next = await editChecklistLikeItem(
      context: context,
      id: id,
      items: _checklist,
      dialogTitle: '编辑子任务',
    );
    if (!mounted || identical(next, _checklist)) return;
    _safeSetState(() => _checklist = next);
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
    final next = await editChecklistLikeItem(
      context: context,
      id: id,
      items: _verificationFeedback,
      dialogTitle: '编辑验证反馈',
    );
    if (!mounted || identical(next, _verificationFeedback)) return;
    _safeSetState(() => _verificationFeedback = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final customLabels = _boardController.appSettings.customLabels;
    final themeId = _boardController.projectSettings.themeId;
    final themePreset = projectThemeForId(themeId);
    final allLabels = labelsForEditing(
      customLabels,
      themeId: themeId,
      selectedKeys: _labels,
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
                            focusNode: _titleFocusNode,
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
                        CardDetailPinButton(
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
                    CardDetailConflictBanner(
                      card: conflictCard,
                      resolving: _resolvingConflict,
                      onResolve: _resolveConflict,
                    ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Builder(
                          builder: (context) {
                            // 创建于/更新于/完成于：放在「备注」标题文字正上方。
                            final metaCard = _liveCard ?? widget.card;
                            final timestamps = formatCardDetailTimestamps(
                              createdAt: metaCard.createdAt,
                              updatedAt: metaCard.updatedAt,
                              completedAt: metaCard.completed
                                  ? metaCard.completedAt
                                  : null,
                            );
                            if (timestamps == null) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                timestamps,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          },
                        ),
                        CardDetailAgentModelSection(
                          agentEngine: _agentEngine,
                          agentModelId: _agentModelId,
                          agentModelParamValues: _agentModelParamValues,
                          agentAllowDirtyWorkspace: _agentAllowDirtyWorkspace,
                          agentEnableSandbox: _agentEnableSandbox,
                          onChanged: ({
                            agentEngine,
                            agentModelId,
                            agentModelParamValues = const {},
                            agentAllowDirtyWorkspace,
                            agentEnableSandbox,
                          }) {
                            _safeSetState(() {
                              _agentEngine = agentEngine;
                              _agentModelId = agentModelId;
                              _agentModelParamValues = agentModelParamValues;
                              _agentAllowDirtyWorkspace =
                                  agentAllowDirtyWorkspace;
                              _agentEnableSandbox = agentEnableSandbox;
                            });
                          },
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: CardAgentConversationSection(
                            cardId: widget.card.id,
                            onSubmittedClose: _saveAndCloseAfterAgentFollowUp,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text('备注', style: theme.textTheme.titleSmall),
                            const Spacer(),
                            IconButton(
                              tooltip: '放大编辑',
                              onPressed: _openDescriptionExpanded,
                              icon: const Icon(
                                Icons.open_in_full,
                                size: 20,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            TextButton(
                              onPressed: () => _safeSetState(
                                () => _previewMarkdown = !_previewMarkdown,
                              ),
                              child: Text(
                                _previewMarkdown ? '编辑' : '预览',
                              ),
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
                        Row(
                          children: [
                            Text('标签', style: theme.textTheme.titleSmall),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => showLabelEditorDialog(context),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('编辑'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final label in allLabels)
                              Tooltip(
                                message: label.description ?? label.name,
                                child: FilterChip(
                                  label: Text(label.name),
                                  selected: _labels.contains(label.key),
                                  onSelected: (_) => _toggleLabel(label.key),
                                  backgroundColor:
                                      label.color.withValues(alpha: 0.12),
                                  selectedColor:
                                      label.color.withValues(alpha: 0.35),
                                  checkmarkColor: label.color,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // 验证反馈与子任务；其后依次为优先级、卡片背景色等，提交号在最底部。
                        CardDetailChecklistSection(
                          checklist: _checklist,
                          verificationFeedback: _verificationFeedback,
                          checklistInput: _checklistInput,
                          checklistFocusNode: _checklistFocusNode,
                          verificationFeedbackInput: _verificationFeedbackInput,
                          verificationFeedbackFocusNode:
                              _verificationFeedbackFocusNode,
                          onAddChecklistItem: _addChecklistItem,
                          onToggleChecklistItem: _toggleChecklistItem,
                          onRemoveChecklistItem: _removeChecklistItem,
                          onEditChecklistItem: _editChecklistItem,
                          onAddVerificationFeedbackItem:
                              _addVerificationFeedbackItem,
                          onToggleVerificationFeedbackItem:
                              _toggleVerificationFeedbackItem,
                          onRemoveVerificationFeedbackItem:
                              _removeVerificationFeedbackItem,
                          onEditVerificationFeedbackItem:
                              _editVerificationFeedbackItem,
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
                                        color: theme.colorScheme.outlineVariant,
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
                        CardDetailAttachmentsSection(
                          columnId: widget.columnId,
                          cardId: widget.card.id,
                          attachments: _attachments,
                          missingAttachmentIds:
                              _boardController.missingAttachmentIds,
                          onAttachmentsChanged: (next) =>
                              _safeSetState(() => _attachments = next),
                        ),
                        const SizedBox(height: 20),
                        CardDetailFileAttachmentsSection(
                          columnId: widget.columnId,
                          cardId: widget.card.id,
                          attachments: _fileAttachments,
                          missingAttachmentIds:
                              _boardController.missingAttachmentIds,
                          onAttachmentsChanged: (next) =>
                              _safeSetState(() => _fileAttachments = next),
                        ),
                        const SizedBox(height: 20),
                        CardDetailDueReminderSection(
                          dueDate: _dueDate,
                          reminderAt: _reminderAt,
                          onDueDateChanged: (value) =>
                              _safeSetState(() => _dueDate = value),
                          onReminderChanged: (value) =>
                              _safeSetState(() => _reminderAt = value),
                        ),
                        const SizedBox(height: 20),
                        Text('重复', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final recurrence in CardRecurrence.menuOrder)
                              ChoiceChip(
                                label: Text(recurrence.label),
                                selected: _recurrence == recurrence,
                                onSelected: (_) => _safeSetState(() {
                                  _recurrence = recurrence;
                                  if (recurrence == CardRecurrence.none) {
                                    _recurrenceInterval = 1;
                                  } else {
                                    final max =
                                        _maxRecurrenceInterval(recurrence);
                                    if (_recurrenceInterval > max) {
                                      _recurrenceInterval = max;
                                    }
                                  }
                                }),
                              ),
                          ],
                        ),
                        if (_recurrence != CardRecurrence.none) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '每隔',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(width: 8),
                              DropdownButton<int>(
                                value: () {
                                  final max =
                                      _maxRecurrenceInterval(_recurrence);
                                  return _recurrenceInterval > max
                                      ? max
                                      : _recurrenceInterval;
                                }(),
                                items: [
                                  for (var i = 1;
                                      i <= _maxRecurrenceInterval(_recurrence);
                                      i++)
                                    DropdownMenuItem(
                                      value: i,
                                      child: Text(
                                        _recurrence.intervalLabel(i),
                                      ),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  _safeSetState(
                                    () => _recurrenceInterval = value,
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20),
                        CardDetailRelationsSection(
                          cardId: widget.card.id,
                          links: _links,
                          blockedByIds: _blockedByIds,
                          relatedIds: _relatedIds,
                          onLinksChanged: (next) =>
                              _safeSetState(() => _links = next),
                          onBlockedByIdsChanged: (next) =>
                              _safeSetState(() => _blockedByIds = next),
                          onRelatedIdsChanged: (next) =>
                              _safeSetState(() => _relatedIds = next),
                          onOpenRelatedCard: ({
                            required columnId,
                            required card,
                          }) {
                            showCardDetailSheet(
                              context: context,
                              columnId: columnId,
                              card: card,
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        CardDetailCommitRefSection(
                          controller: _commitRefController,
                          onChanged: () => _safeSetState(() {}),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  CardDetailActionsBar(
                    columnId: widget.columnId,
                    cardId: widget.card.id,
                    cardTitle: widget.card.title,
                    // 新建卡详情不展示「完成」：刚建卡时用户可能误把「完成」当「保存」，
                    // 导致卡片被直接标记完成并移入已完成列。
                    showComplete: !widget.isNewCard && !_isInDoneColumn,
                    onSaveAsTemplate: _saveAsTemplate,
                    onTransfer: _transferToOtherProject,
                    onDeleted: _closeWithoutPersist,
                    onComplete: _completeAndClose,
                    onSave: _save,
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

class _DetailCompleteFlightReplica extends StatelessWidget {
  const _DetailCompleteFlightReplica({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      shadowColor: Colors.black45,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              decoration: TextDecoration.lineThrough,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
