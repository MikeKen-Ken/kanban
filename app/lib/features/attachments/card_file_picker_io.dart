import 'package:file_picker/file_picker.dart';

import 'native_file_dialog.dart';
import 'picked_file_bytes.dart';

Future<List<PickedFileBytes>> pickCardFiles() async {
  await yieldBeforeNativeFileDialog();
  final result = await FilePicker.pickFiles(
    dialogTitle: '选择要添加的文件',
    allowMultiple: true,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return const [];

  final results = <PickedFileBytes>[];
  for (final file in result.files) {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) continue;
    results.add(
      PickedFileBytes(
        bytes: bytes,
        fileName: file.name.isNotEmpty ? file.name : 'file.bin',
      ),
    );
  }
  return results;
}
