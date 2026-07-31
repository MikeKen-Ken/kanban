import '../project/project_settings.dart';
import '../project/projects_manifest.dart';
import '../trash/trash_models.dart';
import '../../models/kanban_models.dart';

/// 项目工作区快照，用于同步与三路合并
class ProjectWorkspaceSnapshot {
  const ProjectWorkspaceSnapshot({
    required this.manifest,
    required this.boards,
    required this.settings,
    this.projectTrash = const {},
    this.appTrash = TrashBin.empty,
  });

  final ProjectsManifest manifest;
  final Map<String, KanbanBoard> boards;
  final Map<String, ProjectSettings> settings;
  final Map<String, TrashBin> projectTrash;
  final TrashBin appTrash;

  Map<String, dynamic> toJson() => {
        'manifest': manifest.toJson(),
        'boards': boards.map((k, v) => MapEntry(k, v.toJson())),
        'settings': settings.map((k, v) => MapEntry(k, v.toJson())),
        'projectTrash':
            projectTrash.map((k, v) => MapEntry(k, v.toJson())),
        'appTrash': appTrash.toJson(),
      };

  factory ProjectWorkspaceSnapshot.fromJson(Map<String, dynamic> json) {
    final boardsRaw = json['boards'] as Map<String, dynamic>? ?? {};
    final settingsRaw = json['settings'] as Map<String, dynamic>? ?? {};
    final trashRaw = json['projectTrash'] as Map<String, dynamic>? ?? {};
    return ProjectWorkspaceSnapshot(
      manifest: ProjectsManifest.fromJson(
        json['manifest'] as Map<String, dynamic>? ?? const {},
      ),
      boards: boardsRaw.map(
        (k, v) => MapEntry(k, KanbanBoard.fromJson(v as Map<String, dynamic>)),
      ),
      settings: settingsRaw.map(
        (k, v) =>
            MapEntry(k, ProjectSettings.fromJson(v as Map<String, dynamic>)),
      ),
      projectTrash: trashRaw.map(
        (k, v) => MapEntry(k, TrashBin.fromJson(v as Map<String, dynamic>)),
      ),
      appTrash: json['appTrash'] == null
          ? TrashBin.empty
          : TrashBin.fromJson(json['appTrash'] as Map<String, dynamic>),
    );
  }

  int countCardConflicts() {
    var n = 0;
    for (final board in boards.values) {
      for (final col in board.columns) {
        for (final card in col.cards) {
          if (card.hasConflict) n++;
        }
      }
    }
    return n;
  }
}
