import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/storage/json_file_io.dart';

void main() {
  test('looksLikeJsonBytes rejects all-zero payload', () {
    expect(looksLikeJsonBytes(List.filled(68, 0)), isFalse);
  });

  test('looksLikeJsonBytes accepts object json', () {
    expect(looksLikeJsonBytes(utf8.encode('{"a":1}')), isTrue);
  });

  test('tryDecodeJsonBytes returns null for null-byte file content', () {
    expect(tryDecodeJsonBytes(List.filled(68, 0)), isNull);
  });

  test('writeJsonFileAtomic then readJsonFile round trip', () async {
    final dir = await Directory.systemTemp.createTemp('kanban_json_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/sample.json');
    await writeJsonFileAtomic(file, {'hello': '世界', 'n': 1});
    final json = await readJsonFile(file);
    expect(json?['hello'], '世界');
    expect(json?['n'], 1);
  });

  test('正式文件替换中断时从完整备份恢复', () async {
    final dir = await Directory.systemTemp.createTemp('kanban_json_recovery_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/sample.json');
    final backup = File('${file.path}.bak');
    await backup.writeAsString('{"revision":7}', flush: true);

    final json = await readJsonFile(file);

    expect(json?['revision'], 7);
    expect(await file.exists(), isTrue);
    expect(await backup.exists(), isFalse);
  });
}
