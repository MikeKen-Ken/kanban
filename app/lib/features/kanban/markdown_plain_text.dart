/// 将 Markdown 备注转为适合看板瓦片截断展示的纯文本摘要。
///
/// 仅做轻量去标记，不追求完整 CommonMark 语义；列表场景禁止渲染 Markdown。
String markdownToPlainText(String markdown) {
  if (markdown.isEmpty) return '';

  var text = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // 围栏代码块 → 保留内部纯文本
  text = text.replaceAllMapped(
    RegExp(r'```[^\n]*\n([\s\S]*?)```', multiLine: true),
    (m) => m[1] ?? '',
  );
  text = text.replaceAll(RegExp(r'```+'), '');

  // 图片 ![alt](url) → alt
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (m) => m[1] ?? '',
  );

  // 链接 [text](url) → text
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (m) => m[1] ?? '',
  );

  // 行内代码
  text = text.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (m) => m[1] ?? '',
  );

  // 标题前缀
  text = text.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

  // 引用
  text = text.replaceAll(RegExp(r'^>\s?', multiLine: true), '');

  // 无序 / 有序列表标记
  text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

  // 水平线
  text = text.replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '');

  // 粗体 / 斜体 / 删除线（先处理双标记再单标记）
  text = text.replaceAllMapped(
    RegExp(r'(\*\*|__)(.+?)\1'),
    (m) => m[2] ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'(~~)(.+?)\1'),
    (m) => m[2] ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'(\*|_)([^*_\n]+?)\1'),
    (m) => m[2] ?? '',
  );

  // 压成单行摘要：空白折叠
  text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  text = text.replaceAll(RegExp(r'\n+'), ' ');
  return text.trim();
}
