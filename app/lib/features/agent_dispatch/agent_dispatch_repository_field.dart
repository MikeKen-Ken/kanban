import 'package:flutter/material.dart';

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
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Row(
                          children: [
                            Expanded(
                              child: Tooltip(
                                message: path,
                                waitDuration: const Duration(milliseconds: 350),
                                child: Text(
                                  _displayPath(path),
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
      ],
    );
  }

  String _displayPath(String path) {
    const maxLength = 56;
    if (path.length <= maxLength) return path;
    const prefixLength = 26;
    const suffixLength = maxLength - prefixLength - 1;
    return '${path.substring(0, prefixLength)}…'
        '${path.substring(path.length - suffixLength)}';
  }
}
