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
    description: '为像素画与精灵资源项目附加 Aseprite MCP',
    color: Color(0xFF7C4DFF),
  ),
  ProjectMcpTagOption(
    key: 'chrome-devtools',
    name: 'Chrome 调试',
    description: '为 Web 调试项目附加 Chrome DevTools MCP',
    color: Color(0xFF4285F4),
  ),
  ProjectMcpTagOption(
    key: 'tavily',
    name: 'Tavily',
    description: '为需要联网检索的项目附加 Tavily MCP',
    color: Color(0xFF0F766E),
  ),
  ProjectMcpTagOption(
    key: 'unity',
    name: 'Unity',
    description: '为 Unity 项目附加 Unity MCP',
    color: Color(0xFF455A64),
  ),
  ProjectMcpTagOption(
    key: 'cocos',
    name: 'Cocos',
    description: '为 Cocos 项目附加 Cocos Creator MCP',
    color: Color(0xFF00838F),
  ),
  ProjectMcpTagOption(
    key: 'node_repl',
    name: 'Node REPL',
    description: '为脚本与浏览器辅助项目附加 Node REPL',
    color: Color(0xFF558B2F),
  ),
];

const kProjectMcpTagKeys = <String>{
  'aseprite',
  'chrome-devtools',
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
