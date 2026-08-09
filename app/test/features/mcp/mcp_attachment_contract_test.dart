import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'package:kanban/models/kanban_models.dart';

void main() {
  test('图片附件元数据包含 MCP 所需字段', () {
    final attachment = CardAttachment(
      id: 'att-1',
      fileName: 'screen.png',
      mimeType: 'image/png',
      order: 0,
      createdAt: 123,
      width: 640,
      height: 480,
    );

    expect(attachment.toJson(), {
      'id': 'att-1',
      'fileName': 'screen.png',
      'mimeType': 'image/png',
      'order': 0,
      'createdAt': 123,
      'width': 640,
      'height': 480,
    });
  });

  test('MCP ImageContent 使用标准 base64 和原始 MIME 类型', () {
    final content = ImageContent(
      data: base64Encode([1, 2, 3]),
      mimeType: 'image/jpeg',
    );

    expect(content.type, 'image');
    expect(content.data, 'AQID');
    expect(content.mimeType, 'image/jpeg');
    expect(content.toJson(), containsPair('type', 'image'));
  });
}
