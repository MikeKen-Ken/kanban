import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/card_detail_sheet.dart';

void main() {
  test('卡片详情禁用整页 enableDrag，避免按钮与拖拽手势竞争', () {
    expect(kCardDetailSheetEnableDrag, isFalse);
  });

  test('电脑端卡片详情比默认 640 更宽，减轻选项拥挤', () {
    expect(kCardDetailSheetMaxWidth, 880);
    expect(kCardDetailSheetMaxWidth, greaterThan(640));
  });

  testWidgets('enableDrag=false 时在按钮上垂直拖拽不关闭弹层，点击可关闭',
      (tester) async {
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    enableDrag: kCardDetailSheetEnableDrag,
                    showDragHandle: true,
                    builder: (ctx) => DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: 0.6,
                      minChildSize: 0.4,
                      maxChildSize: 0.9,
                      builder: (context, scrollController) {
                        return Material(
                          child: Column(
                            children: [
                              Expanded(
                                child: ListView(
                                  controller: scrollController,
                                  children: const [
                                    SizedBox(height: 24),
                                    Text('内容区'),
                                    SizedBox(height: 400),
                                  ],
                                ),
                              ),
                              FilledButton(
                                onPressed: () {
                                  saved = true;
                                  Navigator.pop(ctx);
                                },
                                child: const Text('保存'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.enableDrag, isFalse);
    expect(find.text('保存'), findsOneWidget);

    // 模拟电脑端在按钮上按下并垂直拖动：不应关掉弹层。
    final saveCenter = tester.getCenter(find.text('保存'));
    final gesture = await tester.startGesture(
      saveCenter,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('保存'), findsOneWidget);
    expect(saved, isFalse);

    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved, isTrue);
    expect(find.text('保存'), findsNothing);
  });
}
