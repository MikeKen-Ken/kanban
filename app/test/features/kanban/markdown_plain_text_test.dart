import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/markdown_plain_text.dart';

void main() {
  group('markdownToPlainText', () {
    test('空字符串', () {
      expect(markdownToPlainText(''), '');
    });

    test('去除标题、粗斜体与列表标记', () {
      const md = '''
# 标题
这是 **粗体** 与 *斜体*
- 一项
- 二项
''';
      expect(
        markdownToPlainText(md),
        '标题 这是 粗体 与 斜体 一项 二项',
      );
    });

    test('链接保留可见文字', () {
      expect(
        markdownToPlainText('见 [文档](https://example.com) 说明'),
        '见 文档 说明',
      );
    });

    test('行内代码与代码块去围栏', () {
      expect(
        markdownToPlainText('用 `code` 即可'),
        '用 code 即可',
      );
      expect(
        markdownToPlainText('```\nprint(1)\n```\n后续'),
        'print(1) 后续',
      );
    });

    test('纯 Markdown 标记去尽后为空', () {
      expect(markdownToPlainText('***'), '');
      expect(markdownToPlainText('---'), '');
    });
  });
}
