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
