import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../../features/import_export/backup_file_picker.dart';
import '../../models/kanban_models.dart';
import '../kanban/next_work_card.dart';
import '../kanban/verify_column.dart';
import 'agent_dispatch_after_queue.dart';
import 'agent_dispatch_after_queue_field.dart';
import 'agent_dispatch_config.dart';
import 'agent_dispatch_card_limit_field.dart';
import 'agent_dispatch_credentials.dart';
import 'agent_dispatch_directory_opener.dart';
import 'agent_dispatch_git_author_fields.dart';
import 'agent_dispatch_log_exporter.dart';
import 'agent_dispatch_log.dart';
import 'agent_dispatch_log_refresh_scheduler.dart';
import 'agent_dispatch_model_catalog_store.dart';
import 'agent_dispatch_model_parameters.dart';
import 'agent_dispatch_progress.dart';
import 'agent_dispatch_repository_field.dart';
import 'agent_dispatch_registry.dart';
import 'agent_dispatch_run_toggles.dart';
import 'agent_dispatch_section_header.dart';
import 'agent_dispatch_service.dart';
import 'agent_dispatch_settings.dart';
import 'agent_dispatch_token_stats_dialog.dart';
import 'agent_dispatch_usage.dart';
import 'agent_dispatch_usage_pane.dart';
import 'agent_dispatch_usage_store.dart';
import 'agent_dispatch_window.dart';
import 'agent_dispatch_worker.dart';
import 'agent_dispatch_workspace.dart';
import 'cursor_api_key_section.dart';

class AgentDispatchPanel extends StatefulWidget {
  const AgentDispatchPanel({required this.projectId, super.key});

  final String projectId;

  @override
  State<AgentDispatchPanel> createState() => _AgentDispatchPanelState();
}

class _AgentDispatchPanelState extends State<AgentDispatchPanel> {
  static const _credentials = AgentDispatchCredentials();
  AgentDispatchSettings _settings = const AgentDispatchSettings();
  final _repoController = TextEditingController();
  final _gitAuthorNameController = TextEditingController();
  final _gitAuthorEmailController = TextEditingController();
  final _countController = TextEditingController(text: '1');
  final _logController = TextEditingController();
  late final AgentDispatchService _service;

  List<AgentDispatchModelInfo> _models = const [];
  String? _skillPreview;
  String? _workerStatus;
  String? _repoErrorText;
  String? _projectErrorText;
  String? _countErrorText;
  String? _modelCatalogMessage;
  AgentDispatchUsageSnapshot? _usage;
  bool _running = false;
  bool _stopping = false;
  bool _drainPending = false;
  bool _skipping = false;
  bool _busy = false;
  bool _usageBusy = false;
  DateTime _lastLogAt = DateTime.now();
  Timer? _heartbeat;
  final _logRefreshScheduler = AgentDispatchLogRefreshScheduler();

  @override
  void initState() {
    super.initState();
    _service = AgentDispatchRegistry.instance.forProject(widget.projectId);
    _running = _service.isRunning;
    _syncLogFromService();
    _service.addLogListener(_onServiceLog);
    _service.addRunningListener(_onServiceRunningChanged);
    _service.addProgressListener(_onServiceProgressChanged);
    _service.addInteractionListener(_onServiceInteractionChanged);
    if (_running) _startHeartbeat();
    _bootstrap();
  }

  void _syncLogFromService() {
    final text = _service.logText;
    _logController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onServiceLog(AgentDispatchLogEntry entry) {
    if (!mounted) return;
    _logRefreshScheduler.schedule(() {
      if (mounted) setState(_syncLogFromService);
    });
  }

  void _onServiceProgressChanged() {
    if (mounted) setState(() {});
  }

  void _onServiceInteractionChanged() {
    if (mounted) setState(() {});
  }

  AgentDispatchProgress _liveProgress(KanbanBoard? currentBoard) {
    final progress = _service.progress;
    if (currentBoard == null || currentBoard.id != widget.projectId) {
      return progress;
    }
    final hasActiveCard = hasIncompleteDoingCard(currentBoard);
    return applyLiveBoardQueue(
      progress,
      remainingQueue: countRemainingDispatchQueue(
        currentBoard,
        hasActiveCard: hasActiveCard,
      ),
      hasActiveCard: hasActiveCard,
    );
  }

  void _syncRunningFromService() {
    final running = _service.isRunning;
    setState(() {
      _running = running;
      if (!running) {
        _stopping = false;
        _drainPending = false;
        _skipping = false;
        _syncLogFromService();
      }
    });
    if (running) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }
  }

  void _onServiceRunningChanged() {
    if (!mounted) return;
    _syncRunningFromService();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = prefs.loadAgentDispatchSettings();
    final forProject = loaded.viewForProject(widget.projectId);
    final cachedModels = prefs.loadAgentDispatchModelCatalog(
      engine: forProject.engine,
    );
    final cachedModelId = cachedModels.isEmpty
        ? forProject.modelId
        : resolveAgentDispatchModelId(cachedModels, forProject.modelId);
    final modelChanged = cachedModelId != forProject.modelId;
    AgentDispatchModelInfo? selected;
    for (final model in cachedModels) {
      if (model.id == cachedModelId) {
        selected = model;
        break;
      }
    }
    final normalized = modelChanged
        ? forProject.copyWith(
            modelId: cachedModelId,
            modelParamValues: preferredAgentDispatchModelParamValues(
              selected?.parameters ?? const [],
            ),
          )
        : forProject.copyWith(
            modelParamValues: filterAgentDispatchModelParamValues(
              forProject.modelParamValues,
              selected?.parameters ?? const [],
            ),
          );
    if (!mounted) return;
    setState(() {
      _settings = normalized;
      _models = cachedModels;
      _repoController.text = normalized.repoPathFor(widget.projectId) ?? '';
      _gitAuthorNameController.text = normalized.gitAuthorName ?? '';
      _gitAuthorEmailController.text = normalized.gitAuthorEmail ?? '';
      _countController.text = '${normalized.cardLimitCount}';
    });
    // 模型归一化，或首次打开时把该项目种子写入按项目槽位。
    if (modelChanged ||
        !loaded.engineConfigByProject.containsKey(widget.projectId) ||
        normalized.modelParamValues != forProject.modelParamValues) {
      await _persist(normalized);
    }
    await _service.hydrateLog();
    if (!mounted) return;
    setState(_syncLogFromService);
    await _refreshSkillPreview();
    await _refreshWorkerStatus();
    if (!mounted) return;
    if (_service.isRunning) {
      setState(() => _running = true);
      _startHeartbeat();
    }
    if (!mounted) return;
    if (_settings.engine == AgentDispatchEngine.cursor) {
      unawaited(_loadAccountInfo());
    }
  }

  Future<void> _persist(AgentDispatchSettings next) async {
    final synced = next.rememberActiveEngineProfile();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final disk = prefs.loadAgentDispatchSettings();
    final projectId = widget.projectId;
    final afterMap = Map<String, List<AgentDispatchAfterStep>>.from(
      disk.afterQueueByProject,
    );
    final runMap = Map<String, bool>.from(
      disk.runAfterQueueOnFailureByProject,
    );
    // await 之后以当前界面内存为准，避免并发 persist 冲掉运行中改过的完成后队列。
    final latest = _settings;
    if (latest.afterQueueByProject.containsKey(projectId)) {
      afterMap[projectId] = latest.afterQueueByProject[projectId]!;
    } else if (synced.afterQueueByProject.containsKey(projectId)) {
      afterMap[projectId] = synced.afterQueueByProject[projectId]!;
    }
    if (latest.runAfterQueueOnFailureByProject.containsKey(projectId)) {
      runMap[projectId] = latest.runAfterQueueOnFailureByProject[projectId]!;
    } else if (synced.runAfterQueueOnFailureByProject.containsKey(projectId)) {
      runMap[projectId] = synced.runAfterQueueOnFailureByProject[projectId]!;
    }
    // 顶层引擎/模型仅作未配置项目的回退种子：落盘以磁盘原值为基，再绑本项目槽位。
    final forDisk = disk
        .copyWith(
          useProject: synced.useProject,
          projectId: synced.projectId,
          repoPath: synced.repoPath,
          ignoreCardParams: synced.ignoreCardParams,
          allowDirtyWorkspace: synced.allowDirtyWorkspace,
          enableSandbox: synced.enableSandbox,
          requireTests: synced.requireTests,
          terminateAfterDispatchTerminal: synced.terminateAfterDispatchTerminal,
          cardLimitMax: synced.cardLimitMax,
          cardLimitCount: synced.cardLimitCount,
          afterQueue: synced.afterQueue,
          runAfterQueueOnFailure: synced.runAfterQueueOnFailure,
          afterQueueByProject: afterMap,
          runAfterQueueOnFailureByProject: runMap,
          workerScriptPath: synced.workerScriptPath,
          skillPath: synced.skillPath,
          repoPathByProject: synced.repoPathByProject,
          repoPaths: synced.repoPaths,
          gitAuthorName: synced.gitAuthorName,
          gitAuthorEmail: synced.gitAuthorEmail,
        )
        .bindEngineConfigToProject(
          projectId,
          engine: synced.engine,
          modelId: synced.modelId,
          modelParamValues: synced.modelParamValues,
          engineProfiles: synced.engineProfiles,
        );
    final forUi = forDisk.viewForProject(projectId).copyWith(
          afterQueueByProject: afterMap,
          runAfterQueueOnFailureByProject: runMap,
        );
    setState(() => _settings = forUi);
    await prefs.saveAgentDispatchSettings(forDisk);
    if (_service.isRunning && mounted) {
      await _pushLiveRunOptions(forUi);
    }
  }

  Future<void> _pushLiveRunOptions(AgentDispatchSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final catalogs = {
      for (final engine in AgentDispatchEngine.values)
        engine: prefs.loadAgentDispatchModelCatalog(engine: engine),
    };
    if (!mounted) return;
    final board = context.read<BoardController>();
    _service.updateLiveRunOptions(
      settings.toRunOptions(
        projectTitleOf: (id) => board.manifest?.findById(id)?.title,
        catalogs: catalogs,
      ),
    );
  }

  Future<void> _persistAfterQueue(AgentDispatchSettings next) async {
    // 先写入界面内存，再同步到运行中服务，最后落盘；批次结束会再取一次最新状态。
    setState(() => _settings = next);
    if (_running || _service.isRunning) {
      _service.updateAfterQueue(
        steps: next.afterQueueFor(widget.projectId),
        runOnFailure: next.runAfterQueueOnFailureFor(widget.projectId),
      );
    }
    await _persist(next);
  }

  Future<AgentDispatchAfterQueueSnapshot?> _resolveLatestAfterQueue() async {
    final projectId = widget.projectId;
    if (mounted) {
      return (
        steps: _settings.afterQueueFor(projectId),
        runOnFailure: _settings.runAfterQueueOnFailureFor(projectId),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final disk = prefs.loadAgentDispatchSettings();
    return (
      steps: disk.afterQueueFor(projectId),
      runOnFailure: disk.runAfterQueueOnFailureFor(projectId),
    );
  }

  void _appendLog(
    String line, {
    AgentDispatchLogLevel level = AgentDispatchLogLevel.info,
  }) {
    _lastLogAt = DateTime.now();
    _service.appendLog(line, level: level);
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    final started = DateTime.now();
    _lastLogAt = DateTime.now();
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_running || !mounted) return;
      if (DateTime.now().difference(_lastLogAt) < const Duration(seconds: 15)) {
        return;
      }
      final elapsed = DateTime.now().difference(started).inSeconds;
      _appendLog(
          'Still running ($elapsed seconds elapsed); waiting for the current call…');
      setState(() {});
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<bool> _replyInteraction(String text) {
    return _service.submitInteractionReply(text);
  }

  Future<void> _clearLog() async {
    await _service.clearLog();
    if (mounted) setState(_syncLogFromService);
  }

  Future<void> _exportLog(String log) async {
    final exported = await exportAgentDispatchLog(log);
    if (!mounted) return;
    showAppSnackBar(context,
        message: exported ? 'Dispatch log exported' : 'Export cancelled');
  }

  Future<void> _copyLog(String log) async {
    await Clipboard.setData(ClipboardData(text: log));
    if (!mounted) return;
    showAppSnackBar(context, message: 'Dispatch log copied');
  }

  Future<void> _refreshSkillPreview() async {
    final path = _settings.resolveSkillPath();
    final preview = await peekSkillPreview(path);
    if (!mounted) return;
    setState(() => _skillPreview = preview);
  }

  Future<void> _refreshWorkerStatus() async {
    final health = await inspectAgentDispatchWorker(_settings.workerScriptPath);
    if (!mounted) return;
    setState(() {
      _workerStatus = health.ok
          ? 'Healthy: ${health.summary}\n${health.workerRoot}'
          : '${health.error ?? 'Worker health check failed'}\n${health.summary}';
    });
  }

  Future<void> _pickRepo() async {
    final path = await pickBackupDirectory();
    if (path == null || !mounted) return;
    _repoController.text = path;
    await _persist(_settings.bindRepoToProject(widget.projectId, path));
    if (!mounted) return;
    setState(() => _repoErrorText = null);
  }

  Future<void> _deleteRepoPath(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty || !_settings.repoPaths.contains(normalized)) return;
    final wasCurrent = _repoController.text.trim() == normalized;
    if (wasCurrent) _repoController.clear();
    await _persist(_settings.forgetRepoPath(normalized));
  }

  Future<void> _openSkillDirectory() async {
    final opened = await openAgentDispatchSkillDirectory(
      _settings.resolveSkillPath(),
    );
    if (!opened) {
      _appendLog('Unable to open Skill directory',
          level: AgentDispatchLogLevel.warning);
    }
  }

  Future<void> _fixWorker() async {
    if (_busy) return;
    setState(() => _busy = true);
    _appendLog('Starting Worker repair…');
    final result = await ensureAgentDispatchWorker(
      workerScriptPath: _settings.workerScriptPath,
      onLog: (l) {
        if (mounted) _appendLog(l);
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _appendLog(
      result.message,
      level: result.ok
          ? AgentDispatchLogLevel.success
          : AgentDispatchLogLevel.error,
    );
    await _refreshWorkerStatus();
  }

  Future<void> _loadModels() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final models = await listAgentDispatchModels(
        engine: _settings.engine,
        cursorApiKey: await _credentials.resolveCursorApiKey(),
        workerScriptPath: _settings.workerScriptPath,
        onLog: (l) {
          if (mounted) _appendLog(l);
        },
      );
      if (!mounted) return;
      final uniqueModels = <String, AgentDispatchModelInfo>{
        for (final model in models) model.id: model,
      }.values.toList();
      final selectedId = resolveAgentDispatchModelId(
        uniqueModels,
        _settings.modelId,
      );
      final selectionChanged = selectedId != _settings.modelId;
      AgentDispatchModelInfo? selected;
      for (final model in uniqueModels) {
        if (model.id == selectedId) {
          selected = model;
          break;
        }
      }
      final nextParams =
          selectionChanged || _isStockModelParams(_settings.modelParamValues)
              ? preferredAgentDispatchModelParamValues(
                  selected?.parameters ?? const [],
                )
              : filterAgentDispatchModelParamValues(
                  _settings.modelParamValues,
                  selected?.parameters ?? const [],
                );
      setState(() {
        _models = uniqueModels;
        _busy = false;
        _modelCatalogMessage = null;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.saveAgentDispatchModelCatalog(
        uniqueModels,
        engine: _settings.engine,
      );
      _appendLog('Loaded ${uniqueModels.length} model(s)');
      await _persist(_settings.copyWith(
        modelId: selectedId,
        modelParamValues: nextParams,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _modelCatalogMessage = _modelRefreshFailureMessage(
          error: e,
          hasCache: _models.isNotEmpty,
        );
      });
      _appendLog('Failed to load models: $e',
          level: AgentDispatchLogLevel.error);
    }
  }

  Future<void> _onCursorKeyChanged() async {
    await _loadAccountInfo(force: true);
  }

  Future<void> _loadAccountInfo({bool force = false}) async {
    if (_usageBusy || _settings.engine != AgentDispatchEngine.cursor) return;
    final apiKey = await _credentials.resolveCursorApiKey();
    final fingerprint = agentDispatchUsageKeyFingerprint(apiKey);
    if (!force) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.loadAgentDispatchUsage(keyFingerprint: fingerprint);
      if (cached != null) {
        final label = cached.displayLabel;
        if (label != null) {
          await _credentials.updateActiveCursorApiKeyLabel(label);
        }
        if (!mounted) return;
        setState(() => _usage = cached);
        return;
      }
    }
    setState(() => _usageBusy = true);
    try {
      final snapshot = await fetchAgentDispatchUsage(
        cursorApiKey: apiKey,
        workerScriptPath: _settings.workerScriptPath,
      );
      final label = snapshot.displayLabel;
      if (label != null) {
        await _credentials.updateActiveCursorApiKeyLabel(label);
      }
      if (fingerprint.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.saveAgentDispatchUsage(
          snapshot,
          keyFingerprint: fingerprint,
        );
      }
      if (!mounted) return;
      setState(() {
        _usage = snapshot;
        _usageBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _usageBusy = false;
        _usage = AgentDispatchUsageSnapshot(
          message: 'Failed to refresh account information: $e',
        );
      });
    }
  }

  bool _isStockModelParams(Map<String, String> values) {
    if (values.isEmpty) return true;
    if (values.length == 1 && values['fast'] == 'false') {
      return true;
    }
    const stock = AgentDispatchSettings.defaultModelParamValues;
    return values.length == stock.length &&
        stock.entries.every((entry) => values[entry.key] == entry.value);
  }

  AgentDispatchModelInfo? get _selectedModel {
    final id = _settings.modelId;
    if (id == null) return null;
    for (final m in _models) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _onEngineChanged(AgentDispatchEngine? nextEngine) async {
    if (nextEngine == null || _busy) return;
    final switched = _settings.switchEngine(nextEngine);
    final prefs = await SharedPreferences.getInstance();
    final cachedModels = prefs.loadAgentDispatchModelCatalog(
      engine: nextEngine,
    );
    final selectedId = resolveAgentDispatchModelId(
      cachedModels,
      switched.modelId,
      preferredId: nextEngine == AgentDispatchEngine.cursor
          ? AgentDispatchSettings.defaultModelId
          : '',
    );
    AgentDispatchModelInfo? selected;
    for (final model in cachedModels) {
      if (model.id == selectedId) selected = model;
    }
    final modelChanged = selectedId != switched.modelId;
    final nextSettings = switched.copyWith(
      engine: nextEngine,
      modelId: selectedId,
      modelParamValues: modelChanged || switched.modelParamValues.isEmpty
          ? preferredAgentDispatchModelParamValues(
              selected?.parameters ?? const [],
            )
          : filterAgentDispatchModelParamValues(
              switched.modelParamValues,
              selected?.parameters ?? const [],
            ),
    );
    if (!mounted) return;
    setState(() {
      _models = cachedModels;
      _usage = null;
      _modelCatalogMessage = null;
    });
    await _persist(nextSettings);
    if (!mounted) return;
    if (nextEngine == AgentDispatchEngine.cursor) {
      unawaited(_loadAccountInfo());
    }
  }

  Future<void> _run() async {
    if (_running || _service.isRunning) return;
    final board = context.read<BoardController>();
    final count = int.tryParse(_countController.text.trim());
    final repo = _repoController.text.trim();
    final projectId = widget.projectId;
    final projectMissing = board.manifest?.findById(projectId) == null;
    final countInvalid =
        !_settings.cardLimitMax && (count == null || count < 1 || count > 999);
    setState(() {
      _repoErrorText = null;
      _projectErrorText = projectMissing ? 'Project not found' : null;
      _countErrorText = countInvalid ? 'Enter a value from 1 to 999' : null;
    });
    if (projectMissing || countInvalid) {
      return;
    }
    final next = _settings
        .copyWith(
          useProject: true,
          projectId: projectId,
          cardLimitCount: count!,
        )
        .bindRepoToProject(projectId, repo);
    await _persist(next);

    final conflict = AgentDispatchRegistry.instance.runningWithRepo(
      repo,
      exceptProjectId: projectId,
    );
    if (conflict != null) {
      final confirmed = await _confirmSameRepo(board, conflict.projectId, repo);
      if (!confirmed || !mounted) return;
    }

    final prefs = await SharedPreferences.getInstance();
    final catalogs = {
      for (final engine in AgentDispatchEngine.values)
        engine: prefs.loadAgentDispatchModelCatalog(engine: engine),
    };
    final options = next.toRunOptions(
      projectTitleOf: (id) => board.manifest?.findById(id)?.title,
      catalogs: catalogs,
    );
    if (!board.mcpHost.isRunning) {
      _appendLog(
        'Kanban MCP is not running, so Worker cannot inspect the queue; enable MCP in Settings first',
        level: AgentDispatchLogLevel.warning,
      );
      return;
    }
    var queueSize = 0;
    await board.runOnProject(projectId, () async {
      final current = board.board;
      if (current != null) queueSize = countWorkQueueCards(current);
    });

    setState(() {
      _running = true;
    });
    _startHeartbeat();
    _appendLog(
      '\n—— ${DateTime.now().toLocal().toString().substring(0, 19)} new run ——',
    );
    _appendLog('Engine: ${options.engine.label}');
    final result = await _service.runOnce(
      options: options,
      boardController: board,
      skillPath: next.resolveSkillPath(),
      mcpEndpoint: board.mcpHost.endpointUrl,
      closeScopedEndpoint: board.mcpHost.closeScopedEndpoint,
      workerScriptPath: next.workerScriptPath,
      queueSize: queueSize,
      afterQueue: _settings.afterQueueFor(projectId),
      runAfterQueueOnFailure: _settings.runAfterQueueOnFailureFor(projectId),
      resolveAfterQueue: _resolveLatestAfterQueue,
      afterQueueHost: AgentDispatchAfterQueueHost(
        uploadAll: board.uploadNow,
        gitPush: () => gitPushWithRebase(repoPath: options.repoPath),
        sleep: windowsSleepNow,
        shutdown: windowsShutdownNow,
      ),
    );
    if (!mounted) return;
    _syncRunningFromService();
    if (result.ok) {
      _appendLog(result.summary ?? 'Complete',
          level: AgentDispatchLogLevel.success);
    } else if (result.error == '已取消') {
      _appendLog('Run stopped', level: AgentDispatchLogLevel.warning);
    }
  }

  Future<bool> _confirmSameRepo(
    BoardController board,
    String otherProjectId,
    String repo,
  ) async {
    final otherTitle =
        board.manifest?.findById(otherProjectId)?.title ?? otherProjectId;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Repository is used by another project'),
        content: Text(
          'Project "$otherTitle" is already running in this repository:\n$repo\n\n'
          'Running in parallel may modify the same files. Continue anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Run anyway'),
          ),
        ],
      ),
    );
    return go == true;
  }

  @override
  void dispose() {
    _logRefreshScheduler.cancel();
    _service.removeLogListener(_onServiceLog);
    _service.removeRunningListener(_onServiceRunningChanged);
    _service.removeProgressListener(_onServiceProgressChanged);
    _service.removeInteractionListener(_onServiceInteractionChanged);
    _stopHeartbeat();
    _repoController.dispose();
    _gitAuthorNameController.dispose();
    _gitAuthorEmailController.dispose();
    _countController.dispose();
    _logController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = context.watch<BoardController>();
    final projectTitle =
        board.manifest?.findById(widget.projectId)?.title ?? widget.projectId;
    final modelParameters = _selectedModel?.parameters ?? const [];
    final skillPath = _settings.resolveSkillPath();
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = (viewport.width - 48).clamp(560.0, 1600.0).toDouble();
    final dialogHeight = (viewport.height - 180).clamp(420.0, 820.0).toDouble();

    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      title: Text('Agent Dispatch workspace · $projectTitle'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: AgentDispatchWorkspace(
          settings: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AgentDispatchSectionHeader(
                title: 'Engine',
                tone: AgentDispatchSectionTone.configuration,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AgentDispatchEngine>(
                key: ValueKey('engine-${_settings.engine}'),
                initialValue: _settings.engine,
                decoration: const InputDecoration(
                  labelText: 'AI platform',
                  helperText: 'Cards without a specified platform use this',
                ),
                items: [
                  for (final e in AgentDispatchEngine.values)
                    DropdownMenuItem(value: e, child: Text(e.label)),
                ],
                onChanged: _busy ? null : _onEngineChanged,
              ),
              const SizedBox(height: 12),
              if (_projectErrorText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _projectErrorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              const AgentDispatchSectionHeader(
                title: 'Repository (optional)',
                tone: AgentDispatchSectionTone.repository,
              ),
              AgentDispatchRepositoryField(
                controller: _repoController,
                paths: _settings.repoPaths,
                enabled: !_running && !_busy,
                errorText: _repoErrorText,
                onChanged: (value) {
                  setState(() {
                    _settings =
                        _settings.bindRepoToProject(widget.projectId, value);
                    _repoErrorText = null;
                  });
                },
                onPickDirectory: _pickRepo,
                onDeletePath: _deleteRepoPath,
              ),
              const SizedBox(height: 12),
              const AgentDispatchSectionHeader(
                title: 'Git commit identity',
                tone: AgentDispatchSectionTone.identity,
              ),
              const SizedBox(height: 8),
              AgentDispatchGitAuthorFields(
                nameController: _gitAuthorNameController,
                emailController: _gitAuthorEmailController,
                enabled: !_running && !_busy,
                onNameChanged: (value) => _persist(
                  _settings.copyWith(gitAuthorName: value),
                ),
                onEmailChanged: (value) => _persist(
                  _settings.copyWith(gitAuthorEmail: value),
                ),
              ),
              const SizedBox(height: 12),
              if (_settings.engine == AgentDispatchEngine.cursor) ...[
                const AgentDispatchSectionHeader(
                  title: 'Cursor API Key',
                  tone: AgentDispatchSectionTone.credential,
                ),
                CursorApiKeySection(
                  enabled: !_busy,
                  credentials: _credentials,
                  workerScriptPath: _settings.workerScriptPath,
                  onActiveKeyChanged: _onCursorKeyChanged,
                ),
                const SizedBox(height: 12),
                AgentDispatchUsagePane(
                  snapshot: _usage,
                  loading: _usageBusy,
                  onOpenTokenStats: () => showAgentDispatchTokenStatsDialog(
                    context: context,
                    projectId: widget.projectId,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _models.isEmpty
                        ? InputDecorator(
                            decoration: agentDispatchCompactDropdownDecoration(
                              'Model',
                            ),
                            child: Text(
                              'Not loaded yet',
                              style: agentDispatchCompactDropdownStyle(context),
                            ),
                          )
                        : DropdownButtonFormField<String>(
                            key: ValueKey('model-${_settings.modelId}'),
                            initialValue:
                                _models.any((m) => m.id == _settings.modelId)
                                    ? _settings.modelId
                                    : _models.first.id,
                            isDense: true,
                            isExpanded: true,
                            style: agentDispatchCompactDropdownStyle(context),
                            decoration:
                                agentDispatchCompactDropdownDecoration('Model'),
                            items: [
                              for (final m in _models)
                                DropdownMenuItem(
                                  value: m.id,
                                  child: Text(
                                    m.label,
                                    style: agentDispatchCompactDropdownStyle(
                                      context,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (id) {
                                    AgentDispatchModelInfo? selected;
                                    for (final model in _models) {
                                      if (model.id == id) {
                                        selected = model;
                                        break;
                                      }
                                    }
                                    _persist(_settings.copyWith(
                                      modelId: id,
                                      modelParamValues:
                                          preferredAgentDispatchModelParamValues(
                                        selected?.parameters ?? const [],
                                      ),
                                    ));
                                  },
                          ),
                  ),
                  if (modelParameters.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: AgentDispatchModelParameters(
                        parameters: modelParameters,
                        defaultVariant: _selectedModel?.defaultVariant,
                        values: _settings.modelParamValues,
                        enabled: !_busy,
                        onChanged: (id, value) {
                          final values = Map<String, String>.from(
                            _settings.modelParamValues,
                          );
                          if (value == 'default') {
                            values.remove(id);
                          } else {
                            values[id] = value;
                          }
                          _persist(
                            _settings.copyWith(modelParamValues: values),
                          );
                        },
                      ),
                    ),
                  ],
                  TextButton(
                    onPressed: _busy ? null : _loadModels,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(_busy ? 'Refreshing…' : 'Refresh'),
                  ),
                ],
              ),
              AgentDispatchRunToggles(
                ignoreCardParams: _settings.ignoreCardParams,
                allowDirtyWorkspace: _settings.allowDirtyWorkspace,
                enableSandbox: _settings.enableSandbox,
                requireTests: _settings.requireTests,
                terminateAfterDispatchTerminal:
                    _settings.terminateAfterDispatchTerminal,
                enabled: !_busy,
                onIgnoreCardParamsChanged: (value) => _persist(
                  _settings.copyWith(ignoreCardParams: value),
                ),
                onAllowDirtyWorkspaceChanged: (value) => _persist(
                  _settings.copyWith(allowDirtyWorkspace: value),
                ),
                onEnableSandboxChanged: (value) => _persist(
                  _settings.copyWith(enableSandbox: value),
                ),
                onRequireTestsChanged: (value) => _persist(
                  _settings.copyWith(requireTests: value),
                ),
                onTerminateAfterDispatchTerminalChanged: (value) => _persist(
                  _settings.copyWith(terminateAfterDispatchTerminal: value),
                ),
              ),
              const SizedBox(height: 12),
              AgentDispatchCardLimitField(
                controller: _countController,
                useMax: _settings.cardLimitMax,
                enabled: !_running && !_busy,
                errorText: _countErrorText,
                onMaxChanged: (value) {
                  setState(() => _countErrorText = null);
                  _persist(_settings.copyWith(cardLimitMax: value));
                },
                onCountChanged: (_) {
                  if (_countErrorText != null) {
                    setState(() => _countErrorText = null);
                  }
                },
              ),
              const SizedBox(height: 12),
              AgentDispatchAfterQueueField(
                steps: _settings.afterQueueFor(widget.projectId),
                enabled: !_busy,
                onChanged: (steps) async {
                  await _persistAfterQueue(
                    _settings.bindAfterQueueToProject(
                      widget.projectId,
                      steps: steps,
                    ),
                  );
                },
                runOnFailure:
                    _settings.runAfterQueueOnFailureFor(widget.projectId),
                onRunOnFailureChanged: (value) async {
                  await _persistAfterQueue(
                    _settings.bindAfterQueueToProject(
                      widget.projectId,
                      runOnFailure: value,
                    ),
                  );
                },
              ),
              if (_modelCatalogMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    _modelCatalogMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_models.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Model catalog is not loaded; click "Refresh" to load it',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (_selectedModel != null && modelParameters.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Cursor API provides no adjustable parameters for this model',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          worker: AgentDispatchWorkerPane(
            workerStatus: _workerStatus,
            enabled: !_running && !_busy,
            onFixWorker: _fixWorker,
          ),
          skill: AgentDispatchSkillPane(
            skillPath: skillPath,
            skillPreview: _skillPreview,
            enabled: !_running && !_busy,
            onOpenSkillDirectory: _openSkillDirectory,
            onRefreshSkill: _refreshSkillPreview,
          ),
          log: AgentDispatchLogPane(
            controller: _logController,
            running: _running,
            progress: _liveProgress(board.board),
            pendingInteraction: _service.pendingInteraction,
            onInteractionReply: _replyInteraction,
            onClear: _clearLog,
            onExport: _exportLog,
            onCopy: _copyLog,
          ),
        ),
      ),
      actions: [
        const TextButton(
          onPressed: AgentDispatchWindow.backToHub,
          child: Text('Back to overview'),
        ),
        const TextButton(
          onPressed: AgentDispatchWindow.hide,
          child: Text('Close'),
        ),
        if (_running) ...[
          TextButton(
            onPressed: _skipping || _stopping || _drainPending
                ? null
                : () async {
                    setState(() => _skipping = true);
                    _appendLog(
                      'Moving the current card to Blocked and switching to the next…',
                      level: AgentDispatchLogLevel.warning,
                    );
                    await _service.requestSkipToNext(
                      boardController: context.read<BoardController>(),
                    );
                    if (mounted) _syncRunningFromService();
                  },
            child: Text(_skipping ? 'Switching…' : 'Next'),
          ),
          TextButton(
            onPressed: _drainPending || _stopping || _skipping
                ? null
                : () async {
                    setState(() => _drainPending = true);
                    _appendLog(
                      'The batch will stop after the current session…',
                      level: AgentDispatchLogLevel.warning,
                    );
                    await _service.requestDrainAfterCurrent();
                    if (mounted) _syncRunningFromService();
                  },
            child: Text(_drainPending
                ? 'Stopping after current session…'
                : 'Stop after current session'),
          ),
          TextButton(
            onPressed: _stopping || _skipping
                ? null
                : () async {
                    setState(() => _stopping = true);
                    _appendLog(
                      'Stopping the current SDK/CLI session now…',
                      level: AgentDispatchLogLevel.warning,
                    );
                    await _service.requestCancel();
                    if (mounted) _syncRunningFromService();
                  },
            child: Text(_stopping ? 'Stopping…' : 'Stop now'),
          ),
        ],
        FilledButton.icon(
          onPressed:
              _running || _busy || _stopping || _drainPending || _skipping
                  ? null
                  : _run,
          icon: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Text(_running ? 'Running…' : 'Run'),
        ),
      ],
    );
  }
}

String _modelRefreshFailureMessage({
  required Object error,
  required bool hasCache,
}) {
  final text = '$error'.toLowerCase();
  final suffix = hasCache
      ? '; continuing to use the last successfully loaded model catalog'
      : '';
  if (text.contains('networkerror') ||
      text.contains('fetch failed') ||
      text.contains('connect timeout')) {
    return 'Cursor API network connection failed$suffix; no need to re-enter the Key';
  }
  if (text.contains('authenticationerror') ||
      text.contains('invalid api key') ||
      text.contains('unauthorized')) {
    return 'Cursor API Key authentication failed; save a valid Key again$suffix';
  }
  return hasCache
      ? 'Refresh failed; continuing to use the last successfully loaded model catalog'
      : 'Refresh failed; the model catalog could not be loaded; see the log below';
}
