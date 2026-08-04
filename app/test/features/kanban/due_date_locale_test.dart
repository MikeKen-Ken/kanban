import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  testWidgets('未初始化 zh_CN 时格式化到期日会抛错并撑出超高 ErrorWidget',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              const Text('上一张正常卡'),
              Builder(
                builder: (context) {
                  // 复现看板卡片到期日那一行的真实调用
                  final label =
                      DateFormat.MMMd('zh_CN').format(DateTime(2026, 11, 11));
                  return Text(label);
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final thrown = tester.takeException();
    expect(thrown, isNotNull);
    expect('$thrown', contains('Locale data has not been initialized'));
    expect(find.byType(ErrorWidget), findsOneWidget);

    final errorSize = tester.getSize(find.byType(ErrorWidget));
    expect(
      errorSize.height,
      greaterThan(400),
      reason: '未捕获的 LocaleDataException 会渲染成很长的错误条',
    );
  });

  testWidgets('初始化 zh_CN 后到期日可正常显示且高度受控', (tester) async {
    await initializeDateFormatting('zh_CN');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        home: Scaffold(
          body: ListView(
            children: [
              const Text('上一张正常卡'),
              Builder(
                builder: (context) {
                  final label =
                      DateFormat.MMMd('zh_CN').format(DateTime(2026, 11, 11));
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(label),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.textContaining('11'), findsWidgets);

    final cardSize = tester.getSize(find.byType(Card));
    expect(cardSize.height, lessThan(120));
  });
}
