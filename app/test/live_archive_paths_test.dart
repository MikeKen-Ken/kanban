import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/storage/kanban_paths.dart';
import 'package:kanban/webdav_sync/sync_actions_sheet.dart';

void main() {
  test('live 压缩包使用固定文件名', () {
    const base = '/KanbanApp';
    expect(
      KanbanPaths.remoteLiveWorkspaceArchivePath(base),
      '/KanbanApp/workspace.kanban-backup',
    );
    expect(
      KanbanPaths.remoteLiveWorkspaceMarkerPath(base),
      '/KanbanApp/workspace.complete.json',
    );
    expect(
      KanbanPaths.remoteLiveWallpapersArchivePath(base),
      '/KanbanApp/wallpapers.kanban-backup',
    );
    expect(
      KanbanPaths.remoteLiveWallpapersMarkerPath(base),
      '/KanbanApp/wallpapers.complete.json',
    );
  });

  test('同步菜单包含工作区三项与壁纸库两项', () {
    expect(SyncManualAction.values, [
      SyncManualAction.upload,
      SyncManualAction.download,
      SyncManualAction.merge,
      SyncManualAction.uploadWallpapers,
      SyncManualAction.downloadWallpapers,
    ]);
    expect(SyncManualAction.uploadWallpapers.label, '上传壁纸库');
    expect(SyncManualAction.downloadWallpapers.label, '下载壁纸库');
  });
}
