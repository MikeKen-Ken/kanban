import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/webdav_sync/live_archive_marker.dart';

void main() {
  test('标记与字节校验一致', () {
    final bytes = Uint8List.fromList(utf8.encode('kanban'));
    final marker = LiveArchiveMarker(
      id: 'workspace',
      sizeBytes: bytes.length,
      sha256: LiveArchiveMarker.hashBytes(bytes),
    );
    expect(marker.matchesBytes(bytes), isTrue);
    expect(LiveArchiveMarker.tryParse(marker.toJson())?.id, 'workspace');
  });

  test('缺字段的标记解析为 null', () {
    expect(LiveArchiveMarker.tryParse({'id': 'workspace'}), isNull);
    expect(
      LiveArchiveMarker.tryParse({
        'id': 'workspace',
        'sizeBytes': 1,
        'sha256': 'abc',
      })?.sizeBytes,
      1,
    );
  });
}
