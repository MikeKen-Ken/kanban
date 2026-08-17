import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../agent_dispatch/agent_dispatch_platform.dart';
import 'remote_actions_service.dart';

/// 桌面端右上角：打开当前项目仓库远端的 Actions 列表。
class RemoteActionsToolbarButton extends StatelessWidget {
  const RemoteActionsToolbarButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!isAgentDispatchDesktop) return const SizedBox.shrink();
    return IconButton(
      tooltip: '远端 Actions',
      icon: const Icon(Icons.pending_actions_outlined),
      onPressed: () => openRemoteActionsFromToolbar(context),
    );
  }
}

Future<void> openRemoteActionsFromToolbar(BuildContext context) async {
  final controller = context.read<BoardController>();
  final projectId = controller.uiActiveProjectId ?? controller.activeProjectId;
  final result = await openRemoteActionsPage(projectId: projectId);
  if (!context.mounted) return;
  if (result.error != null) {
    showAppSnackBar(context, message: result.error!);
  }
}
