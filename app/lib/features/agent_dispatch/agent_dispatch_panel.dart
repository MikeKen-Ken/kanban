import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/board_controller.dart';
import '../../features/import_export/backup_file_picker.dart';
import 'agent_dispatch_config.dart';
import 'agent_dispatch_platform.dart';
import 'agent_dispatch_service.dart';
import 'agent_dispatch_settings.dart';

/// AppBar「新建列」后的 Agent 调度入口（仅桌面）。
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
  AgentDispatchSettings _settings = const AgentDispatchSettings();
  final _repoController = TextEditingController();
  final _modelController = TextEditingController();
  final _maxCardsController = TextEditingController(text: '1');
  final _workerPathController = TextEditingController();
  final _logController = TextEditingController();
  bool _running = false;
  AgentDispatchService? _service;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = prefs.loadAgentDispatchSettings();
    if (!mounted) return;
    setState(() {
      _settings = loaded;
      _repoController.text = loaded.repoPath ?? '';
      _modelController.text = loaded.model ?? '';
      _maxCardsController.text = '${loaded.maxCards}';
      _workerPathController.text = loaded.workerScriptPath ?? '';
    });
  }

  Future<void> _persist(AgentDispatchSettings next) async {
    setState(() => _settings = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.saveAgentDispatchSettings(next);
  }

  void _appendLog(String line) {
    final next = _logController.text.isEmpty
        ? line
        : '${_logController.text}\n$line';
    _logController.text = next;
    _logController.selection = TextSelection.collapsed(offset: next.length);
  }

  Future<void> _pickRepo() async {
    final path = await pickBackupDirectory();
    if (path == null || !mounted) return;
    _repoController.text = path;
    final board = context.read<BoardController>();
    final projectId = _settings.useProject
        ? _settings.projectId
        : board.activeProjectId;
    var next = _settings.copyWith(repoPath: path);
    if (projectId != null) {
      final map = Map<String, String>.from(next.repoPathByProject)
        ..[projectId] = path;
      next = next.copyWith(repoPathByProject: map);
    }
    await _persist(next);
  }

  Future<void> _run() async {
    if (_running) return;
    final board = context.read<BoardController>();
    final maxCards = int.tryParse(_maxCardsController.text.trim()) ?? 1;
    var next = _settings.copyWith(
      repoPath: _repoController.text.trim().isEmpty
          ? null
          : _repoController.text.trim(),
      model: _modelController.text.trim().isEmpty
          ? null
          : _modelController.text.trim(),
      maxCards: maxCards,
      workerScriptPath: _workerPathController.text.trim().isEmpty
          ? null
          : _workerPathController.text.trim(),
    );
    await _persist(next);

    final options = next.toRunOptions(activeProjectId: board.activeProjectId);
    setState(() {
      _running = true;
      _logController.clear();
    });
    _service = AgentDispatchService(board);
    _appendLog('引擎：${options.engine.label}');
    if (options.projectId != null) {
      _appendLog('项目：${options.projectId}');
    }
    if (options.repoPath != null) {
      _appendLog('仓库：${options.repoPath}');
    }
    if (options.model != null) {
      _appendLog('模型：${options.model}');
    }
    _appendLog('思考：${options.effort.label}；最多 ${options.maxCards} 张');

    final result = await _service!.runBatch(
      options: options,
      workerScriptPath: next.workerScriptPath,
      onLog: (line) {
        if (!mounted) return;
        setState(() => _appendLog(line));
      },
    );
    if (!mounted) return;
    setState(() => _running = false);
    _appendLog(
      '结束：处理 ${result.processed}，成功 ${result.succeeded}，失败 ${result.failed}'
      '${result.stoppedReason == null ? '' : '（${result.stoppedReason}）'}',
    );
  }

  void _cancel() {
    _service?.requestCancel();
    _appendLog('正在请求取消…');
  }

  @override
  void dispose() {
    _repoController.dispose();
    _modelController.dispose();
    _maxCardsController.dispose();
    _workerPathController.dispose();
    _logController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = context.watch<BoardController>();
    final projects = board.manifest?.projects ?? const [];

    return AlertDialog(
      title: const Text('Agent 调度'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                onSelectionChanged: _running
                    ? null
                    : (s) => _persist(_settings.copyWith(engine: s.first)),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('指定看板项目'),
                value: _settings.useProject,
                onChanged: _running
                    ? null
                    : (v) => _persist(_settings.copyWith(useProject: v ?? false)),
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
                  onChanged: _running
                      ? null
                      : (id) => _persist(_settings.copyWith(projectId: id)),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('指定代码仓库'),
                value: _settings.useRepo,
                onChanged: _running
                    ? null
                    : (v) => _persist(_settings.copyWith(useRepo: v ?? false)),
              ),
              if (_settings.useRepo)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _repoController,
                        enabled: !_running,
                        decoration: const InputDecoration(
                          labelText: '本机仓库路径',
                          hintText: r'例如 %USERPROFILE%\Projects\foo',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '选择目录',
                      onPressed: _running ? null : _pickRepo,
                      icon: const Icon(Icons.folder_open),
                    ),
                  ],
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('指定模型'),
                value: _settings.useModel,
                onChanged: _running
                    ? null
                    : (v) => _persist(_settings.copyWith(useModel: v ?? false)),
              ),
              if (_settings.useModel)
                TextField(
                  controller: _modelController,
                  enabled: !_running,
                  decoration: const InputDecoration(
                    labelText: '模型 id',
                    hintText: 'composer-2.5 / gpt-5.4-codex 等',
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('指定思考程度'),
                value: _settings.useEffort,
                onChanged: _running
                    ? null
                    : (v) => _persist(_settings.copyWith(useEffort: v ?? false)),
              ),
              if (_settings.useEffort)
                DropdownButtonFormField<AgentDispatchEffort>(
                  key: ValueKey('effort-${_settings.effort.name}'),
                  initialValue: _settings.effort,
                  decoration: const InputDecoration(labelText: '思考程度'),
                  items: [
                    for (final e in AgentDispatchEffort.values)
                      DropdownMenuItem(value: e, child: Text(e.label)),
                  ],
                  onChanged: _running
                      ? null
                      : (e) {
                          if (e != null) {
                            _persist(_settings.copyWith(effort: e));
                          }
                        },
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('连续处理多张'),
                value: _settings.useMultiCard,
                onChanged: _running
                    ? null
                    : (v) =>
                        _persist(_settings.copyWith(useMultiCard: v ?? false)),
              ),
              if (_settings.useMultiCard)
                TextField(
                  controller: _maxCardsController,
                  enabled: !_running,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '最多张数',
                    hintText: '1–50',
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('成功后提交待验证'),
                value: _settings.autoSubmitVerify,
                onChanged: _running
                    ? null
                    : (v) => _persist(
                          _settings.copyWith(autoSubmitVerify: v ?? true),
                        ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('失败后移入阻塞中'),
                value: _settings.autoBlockOnFail,
                onChanged: _running
                    ? null
                    : (v) => _persist(
                          _settings.copyWith(autoBlockOnFail: v ?? true),
                        ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _workerPathController,
                enabled: !_running,
                decoration: const InputDecoration(
                  labelText: 'Worker 脚本（可选）',
                  hintText: r'scripts\agent_dispatch\dist\cli.js',
                ),
              ),
              const SizedBox(height: 12),
              Text('运行日志', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              SizedBox(
                height: 160,
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
            onPressed: _cancel,
            child: const Text('取消运行'),
          ),
        FilledButton.icon(
          onPressed: _running ? null : _run,
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
