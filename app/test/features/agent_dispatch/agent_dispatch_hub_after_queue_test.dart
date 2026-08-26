import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_after_queue.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_after_queue_field.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_hub.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_hub_after_queue.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_hub_batch.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AgentDispatchRegistry.instance.debugReset();
  });

  tearDown(AgentDispatchRegistry.instance.debugReset);

  test('总览波次按首次跟踪顺序去重仓库', () {
    final wave = AgentDispatchHubAfterQueueWave()
      ..track(projectId: 'a', repoPath: '/repo-a')
      ..track(projectId: 'b', repoPath: '/repo-b')
      ..track(projectId: 'c', repoPath: '/repo-a')
      ..track(projectId: 'd', repoPath: '  ');

    expect(wave.uniqueRepoPaths, ['/repo-a', '/repo-b']);
    expect(wave.hasTracked, isTrue);
    expect(wave.allTrackedFinished, isFalse);
  });

  test('总览波次全部记录结果后才算结束', () {
    final wave = AgentDispatchHubAfterQueueWave()
      ..track(projectId: 'a', repoPath: '/a')
      ..track(projectId: 'b', repoPath: '/b')
      ..recordOutcome(
        projectId: 'a',
        outcome: AgentDispatchHubBatchOutcome.success,
      );

    expect(wave.allTrackedFinished, isFalse);
    wave.recordOutcome(
      projectId: 'b',
      outcome: AgentDispatchHubBatchOutcome.failure,
    );
    expect(wave.allTrackedFinished, isTrue);
    expect(wave.successCount, 1);
    expect(wave.failureCount, 1);
  });

  test('Worker 取消文案解析为 cancelled', () {
    expect(
      hubAfterQueueOutcome(ok: true),
      AgentDispatchHubBatchOutcome.success,
    );
    expect(
      hubAfterQueueOutcome(ok: false, error: 'Canceled'),
      AgentDispatchHubBatchOutcome.cancelled,
    );
    expect(
      hubAfterQueueOutcome(ok: false, error: 'Cancelled'),
      AgentDispatchHubBatchOutcome.cancelled,
    );
    expect(
      hubAfterQueueOutcome(ok: false, error: '已取消'),
      AgentDispatchHubBatchOutcome.cancelled,
    );
    expect(
      hubAfterQueueOutcome(ok: false, error: 'quota'),
      AgentDispatchHubBatchOutcome.failure,
    );
  });

  test('总览完成后队列：全部成功且没有批次在跑时触发', () {
    expect(
      shouldRunHubAfterQueue(
        anyDispatchRunning: false,
        allTrackedFinished: true,
        successCount: 2,
        failureCount: 0,
        cancelledCount: 0,
        runOnFailure: false,
        queueNonEmpty: true,
      ),
      isTrue,
    );
  });

  test('总览完成后队列：仍有批次在跑时不触发', () {
    expect(
      shouldRunHubAfterQueue(
        anyDispatchRunning: true,
        allTrackedFinished: true,
        successCount: 1,
        failureCount: 0,
        cancelledCount: 0,
        runOnFailure: true,
        queueNonEmpty: true,
      ),
      isFalse,
    );
  });

  test('总览完成后队列：全部取消不触发', () {
    expect(
      shouldRunHubAfterQueue(
        anyDispatchRunning: false,
        allTrackedFinished: true,
        successCount: 0,
        failureCount: 0,
        cancelledCount: 2,
        runOnFailure: true,
        queueNonEmpty: true,
      ),
      isFalse,
    );
  });

  test('总览完成后队列：部分成功部分取消仍触发', () {
    expect(
      shouldRunHubAfterQueue(
        anyDispatchRunning: false,
        allTrackedFinished: true,
        successCount: 1,
        failureCount: 0,
        cancelledCount: 1,
        runOnFailure: false,
        queueNonEmpty: true,
      ),
      isTrue,
    );
  });

  test('总览完成后队列：有失败且勾选失败后仍执行时触发', () {
    expect(
      shouldRunHubAfterQueue(
        anyDispatchRunning: false,
        allTrackedFinished: true,
        successCount: 1,
        failureCount: 1,
        cancelledCount: 0,
        runOnFailure: true,
        queueNonEmpty: true,
      ),
      isTrue,
    );
  });

  test('总览完成后队列：有失败且取消勾选时不触发', () {
    expect(
      shouldRunHubAfterQueue(
        anyDispatchRunning: false,
        allTrackedFinished: true,
        successCount: 1,
        failureCount: 1,
        cancelledCount: 0,
        runOnFailure: false,
        queueNonEmpty: true,
      ),
      isFalse,
    );
  });

  test('总览完成后队列为空不触发', () {
    expect(
      shouldRunHubAfterQueue(
        anyDispatchRunning: false,
        allTrackedFinished: true,
        successCount: 1,
        failureCount: 0,
        cancelledCount: 0,
        runOnFailure: true,
        queueNonEmpty: false,
      ),
      isFalse,
    );
  });

  test('总览队列含休眠/关机时从项目队列去掉对应步骤', () {
    const projectSteps = [
      AgentDispatchAfterStep.gitPush,
      AgentDispatchAfterStep.hibernate,
      AgentDispatchAfterStep.shutdown,
    ];

    expect(
      applyHubAfterQueueDeferral(
        projectSteps,
        hubWavePending: false,
        hubSteps: const [AgentDispatchAfterStep.shutdown],
      ),
      projectSteps,
    );
    expect(
      applyHubAfterQueueDeferral(
        projectSteps,
        hubWavePending: true,
        hubSteps: const [AgentDispatchAfterStep.webdavUpload],
      ),
      projectSteps,
    );
    expect(
      applyHubAfterQueueDeferral(
        projectSteps,
        hubWavePending: true,
        hubSteps: const [AgentDispatchAfterStep.shutdown],
      ),
      [AgentDispatchAfterStep.gitPush, AgentDispatchAfterStep.hibernate],
    );
    expect(
      applyHubAfterQueueDeferral(
        projectSteps,
        hubWavePending: true,
        hubSteps: const [
          AgentDispatchAfterStep.hibernate,
          AgentDispatchAfterStep.shutdown,
        ],
      ),
      [AgentDispatchAfterStep.gitPush],
    );
  });

  test('全部总览批次结束后执行总览完成后队列，并推送每个仓库', () async {
    final hub = AgentDispatchRegistry.instance.hubAfterQueue
      ..trackHubStart(projectId: 'a', repoPath: '/repo-a')
      ..trackHubStart(projectId: 'b', repoPath: '/repo-b')
      ..recordOutcome(
        projectId: 'a',
        outcome: AgentDispatchHubBatchOutcome.success,
      )
      ..recordOutcome(
        projectId: 'b',
        outcome: AgentDispatchHubBatchOutcome.success,
      );

    final uploaded = <int>[];
    final pushed = <List<String>>[];
    await executeAgentDispatchHubAfterQueue(
      anyDispatchRunning: () => false,
      resolveQueue: () async => (
        steps: const [
          AgentDispatchAfterStep.webdavUpload,
          AgentDispatchAfterStep.gitPush,
        ],
        runOnFailure: true,
      ),
      hostForRepos: (repos) => AgentDispatchAfterQueueHost(
        uploadAll: () async => uploaded.add(1),
        gitPush: () async => pushed.add(repos),
        hibernate: () async => fail('不应休眠'),
        shutdown: () async => fail('不应关机'),
      ),
    );

    expect(uploaded, [1]);
    expect(pushed, [
      ['/repo-a', '/repo-b'],
    ]);
    expect(hub.pending, isFalse);
    expect(hub.running, isFalse);
  });

  test('执行总览队列期间又有批次时保留波次', () async {
    final hub = AgentDispatchRegistry.instance.hubAfterQueue
      ..trackHubStart(projectId: 'a', repoPath: '/repo-a')
      ..recordOutcome(
        projectId: 'a',
        outcome: AgentDispatchHubBatchOutcome.success,
      );

    var running = false;
    await executeAgentDispatchHubAfterQueue(
      anyDispatchRunning: () => running,
      resolveQueue: () async => (
        steps: const [AgentDispatchAfterStep.webdavUpload],
        runOnFailure: true,
      ),
      hostForRepos: (repos) => AgentDispatchAfterQueueHost(
        uploadAll: () async {
          hub.trackHubStart(projectId: 'b', repoPath: '/repo-b');
          running = true;
        },
        gitPush: () async => fail('不应推送'),
        hibernate: () async => fail('不应休眠'),
        shutdown: () async => fail('不应关机'),
      ),
    );

    expect(hub.pending, isTrue);
    expect(hub.wave.projectIds, ['a', 'b']);
    expect(hub.running, isFalse);
  });

  test('仍有其它批次在跑时不执行总览完成后队列', () async {
    AgentDispatchRegistry.instance.hubAfterQueue
      ..trackHubStart(projectId: 'a', repoPath: '/repo-a')
      ..recordOutcome(
        projectId: 'a',
        outcome: AgentDispatchHubBatchOutcome.success,
      );

    var ran = false;
    await executeAgentDispatchHubAfterQueue(
      anyDispatchRunning: () => true,
      resolveQueue: () async => (
        steps: const [AgentDispatchAfterStep.webdavUpload],
        runOnFailure: true,
      ),
      hostForRepos: (repos) => AgentDispatchAfterQueueHost(
        uploadAll: () async => ran = true,
        gitPush: () async => fail('不应推送'),
        hibernate: () async => fail('不应休眠'),
        shutdown: () async => fail('不应关机'),
      ),
    );

    expect(ran, isFalse);
    expect(AgentDispatchRegistry.instance.hubAfterQueue.pending, isTrue);
  });

  testWidgets('总览显示完成后队列编辑器', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AgentDispatchHubView(
          items: const [
            AgentDispatchHubItem(
              projectId: 'a',
              title: '项目甲',
              running: false,
            ),
          ],
          onClose: () {},
          onOpenProject: (_) {},
          onRunProject: (_) async {},
          onStopProject: (_) async {},
          afterQueueStatus:
              'Completion queue waits until every running batch finishes',
          afterQueuePane: AgentDispatchAfterQueueField(
            steps: const [AgentDispatchAfterStep.hibernate],
            enabled: true,
            description:
                'These actions run after every currently running dispatch batch finishes.',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Completion queue'), findsOneWidget);
    expect(
      find.text(
        'These actions run after every currently running dispatch batch finishes.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Completion queue waits until every running batch finishes'),
      findsOneWidget,
    );
    expect(find.text('1. Hibernate'), findsOneWidget);
  });
}
