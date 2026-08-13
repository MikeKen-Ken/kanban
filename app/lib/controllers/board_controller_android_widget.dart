part of 'board_controller.dart';

extension BoardControllerAndroidWidget on BoardController {
  void scheduleAndroidHomeWidgetRefresh() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(_refreshAndroidHomeWidget());
  }

  Future<void> _refreshAndroidHomeWidget() async {
    try {
      final currentBoard = board;
      final projectId = activeProjectId;
      if (currentBoard == null || projectId == null) return;
      final projectName =
          manifest?.findById(projectId)?.title ?? currentBoard.title;
      final snapshot = buildAndroidWidgetSnapshot(
        board: currentBoard,
        projectName: projectName,
      );
      await AndroidWidgetBridge.publish(snapshot);
    } catch (error) {
      debugPrint('刷新安卓小组件失败：$error');
    }
  }
}
