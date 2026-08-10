import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../common/app_snack_bar.dart';
import '../../common/help_tip_icon.dart';
import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';

/// 打开关联卡片详情的回调（由详情页注入，避免与入口文件循环依赖）。
typedef OpenRelatedCardCallback = void Function({
  required String columnId,
  required KanbanCard card,
});

/// 外链、依赖与关联卡片区块。
class CardDetailRelationsSection extends StatelessWidget {
  const CardDetailRelationsSection({
    super.key,
    required this.cardId,
    required this.links,
    required this.blockedByIds,
    required this.relatedIds,
    required this.onLinksChanged,
    required this.onBlockedByIdsChanged,
    required this.onRelatedIdsChanged,
    required this.onOpenRelatedCard,
  });

  final String cardId;
  final List<CardLink> links;
  final List<String> blockedByIds;
  final List<String> relatedIds;
  final ValueChanged<List<CardLink>> onLinksChanged;
  final ValueChanged<List<String>> onBlockedByIdsChanged;
  final ValueChanged<List<String>> onRelatedIdsChanged;
  final OpenRelatedCardCallback onOpenRelatedCard;

  Future<void> _addLink(BuildContext context) async {
    final titleController = TextEditingController();
    final urlController = TextEditingController(text: 'https://');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加链接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: '标题（可选）'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '网址'),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    final title = titleController.text.trim();
    var url = urlController.text.trim();
    titleController.dispose();
    urlController.dispose();
    if (confirmed != true || url.isEmpty || !context.mounted) return;
    if (!url.contains('://')) url = 'https://$url';
    onLinksChanged([
      ...links,
      CardLink(
        id: const Uuid().v4(),
        url: url,
        title: title,
        order: links.length,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
  }

  Future<void> _pickRelatedCard({
    required BuildContext context,
    required String title,
    required ValueChanged<String> onPicked,
  }) async {
    final boardController = context.read<BoardController>();
    final board = boardController.board;
    if (board == null) return;
    final candidates = <({String id, String title, String column})>[];
    for (final column in board.columns) {
      for (final card in column.cards) {
        if (card.id == cardId) continue;
        candidates.add((id: card.id, title: card.title, column: column.title));
      }
    }
    if (candidates.isEmpty) {
      showAppSnackBar(context, message: '当前看板没有其他可关联的卡片');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final item in candidates)
              ListTile(
                title: Text(item.title),
                subtitle: Text(item.column),
                onTap: () => Navigator.pop(ctx, item.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onPicked(picked);
  }

  List<Widget> _relationTiles({
    required BuildContext context,
    required List<String> ids,
    required ValueChanged<String> onRemove,
  }) {
    if (ids.isEmpty) return const [];
    final boardController = context.read<BoardController>();
    return [
      for (final id in ids)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(boardController.findCardById(id)?.title ?? '未知卡片'),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => onRemove(id),
          ),
          onTap: () {
            final card = boardController.findCardById(id);
            final columnId = boardController.findColumnIdForCard(id);
            if (card == null || columnId == null) return;
            onOpenRelatedCard(columnId: columnId, card: card);
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('链接', style: theme.textTheme.titleSmall),
            const HelpTipIcon(
              message: '可添加外部网页书签（打开网址用，不是卡片之间的依赖/关联）',
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addLink(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加'),
            ),
          ],
        ),
        for (final link in links)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link),
            title: Text(link.displayTitle),
            subtitle: Text(
              link.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: '删除链接',
              onPressed: () => onLinksChanged(
                links.where((item) => item.id != link.id).toList(),
              ),
              icon: const Icon(Icons.close),
            ),
            onTap: () => launchUrl(
              Uri.parse(link.url),
              mode: LaunchMode.externalApplication,
            ),
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text('依赖（阻塞本卡）', style: theme.textTheme.titleSmall),
            const HelpTipIcon(
              message: '前置卡未完成前，本卡应视为被阻塞；点条目可跳转查看。',
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _pickRelatedCard(
                context: context,
                title: '选择阻塞本卡的前置任务',
                onPicked: (id) {
                  if (blockedByIds.contains(id) || id == cardId) return;
                  onBlockedByIdsChanged([...blockedByIds, id]);
                },
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加'),
            ),
          ],
        ),
        ..._relationTiles(
          context: context,
          ids: blockedByIds,
          onRemove: (id) => onBlockedByIdsChanged(
            blockedByIds.where((item) => item != id).toList(),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text('关联（相关卡片）', style: theme.textTheme.titleSmall),
            const HelpTipIcon(
              message: '无先后关系，仅便于跳转与追溯；不会阻塞本卡。',
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _pickRelatedCard(
                context: context,
                title: '选择关联卡片',
                onPicked: (id) {
                  if (relatedIds.contains(id) || id == cardId) return;
                  onRelatedIdsChanged([...relatedIds, id]);
                },
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加'),
            ),
          ],
        ),
        ..._relationTiles(
          context: context,
          ids: relatedIds,
          onRemove: (id) => onRelatedIdsChanged(
            relatedIds.where((item) => item != id).toList(),
          ),
        ),
      ],
    );
  }
}
