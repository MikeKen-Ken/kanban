import 'package:flutter/material.dart';

class AgentDispatchRepositoryField extends StatelessWidget {
  const AgentDispatchRepositoryField({
    required this.controller,
    required this.paths,
    required this.enabled,
    required this.onChanged,
    required this.onPickDirectory,
    required this.onDeleteCurrent,
    this.errorText,
    super.key,
  });

  final TextEditingController controller;
  final List<String> paths;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onPickDirectory;
  final VoidCallback? onDeleteCurrent;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            decoration: InputDecoration(
              hintText: '本机仓库根目录',
              errorText: errorText,
              suffixIcon: PopupMenuButton<String>(
                tooltip: '展开历史仓库',
                enabled: enabled && paths.isNotEmpty,
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (path) {
                  controller.text = path;
                  onChanged(path);
                },
                itemBuilder: (context) => [
                  for (final path in paths)
                    PopupMenuItem(
                      value: path,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
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
        IconButton(
          tooltip: '从历史仓库中删除',
          onPressed: enabled ? onDeleteCurrent : null,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}
