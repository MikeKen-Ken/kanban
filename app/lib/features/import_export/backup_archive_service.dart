import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../sync_conflict/workspace_snapshot.dart';
import '../trash/trash_models.dart';

class BackupPackage {
  const BackupPackage({
    required this.workspace,
    this.attachments = const {},
    this.labelTrash = const [],
  });

  final ProjectWorkspaceSnapshot workspace;

  /// 相对路径到附件字节，路径格式为 attachments/{projectId}/{fileName}
  final Map<String, Uint8List> attachments;
  final List<TrashItem> labelTrash;
}

class BackupArchiveService {
  const BackupArchiveService();

  static const formatVersion = 2;
  static const _workspacePath = 'workspace.json';
  static const _labelTrashPath = 'label_trash.json';
  static const _manifestPath = 'backup_manifest.json';

  Uint8List encode(BackupPackage package, {DateTime? createdAt}) {
    final archive = Archive();
    final workspaceBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(package.workspace.toJson())),
    );
    archive.addFile(ArchiveFile.bytes(_workspacePath, workspaceBytes));

    final checksums = <String, String>{
      _workspacePath: sha256.convert(workspaceBytes).toString(),
    };
    final labelTrashBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'items': package.labelTrash.map((item) => item.toJson()).toList(),
        }),
      ),
    );
    archive.addFile(ArchiveFile.bytes(_labelTrashPath, labelTrashBytes));
    checksums[_labelTrashPath] =
        sha256.convert(labelTrashBytes).toString();
    for (final entry in package.attachments.entries) {
      final path = _safeAttachmentPath(entry.key);
      archive.addFile(ArchiveFile.bytes(path, entry.value));
      checksums[path] = sha256.convert(entry.value).toString();
    }

    final manifestBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': formatVersion,
          'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
          'workspace': _workspacePath,
          'checksums': checksums,
        }),
      ),
    );
    archive.addFile(ArchiveFile.bytes(_manifestPath, manifestBytes));
    return ZipEncoder().encodeBytes(archive);
  }

  BackupPackage decode(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, Uint8List>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final path = _safeArchivePath(file.name);
      final content = file.readBytes();
      if (content != null) files[path] = content;
    }

    final manifestBytes = files[_manifestPath];
    if (manifestBytes == null) {
      throw const FormatException('备份缺少清单文件');
    }
    final manifest =
        jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    final version = manifest['version'] as int?;
    if (version != 1 && version != formatVersion) {
      throw FormatException('不支持的备份版本：${manifest['version']}');
    }
    final checksumsRaw = manifest['checksums'];
    if (checksumsRaw is! Map) {
      throw const FormatException('备份校验信息无效');
    }
    final declaredPaths = <String>{};
    for (final entry in checksumsRaw.entries) {
      final path = _safeArchivePath(entry.key.toString());
      declaredPaths.add(path);
      final content = files[path];
      if (content == null ||
          sha256.convert(content).toString() != entry.value.toString()) {
        throw FormatException('备份文件校验失败：$path');
      }
    }
    final actualPaths = files.keys.where((path) => path != _manifestPath).toSet();
    if (actualPaths.length != declaredPaths.length ||
        !actualPaths.containsAll(declaredPaths)) {
      throw const FormatException('备份包含未声明文件或校验清单不完整');
    }
    if (version == formatVersion &&
        !declaredPaths.contains(_labelTrashPath)) {
      throw const FormatException('备份缺少标签回收站数据');
    }

    final workspaceBytes = files[_workspacePath];
    if (workspaceBytes == null) {
      throw const FormatException('备份缺少工作区数据');
    }
    final workspaceJson =
        jsonDecode(utf8.decode(workspaceBytes)) as Map<String, dynamic>;
    return BackupPackage(
      workspace: ProjectWorkspaceSnapshot.fromJson(workspaceJson),
      labelTrash: version == 1
          ? const []
          : [
              for (final item in ((jsonDecode(
                        utf8.decode(files[_labelTrashPath]!),
                      ) as Map<String, dynamic>)['items'] as List<dynamic>? ??
                  const []))
                TrashItem.fromJson(item as Map<String, dynamic>),
            ],
      attachments: {
        for (final entry in files.entries)
          if (entry.key.startsWith('attachments/')) entry.key: entry.value,
      },
    );
  }

  String _safeAttachmentPath(String path) {
    final safe = _safeArchivePath(path.replaceAll('\\', '/'));
    if (!safe.startsWith('attachments/')) {
      throw const FormatException('附件必须位于 attachments 目录');
    }
    return safe;
  }

  String _safeArchivePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        normalized.split('/').any((segment) => segment == '..')) {
      throw FormatException('备份包含不安全路径：$path');
    }
    return normalized;
  }
}
