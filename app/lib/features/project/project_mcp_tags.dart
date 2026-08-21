import 'package:flutter/material.dart';

/// 项目级 Agent MCP 标签；决定调度时按需附加哪些用户 MCP。
class ProjectMcpTagOption {
  const ProjectMcpTagOption({
    required this.key,
    required this.name,
    required this.description,
    required this.color,
  });

  final String key;
  final String name;
  final String description;
  final Color color;
}

const kProjectMcpTagOptions = <ProjectMcpTagOption>[
  ProjectMcpTagOption(
    key: 'aseprite',
    name: 'Aseprite',
    description: 'Add Aseprite MCP for pixel art and sprite projects',
    color: Color(0xFF7C4DFF),
  ),
  ProjectMcpTagOption(
    key: 'chrome-devtools',
    name: 'Chrome debugging',
    description: 'Add Chrome DevTools MCP for web debugging projects',
    color: Color(0xFF4285F4),
  ),
  ProjectMcpTagOption(
    key: 'hub',
    name: 'Hub MCP',
    description:
        'Add Hub MCP for projects that manage other MCP servers in Worker sessions',
    color: Color(0xFF5D4037),
  ),
  ProjectMcpTagOption(
    key: 'tavily',
    name: 'Tavily',
    description: 'Add Tavily MCP for projects that need web research',
    color: Color(0xFF0F766E),
  ),
  ProjectMcpTagOption(
    key: 'unity',
    name: 'Unity',
    description: 'Add Unity MCP for Unity projects',
    color: Color(0xFF455A64),
  ),
  ProjectMcpTagOption(
    key: 'cocos',
    name: 'Cocos',
    description: 'Add Cocos Creator MCP for Cocos projects',
    color: Color(0xFF00838F),
  ),
  ProjectMcpTagOption(
    key: 'node_repl',
    name: 'Node REPL',
    description: 'Add Node REPL for scripting and browser-assistance projects',
    color: Color(0xFF558B2F),
  ),
];

const kProjectMcpTagKeys = <String>{
  'aseprite',
  'chrome-devtools',
  'hub',
  'tavily',
  'unity',
  'cocos',
  'node_repl',
};

List<String> sanitizeProjectMcpTags(Iterable<Object?> raw) {
  final result = <String>[];
  final seen = <String>{};
  for (final item in raw) {
    if (item is! String) continue;
    final key = item.trim();
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    result.add(key);
  }
  return result;
}
