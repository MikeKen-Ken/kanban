import 'dart:async';

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

  test('AsyncMutex 仅允许同一异步调用链重入', () async {
    final mutex = AsyncMutex();
    final firstEntered = Completer<void>();
    final releaseFirst = Completer<void>();
    final secondEntered = Completer<void>();
    final order = <String>[];

    final first = mutex.guard(() async {
      order.add('first-start');
      firstEntered.complete();
      await mutex.guard(() async {
        order.add('nested');
      });
      await releaseFirst.future;
      order.add('first-end');
    });

    await firstEntered.future;
    final second = mutex.guard(() async {
      order.add('second');
      secondEntered.complete();
    });

    await Future<void>.delayed(Duration.zero);
    expect(secondEntered.isCompleted, isFalse);
    expect(order, ['first-start', 'nested']);

    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(order, ['first-start', 'nested', 'first-end', 'second']);
  });

  test('临界区派生但未等待的任务在临界区结束后必须重新排队', () async {
    final mutex = AsyncMutex();
    final startEscaped = Completer<void>();
    final blockerEntered = Completer<void>();
    final releaseBlocker = Completer<void>();
    var escapedStarted = false;
    late Future<void> escaped;

    await mutex.guard(() async {
      escaped = startEscaped.future.then(
        (_) => mutex.guard(() async {
          escapedStarted = true;
        }),
      );
    });

    final blocker = mutex.guard(() async {
      blockerEntered.complete();
      await releaseBlocker.future;
    });
    await blockerEntered.future;

    startEscaped.complete();
    await Future<void>.delayed(Duration.zero);
    expect(escapedStarted, isFalse);

    releaseBlocker.complete();
    await Future.wait([blocker, escaped]);
    expect(escapedStarted, isTrue);
  });
}
