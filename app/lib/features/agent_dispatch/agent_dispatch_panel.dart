import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../../features/import_export/backup_file_picker.dart';
import 'agent_dispatch_config.dart';
import 'agent_dispatch_card_limit_field.dart';
import 'agent_dispatch_credentials.dart';
import 'agent_dispatch_directory_opener.dart';
import 'agent_dispatch_log_exporter.dart';
import 'agent_dispatch_log_store.dart';
import 'agent_dispatch_model_catalog_store.dart';
import 'agent_dispatch_model_parameters.dart';
import 'agent_dispatch_platform.dart';
import 'agent_dispatch_repository_field.dart';
import 'agent_dispatch_service.dart';
import 'agent_dispatch_settings.dart';
import 'agent_dispatch_worker.dart';
import 'cursor_api_key_section.dart';

/// 左上角「新建项目」右侧入口（仅桌面）。
class AgentDispatchToolbarButton extends StatelessWidget {
  const AgentDispatchToolbarButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!isAgentDispatchDesktop) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Agent 调度',
      icon: const Icon(Icons.smart_toy_outlined),
      onPressed: () => showAgentDispatchPanel(context),
    );
  }
}

Future<void> showAgentDispatchPanel(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const AgentDispatchPanel(),
  );
}

class AgentDispatchPanel extends StatefulWidget {
  const AgentDispatchPanel({super.key});

  @override
  State<AgentDispatchPanel> createState() => _AgentDispatchPanelState();
}

class _AgentDispatchPanelState extends State<AgentDispatchPanel> {
  static const _credentials = AgentDispatchCredentials();
  AgentDispatchSettings _settings = const AgentDispatchSettings();
  final _repoController = TextEditingController();
  final _countController = TextEditingController(text: '1');
  final _logController = TextEditingController();
  final _service = AgentDispatchService();

  List<AgentDispatchModelInfo> _models = const [];
  String? _skillPreview;
  String? _workerStatus;
  String? _repoErrorText;
  String? _projectErrorText;
  String? _countErrorText;
  String? _modelCatalogMessage;
  bool _running = false;
  bool _busy = false;
  Future<void> _logSaveQueue = Future.value();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = prefs.loadAgentDispatchSettings();
    final cachedModels = prefs.loadAgentDispatchModelCatalog();
    final cachedModelId = cachedModels.isEmpty
        ? loaded.modelId
        : resolveAgentDispatchModelId(cachedModels, loaded.modelId);
    final normalized = cachedModelId == loaded.modelId
        ? loaded
        : loaded.copyWith(
            modelId: cachedModelId,
            modelParamValues: const {},
          );
    if (normalized != loaded) {
      await prefs.saveAgentDispatchSettings(normalized);
    }
    if (!mounted) return;
    setState(() {
      _settings = normalized;
      _models = cachedModels;
      _repoController.text = normalized.repoPath ?? '';
      _countController.text = '${normalized.cardLimitCount}';
      _logController.text = prefs.loadAgentDispatchLog();
    });
    await _refreshSkillPreview();
    await _refreshWorkerStatus();
  }

  Future<void> _persist(AgentDispatchSettings next) async {
    setState(() => _settings = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.saveAgentDispatchSettings(next);
  }

  void _appendLog(String line) {
    final next =
        _logController.text.isEmpty ? line : '${_logController.text}\n$line';
    _logController.text = next;
    _logController.selection = TextSelection.collapsed(offset: next.length);
    _logSaveQueue = _logSaveQueue.then((_) => _saveLog(next));
    unawaited(_logSaveQueue);
  }

  Future<void> _saveLog(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.saveAgentDispatchLog(value);
  }

  Future<void> _clearLog() async {
    _logController.clear();
    await _logSaveQueue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clearAgentDispatchLog();
    if (mounted) setState(() {});
  }

  Future<void> _exportLog() async {
    final exported = await exportAgentDispatchLog(_logController.text);
    if (!mounted) return;
    showAppSnackBar(context, message: exported ? '调度记录已导出' : '已取消导出');
  }

  Future<void> _refreshSkillPreview() async {
    final path = _settings.resolveSkillPath();
    final preview = await peekSkillPreview(path);
    if (!mounted) return;
    setState(() => _skillPreview = preview);
  }

  Future<void> _refreshWorkerStatus() async {
    final cli = await resolveAgentDispatchCliPath(_settings.workerScriptPath);
    if (!mounted) return;
    setState(() {
      _workerStatus = cli == null ? '未找到 Worker（需一键修复）' : '已就绪：$cli';
    });
  }

  Future<void> _pickRepo() async {
    final path = await pickBackupDirectory();
    if (path == null || !mounted) return;
    _repoController.text = path;
    final board = context.read<BoardController>();
    final projectId =
        _settings.useProject ? _settings.projectId : board.activeProjectId;
    var next = _rememberRepo(_settings.copyWith(repoPath: path), path);
    if (projectId != null) {
      final map = Map<String, String>.from(next.repoPathByProject)
        ..[projectId] = path;
      next = next.copyWith(repoPathByProject: map);
    }
    await _persist(next);
    if (mounted) setState(() => _repoErrorText = null);
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

  Future<void> _deleteCurrentRepo() async {
    final path = _repoController.text.trim();
    if (path.isEmpty || !_settings.repoPaths.contains(path)) return;
    final paths = _settings.repoPaths.where((item) => item != path).toList();
    final byProject = Map<String, String>.from(_settings.repoPathByProject)
      ..removeWhere((_, value) => value == path);
    _repoController.clear();
    await _persist(_settings.copyWith(
      repoPath: null,
      repoPaths: paths,
      repoPathByProject: byProject,
    ));
  }

  Future<void> _openSkillDirectory() async {
    final opened = await openAgentDispatchSkillDirectory(
      _settings.resolveSkillPath(),
    );
    if (!opened) _appendLog('无法打开 Skill 所在目录');
  }

  Future<void> _fixWorker() async {
    if (_busy) return;
    setState(() => _busy = true);
    _appendLog('开始修复 Worker…');
    final result = await ensureAgentDispatchWorker(
      workerScriptPath: _settings.workerScriptPath,
      onLog: (l) {
        if (mounted) setState(() => _appendLog(l));
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _appendLog(result.message);
    await _refreshWorkerStatus();
  }

  Future<void> _loadModels() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final models = await listAgentDispatchModels(
        cursorApiKey: await _credentials.resolveCursorApiKey(),
        workerScriptPath: _settings.workerScriptPath,
        onLog: (l) {
          if (mounted) setState(() => _appendLog(l));
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
      setState(() {
        _models = uniqueModels;
        _busy = false;
        _modelCatalogMessage = null;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.saveAgentDispatchModelCatalog(uniqueModels);
      _appendLog('已加载 ${uniqueModels.length} 个模型');
      if (selectionChanged) {
        await _persist(_settings.copyWith(
          modelId: selectedId,
          modelParamValues: const {},
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _modelCatalogMessage = _modelRefreshFailureMessage(
          error: e,
          hasCache: _models.isNotEmpty,
        );
      });
      _appendLog('拉取模型失败：$e');
    }
  }

  AgentDispatchModelInfo? get _selectedModel {
    final id = _settings.modelId;
    if (id == null) return null;
    for (final m in _models) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _run() async {
    if (_running) return;
    final board = context.read<BoardController>();
    final count = int.tryParse(_countController.text.trim());
    final repo = _repoController.text.trim();
    final projectMissing = _settings.useProject && _settings.projectId == null;
    final countInvalid =
        !_settings.cardLimitMax && (count == null || count < 1 || count > 999);
    setState(() {
      _repoErrorText = repo.isEmpty ? '请填写代码仓库路径' : null;
      _projectErrorText = projectMissing ? '请选择看板项目' : null;
      _countErrorText = countInvalid ? '请输入 1–999' : null;
    });
    if (repo.isEmpty || projectMissing || countInvalid) {
      return;
    }
    var next = _rememberRepo(
        _settings.copyWith(
          repoPath: repo,
          cardLimitCount: count!,
        ),
        repo);
    final projectId = next.useProject ? next.projectId : board.activeProjectId;
    if (projectId != null) {
      final map = Map<String, String>.from(next.repoPathByProject)
        ..[projectId] = repo;
      next = next.copyWith(repoPathByProject: map);
    }
    await _persist(next);

    final options = next.toRunOptions(
      projectTitleOf: (id) => board.manifest?.findById(id)?.title,
    );
    if (options.repoPath.isEmpty) {
      _appendLog('请填写代码仓库路径');
      return;
    }

    setState(() {
      _running = true;
    });
    _appendLog(
      '\n—— ${DateTime.now().toLocal().toString().substring(0, 19)} 新运行 ——',
    );
    _appendLog('引擎：${options.engine.label}');
    final result = await _service.runOnce(
      options: options,
      skillPath: next.resolveSkillPath(),
      workerScriptPath: next.workerScriptPath,
      onLog: (line) {
        if (!mounted) return;
        setState(() => _appendLog(line));
      },
    );
    if (!mounted) return;
    setState(() => _running = false);
    if (result.ok) {
      _appendLog(result.summary ?? '完成');
    } else {
      _appendLog(result.error ?? '失败');
    }
  }

  @override
  void dispose() {
    _repoController.dispose();
    _countController.dispose();
    _logController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = context.watch<BoardController>();
    final projects = board.manifest?.projects ?? const [];
    final modelParameters = _selectedModel?.parameters ?? const [];
    final skillPath = _settings.resolveSkillPath();

    return AlertDialog(
      title: const Text('Agent 调度'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('引擎', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<AgentDispatchEngine>(
                segments: [
                  for (final e in AgentDispatchEngine.values)
                    ButtonSegment(value: e, label: Text(e.label)),
                ],
                selected: {_settings.engine},
                onSelectionChanged: _running || _busy
                    ? null
                    : (s) {
                        setState(() => _models = const []);
                        _persist(_settings.copyWith(
                          engine: s.first,
                          modelId: null,
                          modelParamValues: const {},
                        ));
                      },
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('指定看板项目（默认使用当前项目）'),
                value: _settings.useProject,
                onChanged: _running || _busy
                    ? null
                    : (v) {
                        setState(() => _projectErrorText = null);
                        _persist(_settings.copyWith(useProject: v ?? false));
                      },
              ),
              if (_settings.useProject)
                DropdownButtonFormField<String>(
                  key: ValueKey('project-${_settings.projectId}'),
                  initialValue: projects.any((p) => p.id == _settings.projectId)
                      ? _settings.projectId
                      : null,
                  decoration: InputDecoration(
                    labelText: '项目',
                    errorText: _projectErrorText,
                  ),
                  items: [
                    for (final p in projects)
                      DropdownMenuItem(value: p.id, child: Text(p.title)),
                  ],
                  onChanged: _running || _busy
                      ? null
                      : (id) {
                          final remembered = id == null
                              ? null
                              : _settings.repoPathByProject[id];
                          _persist(_settings.copyWith(
                            projectId: id,
                            repoPath: remembered ?? _settings.repoPath,
                          ));
                          if (remembered != null) {
                            _repoController.text = remembered;
                          }
                          setState(() => _projectErrorText = null);
                        },
                ),
              const SizedBox(height: 8),
              Text('代码仓库', style: Theme.of(context).textTheme.labelLarge),
              AgentDispatchRepositoryField(
                controller: _repoController,
                paths: _settings.repoPaths,
                enabled: !_running && !_busy,
                errorText: _repoErrorText,
                onChanged: (value) {
                  setState(() {
                    _settings = _settings.copyWith(repoPath: value.trim());
                    _repoErrorText = null;
                  });
                },
                onPickDirectory: _pickRepo,
                onDeleteCurrent:
                    _settings.repoPaths.contains(_repoController.text.trim())
                        ? _deleteCurrentRepo
                        : null,
              ),
              const SizedBox(height: 12),
              if (_settings.engine == AgentDispatchEngine.cursor) ...[
                CursorApiKeySection(
                  enabled: !_running && !_busy,
                  credentials: _credentials,
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Text('模型', style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  if (_settings.engine == AgentDispatchEngine.cursor)
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
              if (_settings.engine == AgentDispatchEngine.codex)
                Text(
                  '使用本机 Codex CLI 的默认模型与登录状态',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else if (_models.isEmpty)
                Text(
                  _settings.modelId ?? '尚未加载；可点刷新，或稍后手动依赖默认模型',
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
                        child: Text(
                          m.displayName == null || m.displayName == m.id
                              ? m.id
                              : '${m.displayName}（${m.id}）',
                        ),
                      ),
                  ],
                  onChanged: _running || _busy
                      ? null
                      : (id) => _persist(_settings.copyWith(
                            modelId: id,
                            modelParamValues: const {},
                          )),
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
              Row(
                children: [
                  Text('Skill', style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  IconButton(
                    tooltip: '打开 Skill 目录',
                    onPressed: _running || _busy ? null : _openSkillDirectory,
                    icon: const Icon(Icons.folder_open_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: '重新读取 Skill',
                    onPressed: _running || _busy ? null : _refreshSkillPreview,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
              Text(skillPath, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Container(
                height: 120,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _skillPreview ?? '（未找到或无法读取 Skill）',
                    style:
                        const TextStyle(fontFamily: 'Consolas', fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Worker', style: Theme.of(context).textTheme.labelLarge),
              Text(
                _workerStatus ?? '检查中…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _running || _busy ? null : _fixWorker,
                  icon: const Icon(Icons.build_outlined, size: 18),
                  label: const Text('一键修复 Worker'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '工具对话记录',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _running || _logController.text.isEmpty
                        ? null
                        : _clearLog,
                    child: const Text('清空记录'),
                  ),
                  TextButton.icon(
                    onPressed: _logController.text.isEmpty ? null : _exportLog,
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('导出记录'),
                  ),
                ],
              ),
              SizedBox(
                height: 220,
                child: Scrollbar(
                  thumbVisibility: true,
                  child: TextField(
                    controller: _logController,
                    readOnly: true,
                    maxLines: null,
                    expands: true,
                    scrollPhysics: const AlwaysScrollableScrollPhysics(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style:
                        const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        if (_running)
          TextButton(
            onPressed: () {
              _service.requestCancel();
              _appendLog('已请求取消（进行中的会话可能仍会跑完）');
            },
            child: const Text('取消'),
          ),
        FilledButton.icon(
          onPressed: _running || _busy ? null : _run,
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
