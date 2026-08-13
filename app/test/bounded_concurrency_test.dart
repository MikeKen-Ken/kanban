import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/webdav_sync/bounded_concurrency.dart';

void main() {
  test('空列表立即完成', () async {
    var ran = 0;
    await runBounded<int>(const [], action: (_) async {
      ran++;
    });
    expect(ran, 0);
  });

  test('并发数不超过上限', () async {
    var inFlight = 0;
    var maxInFlight = 0;
    await runBounded(
      List<int>.generate(20, (index) => index),
      concurrency: 4,
      action: (_) async {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 15));
        inFlight--;
      },
    );
    expect(maxInFlight, 4);
  });

  test('失败后不再领取新任务并抛出首个错误', () async {
    var started = 0;
    await expectLater(
      runBounded(
        List<int>.generate(12, (index) => index),
        concurrency: 2,
        action: (index) async {
          started++;
          if (index == 0) {
            throw StateError('首个失败');
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
        },
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', '首个失败'),
      ),
    );
    expect(started, lessThan(12));
  });
}
