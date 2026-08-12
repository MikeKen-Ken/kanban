import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_config.dart';

void main() {
  group('AgentDispatchModelParameter.fromJson', () {
    test('读取 Cursor SDK 的对象参数值', () {
      final parameter = AgentDispatchModelParameter.fromJson({
        'id': 'reasoning_effort',
        'values': [
          {'value': 'low', 'displayName': 'Low'},
          {'value': 'medium', 'displayName': 'Medium'},
          {'value': 'high', 'displayName': 'High'},
        ],
      });

      expect(parameter.values, ['low', 'medium', 'high']);
    });

    test('兼容旧版标量参数值并忽略空值', () {
      final parameter = AgentDispatchModelParameter.fromJson({
        'id': 'reasoning_effort',
        'values': ['low', null, '', 'high'],
      });

      expect(parameter.values, ['low', 'high']);
    });
  });
}
