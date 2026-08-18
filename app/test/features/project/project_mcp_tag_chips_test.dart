import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/project/project_mcp_tag_chips.dart';
import 'package:kanban/features/project/project_settings.dart';

void main() {
  testWidgets('已保存的项目 MCP 标签进入设置时保持选中', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProjectMcpTagChips(
            selectedKeys: ['unity', 'tavily'],
            onSelected: _noop,
          ),
        ),
      ),
    );

    expect(_chip(tester, 'Unity').selected, isTrue);
    expect(_chip(tester, 'Tavily').selected, isTrue);
    expect(_chip(tester, 'Cocos').selected, isFalse);
  });

  testWidgets('未选择时全部为未选中', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProjectMcpTagChips(
            selectedKeys: [],
            onSelected: _noop,
          ),
        ),
      ),
    );

    expect(_chip(tester, 'Unity').selected, isFalse);
    expect(_chip(tester, 'Hub MCP').selected, isFalse);
  });

  test('项目设置往返后 MCP 标签仍可用于选中回显', () {
    const saved = ProjectSettings(
      agentMcpTags: ['unity', 'tavily'],
      updatedAt: 1,
      revision: 1,
    );
    final loaded = ProjectSettings.fromJson(saved.toJson());
    expect(loaded.agentMcpTags, ['unity', 'tavily']);
    expect(loaded.agentMcpTags.contains('unity'), isTrue);
  });
}

void _noop(String key, bool selected) {}

FilterChip _chip(WidgetTester tester, String label) {
  return tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));
}
