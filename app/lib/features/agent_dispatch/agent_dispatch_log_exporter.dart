import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

String agentDispatchLogExportFileName(DateTime now) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return 'agent-dispatch-${now.year}${twoDigits(now.month)}${twoDigits(now.day)}'
      '-${twoDigits(now.hour)}${twoDigits(now.minute)}${twoDigits(now.second)}.txt';
}

/// 将当前本机记录另存为 UTF-8 文本；不会写入备份或 WebDAV。
Future<bool> exportAgentDispatchLog(String log, {DateTime? now}) async {
  final path = await FilePicker.saveFile(
    dialogTitle: 'Export Agent Dispatch log',
    fileName: agentDispatchLogExportFileName(now ?? DateTime.now()),
    type: FileType.custom,
    allowedExtensions: const ['txt'],
    bytes: Uint8List.fromList(utf8.encode(log)),
  );
  return path != null;
}
