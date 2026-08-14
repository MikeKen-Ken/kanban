import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/card_copy_text.dart';
import 'package:kanban/models/kanban_models.dart';

void main() {
  test('复制文本包含标题、备注、子任务、验证反馈与提交号', () {
    final card = KanbanCard(
      id: 'c1',
      title: '示例标题',
      description: '一段备注',
      order: 0,
      createdAt: 0,
      checklist: [
        ChecklistItem(id: '1', text: '已做', completed: true),
        ChecklistItem(id: '2', text: '未做'),
      ],
      verificationFeedback: [
        ChecklistItem(id: 'f1', text: '请补测试'),
      ],
      commitRef: 'abc1234',
    );

    expect(
      formatCardCopyText(card),
      '示例标题\n'
      '\n'
      '备注\n'
      '一段备注\n'
      '\n'
      '子任务\n'
      '- [x] 已做\n'
      '- [ ] 未做\n'
      '\n'
      '验证反馈\n'
      '- [ ] 请补测试\n'
      '\n'
      '提交号\n'
      'abc1234',
    );
  });

  test('空字段不输出对应段落', () {
    final card = KanbanCard(
      id: 'c2',
      title: '仅标题',
      order: 0,
      createdAt: 0,
    );
    expect(formatCardCopyText(card), '仅标题');
  });
}
