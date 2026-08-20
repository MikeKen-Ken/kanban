import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../controllers/board_controller.dart';
import '../mcp/mcp_block_card.dart';
import '../mcp/mcp_dispatch_card_gate.dart';
import 'agent_dispatch_after_queue.dart';
import 'agent_interaction.dart';
import 'agent_dispatch_config.dart';
import 'agent_dispatch_credentials.dart';
import 'agent_dispatch_log.dart';
import 'agent_dispatch_log_buffer.dart';
import 'agent_dispatch_token.dart';
import 'agent_dispatch_token_store.dart';
import 'agent_dispatch_log_store.dart';
import 'agent_dispatch_progress.dart';
import 'agent_dispatch_prompt.dart';
import 'agent_dispatch_settings.dart';
import 'agent_dispatch_worker.dart';

/// 启动一次 Worker 批次；每轮由 Worker 原子 claim 后创建 scoped Agent 会话。
///
/// 每个看板项目一份实例，由 [AgentDispatchRegistry] 持有。
/// 关闭工作台只隐藏窗口，不会终止批次；日志与运行状态由本服务持有。
class AgentDispatchService {
  AgentDispatchService.internal({
    required this.projectId,
    AgentDispatchCredentials credentials = const AgentDispatchCredentials(),
  }) : _credentials = credentials;

  final String projectId;
  final AgentDispatchCredentials _credentials;

  bool _cancelRequested = false;
  bool _drainAfterCurrentRequested = false;
  bool _isRunning = false;
  AgentWorkerProcess? _activeWorker;
  BoardController? _boardController;
  AgentInteractionEvent? _pendingInteraction;
  String? _activeWorkerToken;
  String? _activeRepoPath;
  List<AgentDispatchAfterStep> _afterQueue = const [];
  bool _runAfterQueueOnFailure = true;
  AgentDispatchAfterQueueHost? _afterQueueHost;
  AgentDispatchProgress _progress = AgentDispatchProgress.idle;
  final _logListeners = <void Function(AgentDispatchLogEntry entry)>{};
  final _runningListeners = <void Function()>{};
  final _progressListeners = <void Function()>{};
  final _interactionListeners = <void Function()>{};
  final AgentDispatchLogBuffer _logBuffer = AgentDispatchLogBuffer();
  bool _logHydrated = false;
  Future<void> _logSaveQueue = Future.value();
  Future<void> _conversationSaveQueue = Future.value();
  Timer? _logPersistTimer;

  bool get isRunning => _isRunning;

  String get logText => _logBuffer.text;

  String? get activeRepoPath => _activeRepoPath;

  /// 在批次运行期间更新结束后要执行的动作。
  ///
  /// 工作台改动会同步到此快照；批次真正结束时仍会再解析一次最新配置，
  /// 避免只沿用启动瞬间的旧列表。
  void updateAfterQueue({
    required List<AgentDispatchAfterStep> steps,
    required bool runOnFailure,
  }) {
    _afterQueue = List<AgentDispatchAfterStep>.unmodifiable(steps);
    _runAfterQueueOnFailure = runOnFailure;
  }

  @visibleForTesting
  List<AgentDispatchAfterStep> get debugAfterQueue => _afterQueue;

  @visibleForTesting
  bool get debugRunAfterQueueOnFailure => _runAfterQueueOnFailure;

  /// 运行中更新默认平台与模型；当前卡片不变，下一张领取时生效。
  void updateLiveRunOptions(AgentDispatchRunOptions options) {
    unawaited(_activeWorker?.writeLiveOverrides({
      'engine': options.engine.name,
      if (options.modelId != null && options.modelId!.trim().isNotEmpty)
        'model': options.modelId!.trim(),
      if (options.modelParams.isNotEmpty)
        'modelParams': [
          for (final item in options.modelParams)
            {'id': item.id, 'value': item.value},
        ],
      if (options.engineDefaults.isNotEmpty)
        'engineDefaults': options.engineDefaultsJobJson(),
      'ignoreCardParams': options.ignoreCardParams,
      'allowDirtyWorkspace': options.allowDirtyWorkspace,
      'enableSandbox': options.enableSandbox,
      'terminateAfterDispatchTerminal': options.terminateAfterDispatchTerminal,
    }));
  }

  AgentDispatchProgress get progress => _progress;

  AgentInteractionEvent? get pendingInteraction => _pendingInteraction;

  void addInteractionListener(void Function() listener) {
    _interactionListeners.add(listener);
  }

  void removeInteractionListener(void Function() listener) {
    _interactionListeners.remove(listener);
  }

  void _notifyInteraction() {
    for (final listener in _interactionListeners.toList()) {
      listener();
    }
  }

  /// 回复当前卡片暂停中的 ask_user 问题。
  Future<bool> submitInteractionReply(String text) async {
    final event = _pendingInteraction;
    final worker = _activeWorker;
    final board = _boardController;
    final requestId = event?.requestId;
    if (event == null ||
        worker == null ||
        board == null ||
        requestId == null ||
        text.trim().isEmpty) {
      return false;
    }
    final sent = await worker.submitInteractionReply(
      requestId: requestId,
      text: text,
    );
    if (!sent) return false;
    _pendingInteraction = null;
    _notifyInteraction();
    await _enqueueConversationUpdate(
      board,
      event.cardId,
      (current) => appendAgentConversationUserReply(current, text),
    );
    return true;
  }

  void addLogListener(void Function(AgentDispatchLogEntry entry) listener) {
    _logListeners.add(listener);
  }

  void removeLogListener(void Function(AgentDispatchLogEntry entry) listener) {
    _logListeners.remove(listener);
  }

  void addRunningListener(void Function() listener) {
    _runningListeners.add(listener);
  }

  void removeRunningListener(void Function() listener) {
    _runningListeners.remove(listener);
  }

  void addProgressListener(void Function() listener) {
    _progressListeners.add(listener);
  }

  void removeProgressListener(void Function() listener) {
    _progressListeners.remove(listener);
  }

  void _setRunning(bool value) {
    if (_isRunning == value) return;
    _isRunning = value;
    for (final listener in _runningListeners.toList()) {
      listener();
    }
  }

  void _setProgress(AgentDispatchProgress value) {
    _progress = value;
    for (final listener in _progressListeners.toList()) {
      listener();
    }
  }

  /// 从本机存储补齐日志；已有内存日志时不覆盖。
  Future<void> hydrateLog() async {
    if (_logHydrated) return;
    _logHydrated = true;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.loadAgentDispatchLog(projectId: projectId);
    if (_logBuffer.isEmpty && stored.isNotEmpty) {
      _logBuffer.replaceWith(stored);
      _notifyLog(const AgentDispatchLogEntry(''));
    }
  }

  Future<void> clearLog() async {
    _logPersistTimer?.cancel();
    _logPersistTimer = null;
    _logBuffer.clear();
    _logHydrated = true;
    _notifyLog(const AgentDispatchLogEntry(''));
    _logSaveQueue = _logSaveQueue.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clearAgentDispatchLog(projectId: projectId);
    });
    await _logSaveQueue;
  }

  void appendLog(
    String message, {
    AgentDispatchLogLevel level = AgentDispatchLogLevel.info,
    AgentDispatchLogSource source = AgentDispatchLogSource.system,
  }) {
    final now = DateTime.now();
    final formatted = message
        .split(RegExp(r'\r?\n'))
        .map(
          (part) => AgentDispatchLogEntry(part, level: level, source: source)
              .format(now),
        )
        .join('\n');
    _logBuffer.addLines(formatted.split('\n'));
    _logHydrated = true;
    _notifyLog(AgentDispatchLogEntry(message, level: level, source: source));
    if (_isRunning) {
      final next = applyWorkerProgressLog(_progress, message, now: now);
      if (next != _progress) _setProgress(next);
    }
    _scheduleLogPersist();
    final usage = AgentDispatchTokenRecord.tryParse(message, at: now);
    if (usage != null && usage.totalTokens > 0) {
      _logSaveQueue = _logSaveQueue.then((_) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.appendAgentDispatchToken(usage, projectId: projectId);
      });
    }
  }

  void _scheduleLogPersist() {
    if (_logPersistTimer != null) return;
    _logPersistTimer = Timer(
      const Duration(milliseconds: 500),
      _enqueueLogPersist,
    );
  }

  void _enqueueLogPersist() {
    _logPersistTimer?.cancel();
    _logPersistTimer = null;
    final snapshot = _logBuffer.text;
    _logSaveQueue = _logSaveQueue.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.saveAgentDispatchLog(snapshot, projectId: projectId);
    });
  }

  Future<void> get pendingLogPersist async {
    if (_logPersistTimer != null) _enqueueLogPersist();
    await _logSaveQueue;
  }

  void _notifyLog(AgentDispatchLogEntry entry) {
    for (final listener in _logListeners.toList()) {
      listener(entry);
    }
  }

  void _emitLog(
    String message, {
    AgentDispatchLogLevel level = AgentDispatchLogLevel.info,
    AgentDispatchLogSource source = AgentDispatchLogSource.system,
  }) {
    appendLog(message, level: level, source: source);
  }

  void _markNoFurtherCards() {
    final current = _progress;
    if (!current.running) return;
    _setProgress(
      current.copyWith(
        drainAfterCurrent: true,
        totalCards: clampedTotalAfterStop(current),
      ),
    );
  }

  /// 立即停止当前 Worker 及其 SDK/CLI 子进程，并阻止后续会话启动。
  Future<void> requestCancel() async {
    _cancelRequested = true;
    _markNoFurtherCards();
    _pendingInteraction = null;
    _notifyInteraction();
    final worker = _activeWorker;
    if (worker != null) await worker.stop();
  }

  /// 在当前 Skill 会话结束后停止批次，不中断进行中的会话。
  Future<void> requestDrainAfterCurrent() async {
    _drainAfterCurrentRequested = true;
    _markNoFurtherCards();
    final worker = _activeWorker;
    if (worker != null) await worker.requestDrainAfterCurrent();
  }

  /// 将当前卡片移入阻塞中，终止当前 Skill 会话，并继续批次下一张。
  Future<void> requestSkipToNext({
    required BoardController boardController,
    String? blockReason,
  }) async {
    final workerToken = _activeWorkerToken;
    if (workerToken != null) {
      final status = McpDispatchCardGate.instance.sessionStatus(workerToken);
      final cardId = status?.cardId?.trim();
      if (cardId != null && cardId.isNotEmpty) {
        final blockResult = await mcpBlockCard(
          boardController,
          cardId: cardId,
          projectId: status?.projectId ?? projectId,
          reason: blockReason ?? '用户点击「下一个」跳过',
        );
        if (blockResult.isError == true) {
          _emitLog(
            '移入阻塞中失败，仍将终止当前会话',
            level: AgentDispatchLogLevel.warning,
          );
        } else {
          _emitLog('已将卡片 $cardId 移入阻塞中');
        }
      }
    }
    final worker = _activeWorker;
    if (worker != null) await worker.requestSkipToNext();
  }

  Future<AgentWorkerResult> runOnce({
    required AgentDispatchRunOptions options,
    required BoardController boardController,
    required String skillPath,
    required String mcpEndpoint,
    required Future<void> Function(String workerToken) closeScopedEndpoint,
    String? workerScriptPath,
    int queueSize = 0,
    List<AgentDispatchAfterStep> afterQueue = const [],
    bool runAfterQueueOnFailure = true,
    AgentDispatchAfterQueueHost? afterQueueHost,
    Future<AgentDispatchAfterQueueSnapshot?> Function()? resolveAfterQueue,
    void Function(AgentDispatchLogEntry entry)? onLog,
  }) async {
    if (_isRunning) {
      return const AgentWorkerResult(ok: false, error: '已有批次在运行');
    }
    _cancelRequested = false;
    _drainAfterCurrentRequested = false;
    _activeRepoPath = options.repoPath.trim();
    _boardController = boardController;
    _afterQueue = List<AgentDispatchAfterStep>.unmodifiable(afterQueue);
    _runAfterQueueOnFailure = runAfterQueueOnFailure;
    _afterQueueHost = afterQueueHost;
    final cardLimitMax = options.cardLimit is AgentDispatchCardLimitMax;
    final cardLimitCount = switch (options.cardLimit) {
      AgentDispatchCardLimitMax() => 0,
      AgentDispatchCardLimitCount(:final count) => count,
    };
    _setProgress(
      AgentDispatchProgress(
        running: true,
        cardLimitMax: cardLimitMax,
        cardLimitCount: cardLimitCount,
        totalCards: plannedDispatchTotal(
          cardLimitMax: cardLimitMax,
          cardLimitCount: cardLimitCount,
          queueSize: queueSize,
        ),
        engine: options.engine.name,
        model: options.modelId?.trim() ?? '',
        modelParams: agentDispatchModelParamMap(options.modelParams),
        batchStartedAt: DateTime.now(),
      ),
    );
    _setRunning(true);
    var workerInvoked = false;
    try {
      final result = await _runOnceImpl(
        options: options,
        boardController: boardController,
        skillPath: skillPath,
        mcpEndpoint: mcpEndpoint,
        closeScopedEndpoint: closeScopedEndpoint,
        workerScriptPath: workerScriptPath,
        onLog: onLog,
        onWorkerInvoked: () => workerInvoked = true,
      );
      AgentDispatchAfterQueueSnapshot? resolved;
      if (resolveAfterQueue != null) {
        try {
          resolved = await resolveAfterQueue();
        } catch (error) {
          _emitLog(
            '完成后队列：读取最新配置失败，回退运行中快照：$error',
            level: AgentDispatchLogLevel.warning,
          );
        }
      }
      final latest = resolveAfterQueueForBatchEnd(
        liveSteps: _afterQueue,
        liveRunOnFailure: _runAfterQueueOnFailure,
        resolved: resolved,
      );
      _afterQueue = latest.steps;
      _runAfterQueueOnFailure = latest.runOnFailure;
      final shouldRunAfterQueue = shouldRunAgentDispatchAfterQueue(
        batchOk: result.ok,
        cancelRequested: _cancelRequested,
        drainRequested: _drainAfterCurrentRequested,
        runOnFailure: _runAfterQueueOnFailure,
        workerInvoked: workerInvoked,
        queueNonEmpty: _afterQueue.isNotEmpty && _afterQueueHost != null,
      );
      if (shouldRunAfterQueue && _afterQueueHost != null) {
        if (!result.ok) {
          _emitLog(
            '完成后队列：批次未成功，仍按「失败后仍执行」继续',
            level: AgentDispatchLogLevel.warning,
          );
        }
        try {
          await runAgentDispatchAfterQueue(
            steps: _afterQueue,
            host: _afterQueueHost!,
            onLog: _emitLog,
          );
        } catch (error) {
          _emitLog(
            '完成后队列中断：$error',
            level: AgentDispatchLogLevel.error,
          );
        }
      }
      return result;
    } finally {
      if (_cancelRequested) {
        unawaited(_conversationSaveQueue.catchError((_) {}));
      } else {
        await _conversationSaveQueue;
      }
      _activeRepoPath = null;
      _boardController = null;
      _pendingInteraction = null;
      _notifyInteraction();
      _afterQueue = const [];
      _afterQueueHost = null;
      _setProgress(_progress.copyWith(running: false));
      _setRunning(false);
    }
  }

  Future<AgentWorkerResult> _runOnceImpl({
    required AgentDispatchRunOptions options,
    required BoardController boardController,
    required String skillPath,
    required String mcpEndpoint,
    required Future<void> Function(String workerToken) closeScopedEndpoint,
    String? workerScriptPath,
    void Function(AgentDispatchLogEntry entry)? onLog,
    void Function()? onWorkerInvoked,
  }) async {
    final repo = options.repoPath.trim();
    if (repo.isNotEmpty && !await Directory(repo).exists()) {
      return AgentWorkerResult(ok: false, error: '仓库路径不存在：$repo');
    }
    final boundProjectId = options.projectId?.trim();
    if (boundProjectId == null || boundProjectId.isEmpty) {
      return const AgentWorkerResult(ok: false, error: '缺少看板项目');
    }
    if (boundProjectId != projectId) {
      return const AgentWorkerResult(ok: false, error: '批次项目与工作台不一致');
    }

    final skillFile = File(skillPath);
    if (!await skillFile.exists()) {
      return AgentWorkerResult(
        ok: false,
        error: '未找到 Skill：$skillPath',
      );
    }
    final skillMarkdown = await skillFile.readAsString();
    void log(
      String message, {
      AgentDispatchLogLevel level = AgentDispatchLogLevel.info,
      AgentDispatchLogSource source = AgentDispatchLogSource.system,
    }) {
      final entry =
          AgentDispatchLogEntry(message, level: level, source: source);
      _emitLog(message, level: level, source: source);
      onLog?.call(entry);
    }

    log('项目：${options.projectTitle ?? boundProjectId}');
    if (repo.isEmpty) {
      log('未指定代码仓库，Worker 使用系统临时目录作为工作目录');
    } else {
      log('仓库：$repo');
    }
    log('策略：Worker 原子领卡，每张卡片创建一次独立 Agent 调用；上限 ${options.cardLimit.label}');

    String? cursorApiKey;
    try {
      cursorApiKey = await _credentials.resolveCursorApiKey();
    } catch (error) {
      if (options.engine == AgentDispatchEngine.cursor) {
        return AgentWorkerResult(
          ok: false,
          error: '读取 Cursor API Key 的系统安全存储失败：$error',
        );
      }
      log(
        '读取 Cursor API Key 失败：$error；本批次默认不是 Cursor，仅当卡片指定 Cursor 时才会失败',
        level: AgentDispatchLogLevel.warning,
      );
    }
    if (options.engine == AgentDispatchEngine.cursor && cursorApiKey == null) {
      return const AgentWorkerResult(
        ok: false,
        error: '尚未配置 Cursor API Key，请先在 Agent 调度面板中安全保存',
      );
    }

    final runId = const Uuid().v4();
    final workerToken = const Uuid().v4();
    _activeWorkerToken = workerToken;
    final cardLimit = switch (options.cardLimit) {
      AgentDispatchCardLimitMax() => 999,
      AgentDispatchCardLimitCount(:final count) => count,
    };
    final prompt = buildSkillDispatchPrompt(
      skillMarkdown: skillMarkdown,
      projectId: boundProjectId,
    );
    log('批次 id：$runId');
    log('Worker 每轮先原子领取卡片，再启动绑定卡片的 scoped Agent 会话');
    final stopwatch = Stopwatch()..start();
    late AgentWorkerResult result;
    McpDispatchCardGate.instance.beginBatch(
      workerToken,
      projectId: boundProjectId,
      repoPath: repo.isEmpty ? null : repo,
    );
    try {
      result = await runAgentWorkerJob(
        engine: options.engine,
        cwd: repo.isEmpty ? Directory.systemTemp.path : repo,
        prompt: prompt,
        mcpEndpoint: mcpEndpoint,
        projectId: boundProjectId,
        cardLimit: cardLimit,
        workerToken: workerToken,
        model: options.modelId,
        modelParams: options.modelParams,
        engineDefaults: options.engineDefaultsJobJson(),
        ignoreCardParams: options.ignoreCardParams,
        allowDirtyWorkspace: options.allowDirtyWorkspace,
        enableSandbox: options.enableSandbox,
        terminateAfterDispatchTerminal: options.terminateAfterDispatchTerminal,
        cursorApiKey: cursorApiKey,
        workerScriptPath: workerScriptPath,
        onProcessStarted: (worker) {
          onWorkerInvoked?.call();
          _activeWorker = worker;
          if (_cancelRequested) unawaited(worker.stop());
        },
        onInteraction: (event) {
          if (_cancelRequested) return;
          _handleInteraction(boardController, event);
        },
        onLog: (line) {
          if (_cancelRequested) return;
          final parsed = AgentDispatchLogEntry.parseWorkerLine(line);
          log(
            parsed.message,
            level: parsed.level,
            source: parsed.source,
          );
        },
      );
    } catch (error) {
      result = AgentWorkerResult(ok: false, error: 'Worker 启动或通信失败：$error');
    } finally {
      try {
        await closeScopedEndpoint(workerToken);
      } catch (error) {
        log(
          '回收 scoped MCP 端点失败：$error',
          level: AgentDispatchLogLevel.warning,
        );
      } finally {
        McpDispatchCardGate.instance.endBatch(workerToken);
      }
      _activeWorker = null;
      _activeWorkerToken = null;
      stopwatch.stop();
    }
    if (result.processedCards != null) {
      _setProgress(
        applyWorkerProgressLog(
          _progress,
          '已处理 ${result.processedCards} 张',
        ),
      );
    }
    if (_cancelRequested) {
      log('Worker 批次已由用户终止', level: AgentDispatchLogLevel.warning);
      return const AgentWorkerResult(ok: false, error: '已取消');
    }
    log(
      'Worker 退出：exitCode=${result.exitCode ?? '未知'}，'
      '已处理 ${result.processedCards ?? 0} 张，耗时 ${stopwatch.elapsed.inSeconds} 秒',
      level: result.ok
          ? AgentDispatchLogLevel.success
          : AgentDispatchLogLevel.error,
    );
    if (!result.ok) {
      log(result.error ?? 'Worker 批次失败', level: AgentDispatchLogLevel.error);
    }
    return result;
  }

  @visibleForTesting
  void debugSetPendingInteraction(AgentInteractionEvent? event) {
    _pendingInteraction = event;
    _notifyInteraction();
  }

  void debugReset() {
    _cancelRequested = false;
    _drainAfterCurrentRequested = false;
    _isRunning = false;
    _activeWorker = null;
    _boardController = null;
    _pendingInteraction = null;
    _activeWorkerToken = null;
    _activeRepoPath = null;
    _progress = AgentDispatchProgress.idle;
    _logPersistTimer?.cancel();
    _logPersistTimer = null;
    _logBuffer.clear();
    _logHydrated = false;
    _logSaveQueue = Future.value();
    _conversationSaveQueue = Future.value();
    _logListeners.clear();
    _runningListeners.clear();
    _progressListeners.clear();
    _interactionListeners.clear();
  }

  void _handleInteraction(
    BoardController boardController,
    AgentInteractionEvent event,
  ) {
    if (_cancelRequested) return;
    if (event.awaitsReply) {
      _pendingInteraction = event;
      _notifyInteraction();
    }
    unawaited(
      _enqueueConversationUpdate(
        boardController,
        event.cardId,
        (current) => appendAgentConversationEvent(current, event),
      ),
    );
  }

  Future<void> _enqueueConversationUpdate(
    BoardController boardController,
    String cardId,
    String Function(String? current) update,
  ) {
    _conversationSaveQueue =
        _conversationSaveQueue.catchError((_) {}).then((_) async {
      try {
        await boardController.runOnProject(projectId, () async {
          final current =
              boardController.findCardById(cardId)?.agentConversationMarkdown;
          final error = await boardController.setCardAgentConversation(
            cardId,
            update(current),
          );
          if (error != null) {
            _emitLog(
              '保存卡片对话失败：$error',
              level: AgentDispatchLogLevel.warning,
            );
          }
        });
      } catch (error) {
        _emitLog(
          '保存卡片对话异常：$error',
          level: AgentDispatchLogLevel.warning,
        );
      }
    });
    return _conversationSaveQueue;
  }

  @visibleForTesting
  void debugSetProgress(AgentDispatchProgress value) {
    _setProgress(value);
    _setRunning(value.running);
  }
}

/// 解析默认 skill 路径是否可读（供面板展示）。
Future<String?> peekSkillPreview(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsString();
}

String resolveDispatchSkillPath(AgentDispatchSettings settings) =>
    settings.resolveSkillPath();
