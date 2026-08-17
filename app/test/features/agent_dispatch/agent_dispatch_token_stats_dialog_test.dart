import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Token 统计界面不含官网口径说明', () {
    final source = File(
      'lib/features/agent_dispatch/agent_dispatch_token_stats_dialog.dart',
    ).readAsStringSync();
    expect(source.contains('口径与官网'), isFalse);
    expect(source.contains('不把缓存再计入'), isFalse);
    expect(source.contains('与官网一致'), isFalse);
  });
}
