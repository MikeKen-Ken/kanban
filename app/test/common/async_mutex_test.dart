import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/common/async_mutex.dart';

void main() {
  test('AsyncMutex 串行执行临界区', () async {
    final mutex = AsyncMutex();
    final order = <int>[];

    final first = mutex.guard(() async {
      order.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      order.add(2);
    });
    final second = mutex.guard(() async {
      order.add(3);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      order.add(4);
    });

    await Future.wait([first, second]);
    expect(order, [1, 2, 3, 4]);
  });
}
