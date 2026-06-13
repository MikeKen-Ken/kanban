import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import '../../settings/settings_section.dart';
import 'project_settings.dart';

/// 当前项目的设置页（设置项会同步到 WebDAV）
class ProjectSettingsScreen extends StatefulWidget {
  const ProjectSettingsScreen({super.key});

  @override
  State<ProjectSettingsScreen> createState() => _ProjectSettingsScreenState();
}

class _ProjectSettingsScreenState extends State<ProjectSettingsScreen> {
  late final TextEditingController _doneColumnController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<BoardController>().projectSettings;
    _doneColumnController =
        TextEditingController(text: settings.doneColumnName);
  }

  @override
  void dispose() {
    _doneColumnController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _doneColumnController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已完成列名称不能为空')),
      );
      return;
    }

    setState(() => _saving = true);
    final controller = context.read<BoardController>();
    await controller.saveProjectSettings(
      controller.projectSettings.copyWith(doneColumnName: name),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('项目设置已保存，将自动同步')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projectTitle =
        context.watch<BoardController>().activeProject?.title ?? '项目';

    return Scaffold(
      appBar: AppBar(title: Text('$projectTitle 设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SettingsSection(
            icon: Icons.view_kanban_outlined,
            title: '看板',
            subtitle: '此页面的设置属于当前项目，会通过 WebDAV 在多设备间同步',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextFormField(
                  controller: _doneColumnController,
                  decoration: const InputDecoration(
                    labelText: '已完成列名称',
                    hintText: ProjectSettings.defaultDoneColumnName,
                    border: OutlineInputBorder(),
                    isDense: true,
                    helperText: '勾选完成或拖入该列时，卡片会移入此列。修改后会同步重命名对应列。',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_sync_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '保存后设置会写入当前项目数据，并在下次同步时上传到 WebDAV。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
