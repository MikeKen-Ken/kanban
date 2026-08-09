import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> saveBackupFile(Uint8List bytes, String fileName) async {
  final path = await FilePicker.saveFile(
    dialogTitle: '导出看板完整备份',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['kanban-backup'],
    bytes: bytes,
  );
  return path != null;
}

Future<Uint8List?> pickBackupFile() async {
  final result = await FilePicker.pickFiles(
    dialogTitle: '选择看板完整备份',
    type: FileType.custom,
    allowedExtensions: const ['kanban-backup', 'zip'],
    withData: true,
  );
  return result?.files.single.bytes;
}

Future<String?> pickBackupDirectory() => FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择自动备份文件夹',
    );
