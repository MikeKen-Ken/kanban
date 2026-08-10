part of 'board_controller.dart';

extension BoardControllerMutation on BoardController {

  /// 看板突变临界区：同一异步调用链可重入，UI、MCP 与同步之间严格串行。
  Future<T> _withBoardMutation<T>(Future<T> Function() action) =>
      _boardMutationMutex.guard(action);

  void _markWorkspaceChanged() {
    _backupCoordinator.markChanged();
    // 防抖 Timer 不继承当前 mutation/project Zone，触发时必须重新排队。
    Zone.root.run(_syncService.schedulePush);
  }

  /// 以指定活动来源执行操作（供 MCP 等外部写入标注来源）。
  Future<T> runWithActivitySource<T>(
    ActivitySource source,
    Future<T> Function() action,
  ) async {
    final previous = _mutationOrigin;
    _mutationOrigin = source;
    try {
      return await action();
    } finally {
      _mutationOrigin = previous;
    }
  }

  ActivitySource get _currentActivitySource {
    if (_applyingAutomation) return ActivitySource.automation;
    return _mutationOrigin;
  }

  /// 推入撤销/重做项；自动化不入栈。跨项目 MCP 写入时用 [runOnProject] 包一层以便恢复。
  void _pushUndo(
    String label,
    UndoCallback undo, {
    required UndoCallback redo,
  }) {
    if (_applyingAutomation) return;
    final source = _mutationOrigin;
    final displayLabel = source == ActivitySource.mcp ? 'MCP：$label' : label;
    final scopedProjectId = _mutatingForeignProject ? activeProjectId : null;
    if (scopedProjectId != null) {
      _undoStack.push(
        UndoEntry(
          label: displayLabel,
          undo: () => runOnProject(scopedProjectId, undo),
          redo: () => runOnProject(scopedProjectId, redo),
        ),
      );
      return;
    }
    _undoStack.push(
      UndoEntry(label: displayLabel, undo: undo, redo: redo),
    );
  }

  /// 在指定项目上下文中执行操作：不修改已持久化的 active 项目，也不把 UI 切走。
  ///
  /// 若 [projectId] 即为当前项目，直接执行 [action]。
  /// 对外项目：在独立的异步数据作用域中加载和修改，不改变 UI 当前状态。
  Future<T> runOnProject<T>(
    String projectId,
    Future<T> Function() action,
  ) async {
    return _withBoardMutation(() async {
      if (manifest?.findById(projectId) == null) {
        throw StateError('项目不存在：$projectId');
      }
      if (projectId == activeProjectId) {
        return action();
      }
      if (_projectMutationScope != null) {
        throw StateError('不可嵌套 runOnProject');
      }

      final scope = _ProjectMutationScope(
        projectId: projectId,
        board: await _repository.loadBoard(projectId),
        settings: await _repository.loadProjectSettings(projectId),
        trash: projectTrashes[projectId] ?? TrashBin.empty,
      );

      try {
        return await runZoned(
          () async {
            await _ensureReworkColumnPersisted();
            return action();
          },
          zoneValues: {_projectMutationScopeKey: scope},
        );
      } finally {
        scope.isActive = false;
        projectTrashes[projectId] = scope.trash;
        projectThemeIds[projectId] = scope.settings.themeId;
        if (scope.pendingNotify) {
          notifyListeners();
        }
      }
    });
  }
}

