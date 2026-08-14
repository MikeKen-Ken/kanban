import 'package:flutter/material.dart';

import 'adaptive_popup_menu.dart';
import 'agent_dispatch_field_style.dart';

class AgentDispatchRepositoryField extends StatelessWidget {
  const AgentDispatchRepositoryField({
    required this.controller,
    required this.paths,
    required this.enabled,
    required this.onChanged,
    required this.onPickDirectory,
    required this.onDeletePath,
    this.errorText,
    super.key,
  });

  final TextEditingController controller;
  final List<String> paths;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onPickDirectory;
  final ValueChanged<String> onDeletePath;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menuWidth = adaptivePopupMenuWidth(
      context: context,
      labels: paths,
      trailingWidth: kAdaptivePopupMenuDeleteButtonWidth,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            style: agentDispatchFieldTextStyle(theme),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              hintText: '本机仓库根目录',
              hintStyle: agentDispatchFieldHintStyle(theme),
              errorText: errorText,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 28,
                maxWidth: 28,
                minHeight: 28,
                maxHeight: 28,
              ),
              suffixIcon: PopupMenuButton<String>(
                tooltip: '展开历史仓库',
                enabled: enabled && paths.isNotEmpty,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(width: menuWidth),
                iconSize: 20,
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (path) {
                  controller.text = path;
                  onChanged(path);
                },
                itemBuilder: (context) {
                  final itemWidth = menuWidth - kAdaptivePopupMenuItemPadding;
                  return [
                    for (final path in paths)
                      PopupMenuItem(
                        value: path,
                        child: SizedBox(
                          width: itemWidth,
                        child: Row(
                          children: [
                            Expanded(
                              child: Tooltip(
                                message: path,
                                waitDuration: const Duration(milliseconds: 350),
                                child: Text(
                                  path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '删除此历史仓库',
                              visualDensity: VisualDensity.compact,
                              iconSize: 18,
                              onPressed: () {
                                Navigator.of(context).pop();
                                onDeletePath(path);
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ];
                },
              ),
            ),
            onChanged: onChanged,
          ),
        ),
        IconButton(
          tooltip: '选择目录',
          onPressed: enabled ? onPickDirectory : null,
          icon: const Icon(Icons.folder_open),
        ),
      ],
    );
  }
}
