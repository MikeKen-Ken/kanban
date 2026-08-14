import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/adaptive_popup_menu.dart';

void main() {
  testWidgets('短名称弹出菜单明显窄于长名称', (tester) async {
    late double shortWidth;
    late double longWidth;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            shortWidth = adaptivePopupMenuWidth(
              context: context,
              labels: const ['abcdefg'],
              trailingWidth: kAdaptivePopupMenuKeyTrailingWidth,
            );
            longWidth = adaptivePopupMenuWidth(
              context: context,
              labels: const [
                'a-very-long-cursor-api-key-label-that-should-expand',
              ],
              trailingWidth: kAdaptivePopupMenuKeyTrailingWidth,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(shortWidth, lessThan(longWidth));
    expect(shortWidth, lessThan(220));
    expect(longWidth, greaterThan(320));
  });

  testWidgets('超长目录不超过屏宽上限', (tester) async {
    late double width;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: Builder(
            builder: (context) {
              width = adaptivePopupMenuWidth(
                context: context,
                labels: [
                  'C:\\Users\\Administrator\\Projects\\extremely-long-directory-name\\nested\\kanban',
                ],
                trailingWidth: kAdaptivePopupMenuDeleteButtonWidth,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(width, lessThanOrEqualTo(720));
    expect(width, lessThanOrEqualTo(800 * 0.92));
  });
}
