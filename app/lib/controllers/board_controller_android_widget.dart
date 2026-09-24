part of 'board_controller.dart';

extension BoardControllerAndroidWidget on BoardController {
  void scheduleAndroidHomeWidgetRefresh() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _widgetRefreshRequested = true;
    if (!_widgetRefreshRunning) unawaited(_runAndroidHomeWidgetRefresh());
  }

  Future<void> _runAndroidHomeWidgetRefresh() async {
    _widgetRefreshRunning = true;
    while (_widgetRefreshRequested) {
      _widgetRefreshRequested = false;
      await _refreshAndroidHomeWidget();
    }
    _widgetRefreshRunning = false;
  }

  Future<void> _refreshAndroidHomeWidget() async {
    try {
      final projects = manifest?.projects;
      if (projects == null || projects.isEmpty) return;
      final snapshots = <Map<String, dynamic>>[];
      for (final project in projects) {
        final projectBoard = await loadBoardSnapshot(project.id);
        if (projectBoard == null) continue;
        snapshots.add({
          'id': project.id,
          'title': project.title,
          'snapshot': buildAndroidWidgetSnapshot(
            board: projectBoard,
            projectName: project.title,
          ).toJson(),
        });
      }
      await AndroidWidgetBridge().updateProjects({
        'activeProjectId': activeProjectId,
        'projects': snapshots,
      });
    } catch (error) {
      debugPrint('Failed to refresh Android home widget: $error');
    }
  }
}
