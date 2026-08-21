import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../project/projects_manifest.dart';

/// 弹出目标项目选择；确认后执行跨项目转移。
///
/// 成功返回 `true`；取消或失败返回 `false`。
Future<bool> showTransferCardToProjectFlow({
  required BuildContext context,
  required String columnId,
  required String cardId,
  String? cardTitle,
}) async {
  final controller = context.read<BoardController>();
  final currentId = controller.uiActiveProjectId ?? controller.activeProjectId;
  final targets = controller.projects
      .where((p) => p.id != currentId)
      .toList(growable: false);

  if (targets.isEmpty) {
    showAppSnackBar(context, message: 'There are no other projects to move to');
    return false;
  }

  final picked = await showModalBottomSheet<ProjectEntry>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                cardTitle == null || cardTitle.trim().isEmpty
                    ? 'Move to project'
                    : 'Move "$cardTitle" to…',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: targets.length,
                itemBuilder: (context, index) {
                  final project = targets[index];
                  return ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(project.title),
                    onTap: () => Navigator.pop(ctx, project),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );

  if (picked == null || !context.mounted) return false;

  final error = await controller.transferCardToProject(
    fromColumnId: columnId,
    cardId: cardId,
    targetProjectId: picked.id,
  );
  if (!context.mounted) return false;
  if (error != null) {
    showAppSnackBar(context, message: error);
    return false;
  }
  showAppSnackBar(context, message: 'Moved to "${picked.title}"');
  return true;
}
