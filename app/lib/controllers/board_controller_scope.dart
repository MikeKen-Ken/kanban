part of 'board_controller.dart';

class _ProjectMutationScope {
  _ProjectMutationScope({
    required this.projectId,
    required this.board,
    required this.settings,
    required this.trash,
  });

  final String projectId;
  KanbanBoard? board;
  ProjectSettings settings;
  TrashBin trash;
  bool pendingNotify = false;
  bool isActive = true;
}

