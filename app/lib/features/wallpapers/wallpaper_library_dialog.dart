import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../project/project_settings.dart';
import 'wallpaper_image.dart';
import 'wallpaper_models.dart';

class WallpaperLibraryDialog extends StatefulWidget {
  const WallpaperLibraryDialog({super.key});

  @override
  State<WallpaperLibraryDialog> createState() => _WallpaperLibraryDialogState();
}

class _WallpaperLibraryDialogState extends State<WallpaperLibraryDialog> {
  late Set<String> _selected;
  late WallpaperPlaybackMode _mode;
  late int _intervalSeconds;
  final Set<String> _deleteSelection = {};
  bool _deleteMode = false;
  bool _busy = false;

  static const _intervals = <int>[10, 30, 60, 300, 900, 3600, 86400];

  @override
  void initState() {
    super.initState();
    final controller = context.read<BoardController>();
    final settings = controller.projectSettings;
    final allIds = controller.wallpapers.map((item) => item.id).toSet();
    _selected = settings.wallpaperIds.toSet();
    if (_selected.isEmpty && allIds.isNotEmpty) {
      _selected = allIds;
    }
    _mode = settings.wallpaperPlaybackMode;
    _intervalSeconds = _intervals.contains(settings.wallpaperIntervalSeconds)
        ? settings.wallpaperIntervalSeconds
        : ProjectSettings.defaultWallpaperIntervalSeconds;
  }

  String _intervalLabel(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    if (seconds < 3600) return '${seconds ~/ 60} 分钟';
    if (seconds < 86400) return '${seconds ~/ 3600} 小时';
    return '1 天';
  }

  Future<void> _upload() async {
    setState(() => _busy = true);
    final error =
        await context.read<BoardController>().uploadWallpapersFromGallery();
    if (!mounted) return;
    final controller = context.read<BoardController>();
    setState(() {
      _busy = false;
      _selected = controller.projectSettings.wallpaperIds.toSet();
      if (_selected.isEmpty && controller.wallpapers.isNotEmpty) {
        _selected = controller.wallpapers.map((item) => item.id).toSet();
      }
    });
    if (error != null) showAppSnackBar(context, message: error);
  }

  Future<void> _deleteSelected() async {
    if (_deleteSelection.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除壁纸'),
        content: Text(
          '确定删除选中的 ${_deleteSelection.length} 张壁纸吗？所有项目中的对应引用也会移除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await context.read<BoardController>().deleteWallpapers(_deleteSelection);
    if (!mounted) return;
    setState(() {
      _selected.removeAll(_deleteSelection);
      _deleteSelection.clear();
      _deleteMode = false;
      _busy = false;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final controller = context.read<BoardController>();
    final wallpaperIds = _mode == WallpaperPlaybackMode.random
        ? controller.wallpapers.map((item) => item.id).toList(growable: false)
        : _selected.toList(growable: false);
    await controller.setProjectWallpapers(
      wallpaperIds: wallpaperIds,
      mode: _mode,
      intervalSeconds: _intervalSeconds,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BoardController>();
    final wallpapers = controller.wallpapers;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          title: Text(_deleteMode ? '选择要删除的壁纸' : '壁纸库'),
          actions: [
            if (_deleteMode) ...[
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _deleteMode = false;
                          _deleteSelection.clear();
                        }),
                child: const Text('取消'),
              ),
              IconButton(
                tooltip: '删除所选',
                onPressed:
                    _busy || _deleteSelection.isEmpty ? null : _deleteSelected,
                icon: const Icon(Icons.delete_outline),
              ),
            ] else ...[
              IconButton(
                tooltip: '批量删除',
                onPressed: _busy || wallpapers.isEmpty
                    ? null
                    : () => setState(() => _deleteMode = true),
                icon: const Icon(Icons.checklist_rtl_outlined),
              ),
              TextButton(
                  onPressed: _busy ? null : _save, child: const Text('应用')),
            ],
          ],
        ),
        body: Column(
          children: [
            if (!_deleteMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<WallpaperPlaybackMode>(
                            segments: const [
                              ButtonSegment(
                                value: WallpaperPlaybackMode.fixed,
                                label: Text('固定'),
                                icon: Icon(Icons.push_pin_outlined),
                              ),
                              ButtonSegment(
                                value: WallpaperPlaybackMode.random,
                                label: Text('随机轮播'),
                                icon: Icon(Icons.shuffle),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (value) {
                              setState(() => _mode = value.first);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _upload,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('上传'),
                        ),
                      ],
                    ),
                    if (_mode == WallpaperPlaybackMode.random) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('切换间隔'),
                          const SizedBox(width: 12),
                          DropdownButton<int>(
                            value: _intervalSeconds,
                            items: [
                              for (final value in _intervals)
                                DropdownMenuItem(
                                  value: value,
                                  child: Text(_intervalLabel(value)),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(
                                      () => _intervalSeconds = value!,
                                    ),
                          ),
                          const Spacer(),
                          const Text('轮播全部壁纸'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: wallpapers.isEmpty
                  ? const Center(child: Text('还没有壁纸，点击“上传”添加图片'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 260,
                        childAspectRatio: 16 / 10,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: wallpapers.length,
                      itemBuilder: (context, index) {
                        final asset = wallpapers[index];
                        final showSelection = _deleteMode ||
                            _mode == WallpaperPlaybackMode.fixed;
                        final checked = _deleteMode
                            ? _deleteSelection.contains(asset.id)
                            : _selected.contains(asset.id);
                        return InkWell(
                          onTap: _busy || !showSelection
                              ? null
                              : () => setState(() {
                                    if (_deleteMode) {
                                      _deleteSelection.contains(asset.id)
                                          ? _deleteSelection.remove(asset.id)
                                          : _deleteSelection.add(asset.id);
                                    } else {
                                      _selected
                                        ..clear()
                                        ..add(asset.id);
                                    }
                                  }),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: WallpaperImage(wallpaperId: asset.id),
                              ),
                              if (showSelection)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: checked
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.black54,
                                    child: Icon(
                                      checked
                                          ? Icons.check
                                          : Icons.circle_outlined,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: Text(
                                  asset.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    shadows: [Shadow(blurRadius: 4)],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
