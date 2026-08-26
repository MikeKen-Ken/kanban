import 'dart:async';

import 'package:flutter/foundation.dart';

import 'agent_dispatch_hub_after_queue.dart';
import 'agent_dispatch_progress.dart';
import 'agent_dispatch_service.dart';

/// 按看板项目持有 Agent 调度批次；总览与工具栏从这里读全局运行态。
class AgentDispatchRegistry extends ChangeNotifier {
  AgentDispatchRegistry._() {
    hubAfterQueue.onChanged = notifyListeners;
  }

  static final AgentDispatchRegistry instance = AgentDispatchRegistry._();

  final _services = <String, AgentDispatchService>{};

  /// 总览完成后队列：所有正在跑的批次结束后执行一次。
  final hubAfterQueue = AgentDispatchHubAfterQueueController();

  AgentDispatchService forProject(String projectId) {
    final id = projectId.trim();
    return _services.putIfAbsent(id, () {
      final service = AgentDispatchService.internal(projectId: id);
      service.addRunningListener(() {
        notifyListeners();
        unawaited(hubAfterQueue.tryRun());
      });
      service.addProgressListener(notifyListeners);
      return service;
    });
  }

  bool get anyRunning => _services.values.any((service) => service.isRunning);

  int get runningCount =>
      _services.values.where((service) => service.isRunning).length;

  AgentDispatchProgress progressOf(String projectId) {
    final service = _services[projectId.trim()];
    return service?.progress ?? AgentDispatchProgress.idle;
  }

  /// 已有其它项目用同一仓库在跑时返回冲突服务。
  AgentDispatchService? runningWithRepo(
    String repoPath, {
    String? exceptProjectId,
  }) {
    final normalized = repoPath.trim();
    if (normalized.isEmpty) return null;
    for (final service in _services.values) {
      if (!service.isRunning) continue;
      if (service.projectId == exceptProjectId) continue;
      if (service.activeRepoPath == normalized) return service;
    }
    return null;
  }

  /// 应用退出时停止所有项目的 Worker。
  ///
  /// 逐个 Worker 使用 `taskkill /T`，以确保 SDK/CLI 子进程不会遗留。
  Future<void> stopAll() async {
    await Future.wait(
      _services.values.map((service) => service.requestCancel()),
    );
  }

  void debugReset() {
    hubAfterQueue.reset();
    for (final service in _services.values) {
      service.debugReset();
    }
    _services.clear();
    notifyListeners();
  }
}
