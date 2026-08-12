import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/board_controller.dart';
import '../../features/import_export/backup_file_picker.dart';
import 'agent_dispatch_config.dart';
import 'agent_dispatch_credentials.dart';
import 'agent_dispatch_platform.dart';
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
    barrierDismissible: false,
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
  bool _running = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = prefs.loadAgentDispatchSettings();
    if (!mounted) return;
    setState(() {
      _settings = loaded;
      _repoController.text = loaded.repoPath ?? '';
      _countController.text = '${loaded.cardLimitCount}';
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
    var next = _settings.copyWith(repoPath: path);
    if (projectId != null) {
      final map = Map<String, String>.from(next.repoPathByProject)
        ..[projectId] = path;
      next = next.copyWith(repoPathByProject: map);
    }
    await _persist(next);
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
      setState(() {
        _models = models;
        _busy = false;
      });
      _appendLog('已加载 ${models.length} 个模型');
      if (_settings.modelId == null && models.isNotEmpty) {
        await _persist(_settings.copyWith(modelId: models.first.id));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
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

  AgentDispatchModelParameter? get _effortParam {
    final model = _selectedModel;
    if (model == null) return null;
    for (final p in model.parameters) {
      if (p.id == 'reasoning_effort' ||
          p.id == 'model_reasoning_effort' ||
          p.id == 'fast' ||
          p.id == 'optimize_for') {
        return p;
      }
    }
    return model.parameters.isEmpty ? null : model.parameters.first;
  }

  Future<void> _run() async {
    if (_running) return;
    final board = context.read<BoardController>();
    final count = int.tryParse(_countController.text.trim()) ?? 1;
    final repo = _repoController.text.trim();
    if (repo.isEmpty) {
      _appendLog('请填写代码仓库路径');
      return;
    }
    var next = _settings.copyWith(
      repoPath: repo,
      cardLimitCount: count,
    );
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
      _logController.clear();
    });
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
    final effortParam = _effortParam;
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
                          effortParamId: null,
                          effortParamValue: null,
                        ));
                      },
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('指定看板项目（否则用当前打开的项目，不写入调用正文）'),
                value: _settings.useProject,
                onChanged: _running || _busy
                    ? null
                    : (v) =>
                        _persist(_settings.copyWith(useProject: v ?? false)),
              ),
              if (_settings.useProject)
                DropdownButtonFormField<String>(
                  key: ValueKey('project-${_settings.projectId}'),
                  initialValue: projects.any((p) => p.id == _settings.projectId)
                      ? _settings.projectId
                      : null,
                  decoration: const InputDecoration(labelText: '项目'),
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
                        },
                ),
              const SizedBox(height: 8),
              Text('代码仓库（必填，会记住）',
                  style: Theme.of(context).textTheme.labelLarge),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _repoController,
                      enabled: !_running && !_busy,
                      decoration: const InputDecoration(
                        hintText: '本机仓库根目录',
                      ),
                      onChanged: (v) =>
                          _settings = _settings.copyWith(repoPath: v.trim()),
                    ),
                  ),
                  IconButton(
                    tooltip: '选择目录',
                    onPressed: _running || _busy ? null : _pickRepo,
                    icon: const Icon(Icons.folder_open),
                  ),
                ],
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
                      child: const Text('从 API 刷新'),
                    ),
                ],
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
                      DropdownMenuItem(value: m.id, child: Text(m.id)),
                  ],
                  onChanged: _running || _busy
                      ? null
                      : (id) => _persist(_settings.copyWith(
                            modelId: id,
                            effortParamId: null,
                            effortParamValue: null,
                          )),
                ),
              if (effortParam != null) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'effort-${effortParam.id}-${_settings.effortParamValue}',
                  ),
                  initialValue: () {
                    final values = [
                      'default',
                      ...effortParam.values,
                    ];
                    final cur = _settings.effortParamValue ?? 'default';
                    return values.contains(cur) ? cur : 'default';
                  }(),
                  decoration: InputDecoration(
                    labelText: '思考程度（${effortParam.id}）',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'default',
                      child: Text('默认（不传参）'),
                    ),
                    for (final v in effortParam.values)
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: _running || _busy
                      ? null
                      : (v) => _persist(_settings.copyWith(
                            effortParamId: effortParam.id,
                            effortParamValue: v,
                          )),
                ),
              ],
              const SizedBox(height: 12),
              Text('卡片上限', style: Theme.of(context).textTheme.labelLarge),
              Row(
                children: [
                  FilterChip(
                    label: const Text('Max'),
                    selected: _settings.cardLimitMax,
                    onSelected: _running || _busy
                        ? null
                        : (v) => _persist(_settings.copyWith(cardLimitMax: v)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _countController,
                      enabled: !_running && !_busy && !_settings.cardLimitMax,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '张数',
                        hintText: '例如 1',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Skill', style: Theme.of(context).textTheme.labelLarge),
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
              Text('运行日志', style: Theme.of(context).textTheme.labelLarge),
              SizedBox(
                height: 140,
                child: TextField(
                  controller: _logController,
                  readOnly: true,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
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
