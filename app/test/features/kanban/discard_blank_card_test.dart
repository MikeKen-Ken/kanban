import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/discard_blank_card.dart';

void main() {
  group('shouldDiscardBlankCard', () {
    test('新建空白卡：标题与备注皆空则丢弃', () {
      expect(
        shouldDiscardBlankCard(
          editedTitle: '',
          originalTitle: '',
          editedDescription: '',
        ),
        isTrue,
      );
      expect(
        shouldDiscardBlankCard(
          editedTitle: '   ',
          originalTitle: '',
          editedDescription: '  \n\t',
        ),
        isTrue,
      );
    });

    test('仅有标题或备注时保留', () {
      expect(
        shouldDiscardBlankCard(
          editedTitle: '有标题',
          originalTitle: '',
          editedDescription: '',
        ),
        isFalse,
      );
      expect(
        shouldDiscardBlankCard(
          editedTitle: '',
          originalTitle: '',
          editedDescription: '有备注',
        ),
        isFalse,
      );
    });

    test('已有原标题：清空编辑框仍回退原标题，不丢弃', () {
      expect(
        shouldDiscardBlankCard(
          editedTitle: '',
          originalTitle: '已有卡',
          editedDescription: '',
        ),
        isFalse,
      );
      expect(
        shouldDiscardBlankCard(
          editedTitle: '   ',
          originalTitle: '已有卡',
          editedDescription: '',
        ),
        isFalse,
      );
    });

    test('标题备注空但有其它元数据时保留', () {
      expect(
        shouldDiscardBlankCard(
          editedTitle: '',
          originalTitle: '',
          editedDescription: '',
          hasOtherMetadata: true,
        ),
        isFalse,
      );
    });
  });
}
