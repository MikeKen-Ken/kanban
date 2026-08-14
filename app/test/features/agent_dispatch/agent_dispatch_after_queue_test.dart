import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_after_queue.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('解析完成后队列时去重并保持顺序', () {
    expect(
      parseAgentDispatchAfterQueue(['webdavUpload', 'sleep', 'webdavUpload']),
      [
        AgentDispatchAfterStep.webdavUpload,
        AgentDispatchAfterStep.sleep,
      ],
    );
  });

  test('上传完成前不会进入休眠', () async {
    var uploadDone = false;
    var slept = false;
    await runAgentDispatchAfterQueue(
      steps: const [
        AgentDispatchAfterStep.webdavUpload,
        AgentDispatchAfterStep.sleep,
      ],
      host: AgentDispatchAfterQueueHost(
        uploadAll: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          uploadDone = true;
        },
        sleep: () async {
          expect(uploadDone, isTrue);
          slept = true;
        },
        shutdown: () async => fail('不应关机'),
      ),
    );
    expect(slept, isTrue);
  });

  test('上传失败时不执行后续休眠', () async {
    var slept = false;
    await expectLater(
      runAgentDispatchAfterQueue(
        steps: const [
          AgentDispatchAfterStep.webdavUpload,
          AgentDispatchAfterStep.sleep,
        ],
        host: AgentDispatchAfterQueueHost(
          uploadAll: () async => throw Exception('上传失败'),
          sleep: () async => slept = true,
          shutdown: () async {},
        ),
      ),
      throwsException,
    );
    expect(slept, isFalse);
  });

  test('保存并加载完成后队列', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const settings = AgentDispatchSettings(
      afterQueue: [
        AgentDispatchAfterStep.webdavUpload,
        AgentDispatchAfterStep.sleep,
      ],
    );

    await prefs.saveAgentDispatchSettings(settings);
    final loaded = prefs.loadAgentDispatchSettings();

    expect(loaded.afterQueue, settings.afterQueue);
  });

  test('缺少 afterQueue 的旧设置回退为空队列', () {
    final settings = AgentDispatchSettings.fromJson({});
    expect(settings.afterQueue, isEmpty);
  });
}
