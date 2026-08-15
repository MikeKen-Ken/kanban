import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../../features/import_export/backup_file_picker.dart';
import '../kanban/next_work_card.dart';
import 'agent_dispatch_after_queue.dart';
import 'agent_dispatch_after_queue_field.dart';
import 'agent_dispatch_config.dart';
import 'agent_dispatch_card_limit_field.dart';
import 'agent_dispatch_credentials.dart';
import 'agent_dispatch_directory_opener.dart';
import 'agent_dispatch_log_exporter.dart';
import 'agent_dispatch_log.dart';
import 'agent_dispatch_log_refresh_scheduler.dart';
import 'agent_dispatch_model_catalog_store.dart';
import 'agent_dispatch_model_parameters.dart';
import 'agent_dispatch_repository_field.dart';
import 'agent_dispatch_registry.dart';
import 'agent_dispatch_service.dart';
import 'agent_dispatch_settings.dart';
import 'agent_dispatch_token_stats_dialog.dart';
import 'agent_dispatch_usage.dart';
import 'agent_dispatch_usage_pane.dart';
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
    AgentDispatchWindow.visible.addListener(_onWindowVisibilityChanged);
    if (_running) _startHeartbeat();
    _bootstrap();
  }

  void _onWindowVisibilityChanged() {
    if (!AgentDispatchWindow.visible.value || !mounted) return;
    if (!_settings.cardLimitMax) {
      setState(() => _settings = _settings.copyWith(cardLimitMax: true));
    }
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

  void _onServiceRunningChanged() {
    if (!mounted) return;
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

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = prefs.loadAgentDispatchSettings();
    final cachedModels = prefs.loadAgentDispatchModelCatalog(
      engine: loaded.engine,
    );
    final cachedModelId = cachedModels.isEmpty
        ? loaded.modelId
        : resolveAgentDispatchModelId(cachedModels, loaded.modelId);
    var normalized = cachedModelId == loaded.modelId
        ? loaded
        : loaded.copyWith(
            modelId: cachedModelId,
            modelParamValues: const {},
          );
    if (_isStockModelParams(normalized.modelParamValues)) {
      AgentDispatchModelInfo? selected;
      for (final model in cachedModels) {
        if (model.id == (normalized.modelId ?? cachedModelId)) {
          selected = model;
          break;
        }
      }
      normalized = normalized.copyWith(
        modelParamValues: preferredAgentDispatchModelParamValues(
          selected?.parameters ?? const [],
        ),
      );
    }
    if (normalized != loaded) {
      await prefs.saveAgentDispatchSettings(normalized);
    }
    if (!mounted) return;
    setState(() {
      _settings = normalized;
      _models = cachedModels;
      _repoController.text = normalized.repoPathByProject[widget.projectId] ??
          normalized.repoPath ??
          '';
      _countController.text = '${normalized.cardLimitCount}';
    });
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
    setState(() => _settings = synced);
    final prefs = await SharedPreferences.getInstance();
    await prefs.saveAgentDispatchSettings(synced);
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
      _appendLog('仍在运行（已 $elapsed 秒），等待当前独立调用返回…');
      setState(() {});
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<void> _clearLog() async {
    await _service.clearLog();
    if (mounted) setState(_syncLogFromService);
  }

  Future<void> _exportLog() async {
    final exported = await exportAgentDispatchLog(_logController.text);
    if (!mounted) return;
    showAppSnackBar(context, message: exported ? '调度记录已导出' : '已取消导出');
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _logController.text));
    if (!mounted) return;
    showAppSnackBar(context, message: '调度记录已复制');
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
          ? '健康：${health.summary}\n${health.workerRoot}'
          : '${health.error ?? 'Worker 健康检查失败'}\n${health.summary}';
    });
  }

  Future<void> _pickRepo() async {
    final path = await pickBackupDirectory();
    if (path == null || !mounted) return;
    _repoController.text = path;
    final projectId = widget.projectId;
    var next = _rememberRepo(_settings.copyWith(repoPath: path), path);
    final map = Map<String, String>.from(next.repoPathByProject)
      ..[projectId] = path;
    next = next.copyWith(repoPathByProject: map);
    await _persist(next);
    if (!mounted) return;
    setState(() => _repoErrorText = null);
  }

  AgentDispatchSettings _rememberRepo(
    AgentDispatchSettings settings,
    String path,
  ) {
    final normalized = path.trim();
    if (normalized.isEmpty) return settings;
    final paths = [
      normalized,
      ...settings.repoPaths.where((item) => item != normalized),
    ];
    return settings.copyWith(repoPaths: paths);
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
      _appendLog('无法打开 Skill 所在目录', level: AgentDispatchLogLevel.warning);
    }
  }

  Future<void> _fixWorker() async {
    if (_busy) return;
    setState(() => _busy = true);
    _appendLog('开始修复 Worker…');
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
              : _settings.modelParamValues;
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
      _appendLog('已加载 ${uniqueModels.length} 个模型');
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
      _appendLog('拉取模型失败：$e', level: AgentDispatchLogLevel.error);
    }
  }

  Future<void> _onCursorKeyChanged() async {
    await _loadAccountInfo();
  }

  Future<void> _loadAccountInfo() async {
    if (_usageBusy || _settings.engine != AgentDispatchEngine.cursor) return;
    setState(() => _usageBusy = true);
    try {
      final snapshot = await fetchAgentDispatchUsage(
        cursorApiKey: await _credentials.resolveCursorApiKey(),
        workerScriptPath: _settings.workerScriptPath,
      );
      final name = snapshot.apiKeyName?.trim();
      final email = snapshot.userEmail?.trim();
      final label = name != null && name.isNotEmpty
          ? name
          : email != null && email.isNotEmpty
              ? email
              : null;
      if (label != null) {
        await _credentials.updateActiveCursorApiKeyLabel(label);
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
          message: '账号信息刷新失败：$e',
        );
      });
    }
  }

  bool _isStockModelParams(Map<String, String> values) {
    if (values.isEmpty) return true;
    if (values.length == 1 &&
        (values['fast'] == 'true' || values['fast'] == 'false')) {
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
    if (nextEngine == null || _running || _busy) return;
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
          : switched.modelParamValues,
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
      _repoErrorText = repo.isEmpty ? '请填写代码仓库路径' : null;
      _projectErrorText = projectMissing ? '项目不存在' : null;
      _countErrorText = countInvalid ? '请输入 1–999' : null;
    });
    if (repo.isEmpty || projectMissing || countInvalid) {
      return;
    }
    var next = _rememberRepo(
        _settings.copyWith(
          useProject: true,
          projectId: projectId,
          repoPath: repo,
          cardLimitCount: count!,
        ),
        repo);
    final map = Map<String, String>.from(next.repoPathByProject)
      ..[projectId] = repo;
    next = next.copyWith(repoPathByProject: map);
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
    if (options.repoPath.isEmpty) {
      _appendLog('请填写代码仓库路径', level: AgentDispatchLogLevel.warning);
      return;
    }
    if (!board.mcpHost.isRunning) {
      _appendLog(
        '看板 MCP 未运行，Worker 无法只读检查队列；请先在设置中启用 MCP',
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
      '\n—— ${DateTime.now().toLocal().toString().substring(0, 19)} 新运行 ——',
    );
    _appendLog('引擎：${options.engine.label}');
    final result = await _service.runOnce(
      options: options,
      skillPath: next.resolveSkillPath(),
      mcpEndpoint: board.mcpHost.endpointUrl,
      agentMcpEndpoint: board.mcpHost.agentEndpointUrl,
      workerScriptPath: next.workerScriptPath,
      queueSize: queueSize,
      afterQueue: next.afterQueue,
      runAfterQueueOnFailure: next.runAfterQueueOnFailure,
      afterQueueHost: AgentDispatchAfterQueueHost(
        uploadAll: board.uploadNow,
        gitPush: () => gitPushWithRebase(repoPath: options.repoPath),
        sleep: windowsSleepNow,
        shutdown: windowsShutdownNow,
      ),
    );
    if (!mounted) return;
    if (result.ok) {
      _appendLog(result.summary ?? '完成', level: AgentDispatchLogLevel.success);
    } else if (result.error == '已取消') {
      _appendLog('已停止运行', level: AgentDispatchLogLevel.warning);
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
        title: const Text('仓库已被其它项目占用'),
        content: Text(
          '项目「$otherTitle」正在同一仓库运行：\n$repo\n\n'
          '并行可能导致互相改到同一批文件。仍要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('仍要运行'),
          ),
        ],
      ),
    );
    return go == true;
  }

  @override
  void dispose() {
    _logRefreshScheduler.cancel();
    AgentDispatchWindow.visible.removeListener(_onWindowVisibilityChanged);
    _service.removeLogListener(_onServiceLog);
    _service.removeRunningListener(_onServiceRunningChanged);
    _stopHeartbeat();
    _repoController.dispose();
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
    final dialogWidth = (viewport.width - 96).clamp(560.0, 1320.0).toDouble();
    final dialogHeight = (viewport.height - 180).clamp(420.0, 820.0).toDouble();

    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      title: Text('Agent 调度工作台 · $projectTitle'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: AgentDispatchWorkspace(
          settings: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('引擎', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              DropdownButtonFormField<AgentDispatchEngine>(
                key: ValueKey('engine-${_settings.engine}'),
                initialValue: _settings.engine,
                decoration: const InputDecoration(labelText: 'AI 平台'),
                items: [
                  for (final e in AgentDispatchEngine.values)
                    DropdownMenuItem(value: e, child: Text(e.label)),
                ],
                onChanged: _running || _busy ? null : _onEngineChanged,
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
              Text('代码仓库', style: Theme.of(context).textTheme.labelLarge),
              AgentDispatchRepositoryField(
                controller: _repoController,
                paths: _settings.repoPaths,
                enabled: !_running && !_busy,
                errorText: _repoErrorText,
                onChanged: (value) {
                  final trimmed = value.trim();
                  setState(() {
                    _settings = _settings.copyWith(repoPath: trimmed);
                    _repoErrorText = null;
                  });
                },
                onPickDirectory: _pickRepo,
                onDeletePath: _deleteRepoPath,
              ),
              const SizedBox(height: 12),
              if (_settings.engine == AgentDispatchEngine.cursor) ...[
                Text('Cursor API Key',
                    style: Theme.of(context).textTheme.labelLarge),
                CursorApiKeySection(
                  enabled: !_running && !_busy,
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
                  Text('模型', style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: _running || _busy ? null : _loadModels,
                    child: Text(_busy ? '刷新中…' : '从 API 刷新'),
                  ),
                ],
              ),
              if (_modelCatalogMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _modelCatalogMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_models.isEmpty)
                Text(
                  '尚未加载模型目录；请点击「从 API 刷新」手动拉取',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                DropdownButtonFormField<String>(
                  key: ValueKey('model-${_settings.modelId}'),
                  initialValue: _models.any((m) => m.id == _settings.modelId)
                      ? _settings.modelId
                      : _models.first.id,
                  decoration: const InputDecoration(labelText: '模型 id'),
                  items: [
                    for (final m in _models)
                      DropdownMenuItem(
                        value: m.id,
                        child: Text(m.label),
                      ),
                  ],
                  onChanged: _running || _busy
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
              AgentDispatchModelParameters(
                parameters: modelParameters,
                defaultVariant: _selectedModel?.defaultVariant,
                values: _settings.modelParamValues,
                enabled: !_running && !_busy,
                onChanged: (id, value) {
                  final values = Map<String, String>.from(
                    _settings.modelParamValues,
                  );
                  if (value == 'default') {
                    values.remove(id);
                  } else {
                    values[id] = value;
                  }
                  _persist(_settings.copyWith(modelParamValues: values));
                },
              ),
              if (_selectedModel != null && modelParameters.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Cursor API 未为此模型提供可调参数',
                    style: Theme.of(context).textTheme.bodySmall,
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
                steps: _settings.afterQueue,
                enabled: !_running && !_busy,
                onChanged: (steps) =>
                    _persist(_settings.copyWith(afterQueue: steps)),
                runOnFailure: _settings.runAfterQueueOnFailure,
                onRunOnFailureChanged: (value) => _persist(
                  _settings.copyWith(runAfterQueueOnFailure: value),
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
            onClear: _clearLog,
            onExport: _exportLog,
            onCopy: _copyLog,
          ),
        ),
      ),
      actions: [
        const TextButton(
          onPressed: AgentDispatchWindow.backToHub,
          child: Text('返回总览'),
        ),
        const TextButton(
          onPressed: AgentDispatchWindow.hide,
          child: Text('关闭'),
        ),
        if (_running) ...[
          TextButton(
            onPressed: _skipping || _stopping || _drainPending
                ? null
                : () async {
                    setState(() => _skipping = true);
                    _appendLog(
                      '正在将当前卡片移入阻塞中并切换到下一张…',
                      level: AgentDispatchLogLevel.warning,
                    );
                    await _service.requestSkipToNext(
                      boardController: context.read<BoardController>(),
                    );
                    if (mounted) setState(() {});
                  },
            child: Text(_skipping ? '正在切换…' : '下一个'),
          ),
          TextButton(
            onPressed: _drainPending || _stopping || _skipping
                ? null
                : () async {
                    setState(() => _drainPending = true);
                    _appendLog(
                      '将在当前会话结束后停止批次…',
                      level: AgentDispatchLogLevel.warning,
                    );
                    await _service.requestDrainAfterCurrent();
                    if (mounted) setState(() {});
                  },
            child: Text(_drainPending ? '当前会话后停止中…' : '当前会话后停止'),
          ),
          TextButton(
            onPressed: _stopping || _skipping
                ? null
                : () async {
                    setState(() => _stopping = true);
                    _appendLog(
                      '正在立即停止当前 SDK/CLI 会话…',
                      level: AgentDispatchLogLevel.warning,
                    );
                    await _service.requestCancel();
                    if (mounted) setState(() {});
                  },
            child: Text(_stopping ? '正在停止…' : '立即停止'),
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
          label: Text(_running ? '运行中…' : '运行'),
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
  final suffix = hasCache ? '，继续使用上次成功加载的模型目录' : '';
  if (text.contains('networkerror') ||
      text.contains('fetch failed') ||
      text.contains('connect timeout')) {
    return 'Cursor API 网络连接失败$suffix；无需重新输入 Key';
  }
  if (text.contains('authenticationerror') ||
      text.contains('invalid api key') ||
      text.contains('unauthorized')) {
    return 'Cursor API Key 认证失败，请重新保存有效的 Key$suffix';
  }
  return hasCache ? '刷新失败，继续使用上次成功加载的模型目录' : '刷新失败，未能加载模型目录；请查看下方日志';
}
