import 'package:flutter/material.dart';

import 'agent_dispatch_hub.dart';
import 'agent_dispatch_panel.dart';
import 'agent_dispatch_window.dart';

/// 总览与各项目工作台的保活切换。
class AgentDispatchShell extends StatelessWidget {
  const AgentDispatchShell({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AgentDispatchWindow.selectedProjectId,
        AgentDispatchWindow.openedProjectIds,
      ]),
      builder: (context, _) {
        final selected = AgentDispatchWindow.selectedProjectId.value;
        final opened = AgentDispatchWindow.openedProjectIds.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Offstage(
              offstage: selected != null,
              child: ExcludeFocus(
                excluding: selected != null,
                child: const AgentDispatchHub(),
              ),
            ),
            for (final projectId in opened)
              Offstage(
                offstage: selected != projectId,
                child: ExcludeFocus(
                  excluding: selected != projectId,
                  child: AgentDispatchPanel(projectId: projectId),
                ),
              ),
          ],
        );
      },
    );
  }
}
