import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// 打开备注预览中的链接；仅允许 http(s)/mailto。
Future<void> openDescriptionMarkdownLink(String? href) async {
  if (href == null) return;
  final trimmed = href.trim();
  if (trimmed.isEmpty) return;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return;

  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https' && scheme != 'mailto') {
    return;
  }

  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// 备注 Markdown 预览：详情页与全屏放大共用，保证渲染与交互一致。
class DescriptionMarkdownPreview extends StatelessWidget {
  const DescriptionMarkdownPreview({
    super.key,
    required this.data,
    this.minHeight = 0,
    this.scrollable = false,
    this.expand = false,
  });

  final String data;

  /// 详情页预览区最小高度。
  final double minHeight;

  /// 长文在固定视口内滚动（全屏放大）。
  final bool scrollable;

  /// 占满父级约束（全屏放大的边框区域）。
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = data.trim().isEmpty ? '_No description_' : data;

    final body = MarkdownBody(
      data: source,
      selectable: true,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme),
      onTapLink: (text, href, title) {
        openDescriptionMarkdownLink(href);
      },
    );

    final content = scrollable
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: body,
          )
        : Padding(
            padding: const EdgeInsets.all(12),
            child: body,
          );

    final framed = Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: content,
    );

    if (expand) {
      return SizedBox.expand(child: framed);
    }
    return framed;
  }
}
