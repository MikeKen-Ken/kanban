import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/card_detail_file_attachment_overflow.dart';

void main() {
  testWidgets('文件附件菜单含打开所在文件夹，缺失附件则没有', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: _OverflowHost(missing: false),
        ),
      ),
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(find.text('打开所在文件夹'), findsOneWidget);
    expect(find.text('删除文件'), findsOneWidget);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: _OverflowHost(missing: true),
        ),
      ),
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsNothing);
    expect(find.text('打开所在文件夹'), findsNothing);
    expect(find.text('删除文件'), findsOneWidget);
  });
}

class _OverflowHost extends StatelessWidget {
  const _OverflowHost({required this.missing});

  final bool missing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      itemBuilder: (_) => cardFileAttachmentOverflowItems(
        missing: missing,
        colors: colors,
      ),
    );
  }
}
