import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/attachments/attachment_add_validation.dart';
import 'package:kanban/features/attachments/picked_file_bytes.dart';
import 'package:kanban/features/attachments/picked_image_bytes.dart';
import 'package:kanban/models/kanban_models.dart';

Uint8List _bytes(int length) => Uint8List(length);

PickedFileBytes _file(String name, int length) => PickedFileBytes(
      bytes: _bytes(length),
      fileName: name,
    );

void main() {
  group('analyzeFileAttachmentPicks', () {
    test('合规文件无问题', () {
      final analysis = analyzeFileAttachmentPicks(
        picked: [_file('a.txt', 100)],
        currentCount: 0,
        maxCount: KanbanCard.maxFileAttachments,
      );
      expect(analysis.hasIssues, isFalse);
      expect(analysis.canForceSubmit, isFalse);
    });

    test('超大文件可执意提交', () {
      final analysis = analyzeFileAttachmentPicks(
        picked: [_file('big.bin', maxCardFileBytes + 1)],
        currentCount: 0,
        maxCount: KanbanCard.maxFileAttachments,
      );
      expect(analysis.hasIssues, isTrue);
      expect(analysis.canForceSubmit, isTrue);
      expect(
        analysis.issues.single.reason,
        contains('超过单文件'),
      );
    });

    test('空文件不可执意提交', () {
      final analysis = analyzeFileAttachmentPicks(
        picked: [_file('empty.txt', 0)],
        currentCount: 0,
        maxCount: KanbanCard.maxFileAttachments,
      );
      expect(analysis.hasIssues, isTrue);
      expect(analysis.canForceSubmit, isFalse);
    });

    test('数量超额可执意提交', () {
      final analysis = analyzeFileAttachmentPicks(
        picked: [
          _file('a.txt', 10),
          _file('b.txt', 10),
          _file('c.txt', 10),
        ],
        currentCount: KanbanCard.maxFileAttachments - 1,
        maxCount: KanbanCard.maxFileAttachments,
      );
      expect(analysis.issues.any((issue) => issue.label == '选择数量'), isTrue);
      expect(analysis.canForceSubmit, isTrue);
    });

    test('数量已满不可执意提交', () {
      final analysis = analyzeFileAttachmentPicks(
        picked: [_file('a.txt', 10)],
        currentCount: KanbanCard.maxFileAttachments,
        maxCount: KanbanCard.maxFileAttachments,
      );
      expect(analysis.canForceSubmit, isFalse);
    });
  });

  group('trimPickedAttachmentsForAdd', () {
    test('按剩余配额截取', () {
      final picked = ['a', 'b', 'c'];
      expect(trimPickedAttachmentsForAdd(picked, 2), ['a', 'b']);
      expect(trimPickedAttachmentsForAdd(picked, 5), picked);
      expect(trimPickedAttachmentsForAdd(picked, 0), isEmpty);
    });
  });

  group('analyzeImageAttachmentPicks', () {
    test('无法解码的图片不可执意提交', () {
      final analysis = analyzeImageAttachmentPicks(
        picked: [
          PickedImageBytes(bytes: _bytes(4), fileName: 'bad.jpg'),
        ],
        currentCount: 0,
        maxCount: KanbanCard.maxAttachments,
      );
      expect(analysis.hasIssues, isTrue);
      expect(analysis.canForceSubmit, isFalse);
    });
  });
}
