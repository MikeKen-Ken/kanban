import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_config.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_model_catalog_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('模型目录缓存保留参数、显示名和默认变体', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const models = [
      AgentDispatchModelInfo(
        id: 'composer-2.5',
        displayName: 'Composer 2.5',
        parameters: [
          AgentDispatchModelParameter(
            id: 'fast',
            displayName: 'Fast',
            options: [
              AgentDispatchModelParameterOption(
                value: 'true',
                displayName: 'On',
              ),
              AgentDispatchModelParameterOption(
                value: 'false',
                displayName: 'Off',
              ),
            ],
          ),
        ],
        variants: [
          AgentDispatchModelVariant(
            displayName: 'Fast',
            isDefault: true,
            params: {'fast': 'true'},
          ),
        ],
      ),
    ];

    await prefs.saveAgentDispatchModelCatalog(models);
    final cached = prefs.loadAgentDispatchModelCatalog();

    expect(cached.single.displayName, 'Composer 2.5');
    expect(cached.single.parameters.single.options.last.displayName, 'Off');
    expect(cached.single.defaultVariant?.params, {'fast': 'true'});
  });

  test('Cursor 与 Codex 使用独立模型目录缓存', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const cursorModels = [AgentDispatchModelInfo(id: 'composer-2.5')];
    const codexModels = [AgentDispatchModelInfo(id: 'gpt-5.6-sol')];

    await prefs.saveAgentDispatchModelCatalog(cursorModels);
    await prefs.saveAgentDispatchModelCatalog(
      codexModels,
      engine: AgentDispatchEngine.codex,
    );

    expect(prefs.loadAgentDispatchModelCatalog().single.id, 'composer-2.5');
    expect(
      prefs
          .loadAgentDispatchModelCatalog(engine: AgentDispatchEngine.codex)
          .single
          .id,
      'gpt-5.6-sol',
    );
  });
}
