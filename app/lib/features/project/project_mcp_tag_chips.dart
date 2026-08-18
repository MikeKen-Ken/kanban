import 'package:flutter/material.dart';

import 'project_mcp_tags.dart';

/// 项目设置中的 Agent MCP 标签多选；[selectedKeys] 决定进入页面时的选中态。
class ProjectMcpTagChips extends StatelessWidget {
  const ProjectMcpTagChips({
    super.key,
    required this.selectedKeys,
    required this.onSelected,
  });

  final List<String> selectedKeys;
  final void Function(String key, bool selected) onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in kProjectMcpTagOptions)
          _chip(option, selectedKeys.contains(option.key)),
      ],
    );
  }

  Widget _chip(ProjectMcpTagOption option, bool selected) {
    return FilterChip(
      key: ValueKey('project-mcp-${option.key}'),
      label: Text(option.name),
      tooltip: option.description,
      selected: selected,
      showCheckmark: true,
      checkmarkColor: option.color,
      onSelected: (value) => onSelected(option.key, value),
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return option.color.withValues(alpha: 0.22);
        }
        return null;
      }),
      side: WidgetStateBorderSide.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return BorderSide(
          color: option.color.withValues(alpha: isSelected ? 0.85 : 0.35),
          width: isSelected ? 2 : 1,
        );
      }),
      labelStyle: TextStyle(
        color: selected ? option.color : null,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}
