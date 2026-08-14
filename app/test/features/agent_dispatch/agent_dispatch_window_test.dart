import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_window.dart';

void main() {
  setUp(AgentDispatchWindow.resetForTest);
  tearDown(AgentDispatchWindow.resetForTest);

  testWidgets('关闭工作台只隐藏窗口，不销毁内容', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AgentDispatchWindowHost(
          panel: Text('工作台内容'),
          child: Text('主界面'),
        ),
      ),
    );

    expect(find.text('主界面'), findsOneWidget);
    expect(find.text('工作台内容'), findsNothing);

    AgentDispatchWindow.show();
    await tester.pump();
    expect(find.text('工作台内容'), findsOneWidget);

    AgentDispatchWindow.hide();
    await tester.pump();
    expect(find.text('工作台内容'), findsNothing);
    expect(
      find.text('工作台内容', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('主界面'), findsOneWidget);
  });

  testWidgets('再次打开仍是同一份工作台 State', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AgentDispatchWindowHost(
          panel: _KeepAliveMarker(),
          child: SizedBox.shrink(),
        ),
      ),
    );

    AgentDispatchWindow.show();
    await tester.pump();
    final state = tester.state<_KeepAliveMarkerState>(
      find.byType(_KeepAliveMarker),
    );
    state.mark = 'kept';

    AgentDispatchWindow.hide();
    await tester.pump();
    AgentDispatchWindow.show();
    await tester.pump();

    expect(
      tester.state<_KeepAliveMarkerState>(find.byType(_KeepAliveMarker)).mark,
      'kept',
    );
  });

  testWidgets('工作台内下拉菜单可正常选择', (tester) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AgentDispatchWindowHost(
          panel: AlertDialog(
            content: DropdownButtonFormField<String>(
              initialValue: 'a',
              items: const [
                DropdownMenuItem(value: 'a', child: Text('选项 A')),
                DropdownMenuItem(value: 'b', child: Text('选项 B')),
              ],
              onChanged: (value) => selected = value,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const SizedBox.shrink(),
      ),
    );

    AgentDispatchWindow.show();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    await tester.tap(find.text('选项 B').last);
    await tester.pumpAndSettle();

    expect(selected, 'b');
  });

  testWidgets('builder 插槽中悬停带 tooltip 的按钮能显示文案，不出现巨大灰板',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AgentDispatchWindowHost(
          panel: IconButton(
            tooltip: '选择目录',
            onPressed: () {},
            icon: const Icon(Icons.folder_open),
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const SizedBox.shrink(),
      ),
    );

    AgentDispatchWindow.show();
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byIcon(Icons.folder_open)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('选择目录'), findsOneWidget);

    final tooltipBox = tester.getSize(
      find
          .ancestor(
            of: find.text('选择目录'),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(tooltipBox.width, lessThan(240));
    expect(tooltipBox.height, lessThan(80));
  });

  testWidgets('Esc 在项目工作台先回到总览再关闭', (tester) async {
    AgentDispatchWindow.showHub();
    AgentDispatchWindow.openProject('p1');
    expect(AgentDispatchWindow.selectedProjectId.value, 'p1');
    expect(AgentDispatchWindow.hideIfVisible(), isTrue);
    expect(AgentDispatchWindow.visible.value, isTrue);
    expect(AgentDispatchWindow.selectedProjectId.value, isNull);
    expect(AgentDispatchWindow.hideIfVisible(), isTrue);
    expect(AgentDispatchWindow.visible.value, isFalse);
  });
}

class _KeepAliveMarker extends StatefulWidget {
  const _KeepAliveMarker();

  @override
  State<_KeepAliveMarker> createState() => _KeepAliveMarkerState();
}

class _KeepAliveMarkerState extends State<_KeepAliveMarker> {
  String mark = 'fresh';

  @override
  Widget build(BuildContext context) => Text(mark);
}
