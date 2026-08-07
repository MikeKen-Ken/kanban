import '../../models/kanban_models.dart';
import '../kanban/kanban_labels.dart';
import '../project/projects_manifest.dart';
import 'card_reference.dart';

List<CardReference> buildCardReferences({
  required ProjectsManifest manifest,
  required Map<String, KanbanBoard> boards,
  List<KanbanLabel> customLabels = const [],
}) {
  final projectNames = {
    for (final project in manifest.projects) project.id: project.title,
  };
  final references = <CardReference>[];
  for (final boardEntry in boards.entries) {
    final projectId = boardEntry.key;
    for (final column in boardEntry.value.columns) {
      for (final card in column.cards) {
        references.add(
          CardReference(
            projectId: projectId,
            projectName: projectNames[projectId] ?? boardEntry.value.title,
            columnId: column.id,
            columnName: column.title,
            cardId: card.id,
            title: card.title,
            description: card.description,
            labelIds: [...card.labels],
            labelNames: [
              for (final key in card.labels)
                if (findKanbanLabel(key, customLabels) case final label?)
                  label.name,
            ],
            checklistTexts: [
              for (final item in card.checklist) item.text,
            ],
            verificationFeedbackTexts: [
              for (final item in card.verificationFeedback) item.text,
            ],
            priority: card.priority.name,
            completed: card.completed,
            dueDate: card.dueDate,
            createdAt: card.createdAt,
            updatedAt: card.updatedAt,
            order: card.order,
            blockedByIds: [...card.blockedByIds],
            relatedIds: [...card.relatedIds],
            links: [
              for (final link in card.sortedLinks)
                {
                  'id': link.id,
                  'url': link.url,
                  if (link.title.isNotEmpty) 'title': link.title,
                },
            ],
            source: card,
          ),
        );
      }
    }
  }
  return references;
}
