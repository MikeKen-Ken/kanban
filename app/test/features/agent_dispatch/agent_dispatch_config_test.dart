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
      expect(parameter.options.first.displayName, 'Low');
    });

    test('兼容旧版标量参数值并忽略空值', () {
      final parameter = AgentDispatchModelParameter.fromJson({
        'id': 'reasoning_effort',
        'values': ['low', null, '', 'high'],
      });

      expect(parameter.values, ['low', 'high']);
    });
  });

  test('读取模型官方名称与默认变体', () {
    final model = AgentDispatchModelInfo.fromJson({
      'id': 'composer-2.5',
      'displayName': 'Composer 2.5',
      'variants': [
        {
          'displayName': 'Fast',
          'isDefault': true,
          'params': [
            {'id': 'fast', 'value': 'true'},
          ],
        },
      ],
    });

    expect(model.displayName, 'Composer 2.5');
    expect(model.defaultVariant?.displayName, 'Fast');
    expect(model.defaultVariant?.params, {'fast': 'true'});
  });

  test('失效的模型 id 回退到目录首项', () {
    const models = [
      AgentDispatchModelInfo(id: 'composer-2.5'),
      AgentDispatchModelInfo(id: 'gpt-5.5'),
    ];

    expect(
        resolveAgentDispatchModelId(models, 'retired-model'), 'composer-2.5');
    expect(resolveAgentDispatchModelId(models, 'gpt-5.5'), 'gpt-5.5');
    expect(resolveAgentDispatchModelId(const [], 'gpt-5.5'), isNull);
  });

  test('失效的模型 id 优先回退到 Composer 2.5 而不是目录首项', () {
    const models = [
      AgentDispatchModelInfo(id: 'gpt-5.5'),
      AgentDispatchModelInfo(id: 'composer-2.5'),
    ];
    expect(
      resolveAgentDispatchModelId(models, 'retired-model'),
      'composer-2.5',
    );
  });
}
