import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_log_buffer.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_log_refresh_scheduler.dart';

void main() {
  test('高频日志只保留行数上限内的最新内容', () {
    final buffer = AgentDispatchLogBuffer(maxLines: 3000);

    buffer.addLines(List.generate(50000, (index) => 'line $index'));

    expect(buffer.length, 3000);
    expect(buffer.text, isNot(contains('line 46999')));
    expect(buffer.text, contains('line 47000'));
    expect(buffer.text, endsWith('line 49999'));
  });

  test('超长单行也受字符上限约束', () {
    final buffer = AgentDispatchLogBuffer(maxCharacters: 100);

    buffer.addLines(['prefix', 'x' * 200]);

    expect(buffer.text.length, lessThanOrEqualTo(100));
    expect(buffer.text, 'x' * 100);
  });

  test('载入旧日志时保留最新部分', () {
    final buffer = AgentDispatchLogBuffer(maxLines: 2);

    buffer.replaceWith('old\nrecent\nlatest');

    expect(buffer.text, 'recent\nlatest');
  });

  testWidgets('界面刷新调度会合并短时间内的重复通知', (tester) async {
    final scheduler = AgentDispatchLogRefreshScheduler();
    var refreshCount = 0;

    scheduler.schedule(() => refreshCount++);
    scheduler.schedule(() => refreshCount++);
    await tester.pump(const Duration(milliseconds: 99));
    expect(refreshCount, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(refreshCount, 1);

    scheduler.schedule(() => refreshCount++);
    scheduler.cancel();
    await tester.pump(const Duration(milliseconds: 100));
    expect(refreshCount, 1);
  });
}
