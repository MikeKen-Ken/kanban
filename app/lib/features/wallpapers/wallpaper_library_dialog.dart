import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/app_snack_bar.dart';
import '../../controllers/board_controller.dart';
import '../../webdav_sync/sync_actions_sheet.dart';
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
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    if (seconds < 86400) return '${seconds ~/ 3600}h';
    return '1d';
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
        title: const Text('Delete wallpapers'),
        content: Text(
          'Delete ${_deleteSelection.length} selected wallpaper(s)? References in all projects will also be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
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
          title: Text(_deleteMode
              ? 'Select wallpapers to delete'
              : 'Wallpaper library'),
          actions: [
            if (_deleteMode) ...[
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _deleteMode = false;
                          _deleteSelection.clear();
                        }),
                child: const Text('Cancel'),
              ),
              IconButton(
                tooltip: 'Delete selected',
                onPressed:
                    _busy || _deleteSelection.isEmpty ? null : _deleteSelected,
                icon: const Icon(Icons.delete_outline),
              ),
            ] else ...[
              IconButton(
                tooltip: 'Upload wallpaper library to cloud',
                onPressed: _busy
                    ? null
                    : () => runSyncManualAction(
                          context,
                          context.read<BoardController>(),
                          SyncManualAction.uploadWallpapers,
                        ),
                icon: const Icon(Icons.cloud_upload_outlined),
              ),
              IconButton(
                tooltip: 'Download wallpaper library from cloud',
                onPressed: _busy
                    ? null
                    : () => runSyncManualAction(
                          context,
                          context.read<BoardController>(),
                          SyncManualAction.downloadWallpapers,
                        ),
                icon: const Icon(Icons.cloud_download_outlined),
              ),
              IconButton(
                tooltip: 'Bulk delete',
                onPressed: _busy || wallpapers.isEmpty
                    ? null
                    : () => setState(() => _deleteMode = true),
                icon: const Icon(Icons.checklist_rtl_outlined),
              ),
              TextButton(
                  onPressed: _busy ? null : _save, child: const Text('Apply')),
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
                                label: Text('Fixed'),
                                icon: Icon(Icons.push_pin_outlined),
                              ),
                              ButtonSegment(
                                value: WallpaperPlaybackMode.random,
                                label: Text('Random rotation'),
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
                          label: const Text('Upload'),
                        ),
                      ],
                    ),
                    if (_mode == WallpaperPlaybackMode.random) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Switch interval'),
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
                          const Text('Rotate all wallpapers'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: wallpapers.isEmpty
                  ? const Center(
                      child: Text(
                          'No wallpapers yet. Click “Upload” to add images.'))
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
                        final showSelection =
                            _deleteMode || _mode == WallpaperPlaybackMode.fixed;
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
