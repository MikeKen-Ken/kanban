import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

int _atomicWriteSequence = 0;

/// 判断字节是否像 JSON 对象/数组（排除全 0、空文件、明显二进制）
bool looksLikeJsonBytes(List<int> bytes) {
  if (bytes.isEmpty) return false;
  // note: 全 0 文件曾导致 FormatException（界面显示为方框字符）
  var nonZero = 0;
  for (final b in bytes) {
    if (b != 0) {
      nonZero++;
      if (nonZero > 3) break;
    }
  }
  if (nonZero == 0) return false;

  var i = 0;
  while (i < bytes.length &&
      (bytes[i] == 0x20 ||
          bytes[i] == 0x09 ||
          bytes[i] == 0x0A ||
          bytes[i] == 0x0D)) {
    i++;
  }
  if (i >= bytes.length) return false;
  // UTF-8 BOM
  if (i + 2 < bytes.length &&
      bytes[i] == 0xEF &&
      bytes[i + 1] == 0xBB &&
      bytes[i + 2] == 0xBF) {
    i += 3;
    while (i < bytes.length &&
        (bytes[i] == 0x20 ||
            bytes[i] == 0x09 ||
            bytes[i] == 0x0A ||
            bytes[i] == 0x0D)) {
      i++;
    }
  }
  if (i >= bytes.length) return false;
  final c = bytes[i];
  return c == 0x7B || c == 0x5B; // { or [
}

/// 安全解析本地 JSON 文件；损坏时返回 null
Future<Map<String, dynamic>?> readJsonFile(File file) async {
  final primary = await _readJsonCandidate(file);
  if (primary != null) return primary;

  final backup = File('${file.path}.bak');
  final recovered = await _readJsonCandidate(backup);
  if (recovered == null) return null;

  // 上次替换若在删除/改名窗口中断，恢复最后一个完整版本。
  if (await file.exists()) {
    await file.delete();
  }
  await backup.rename(file.path);
  return recovered;
}

Future<Map<String, dynamic>?> _readJsonCandidate(File file) async {
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  if (!looksLikeJsonBytes(bytes)) return null;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } on FormatException {
    return null;
  }
}

/// 先写临时文件再替换，避免半截写/并发写把内容变成空字节
Future<void> writeJsonFileAtomic(File file, Object data) async {
  final parent = file.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }
  final content = const JsonEncoder.withIndent('  ').convert(data);
  final nonce =
      '${DateTime.now().microsecondsSinceEpoch}.$pid.${_atomicWriteSequence++}';
  final tmp = File('${file.path}.tmp.$nonce');
  final backup = File('${file.path}.bak');
  await tmp.writeAsString(content, flush: true);

  try {
    if (await file.exists()) {
      if (await backup.exists()) {
        await backup.delete();
      }
      await file.rename(backup.path);
    }
    await tmp.rename(file.path);
    if (await backup.exists()) {
      await backup.delete();
    }
  } catch (_) {
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(file.path);
    }
    rethrow;
  } finally {
    if (await tmp.exists()) {
      await tmp.delete();
    }
  }
}

/// 将远端/任意字节解析为 JSON Map；非 JSON 时返回 null
Map<String, dynamic>? tryDecodeJsonBytes(List<int> bytes, {String? path}) {
  if (!looksLikeJsonBytes(bytes)) return null;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } on FormatException {
    return null;
  }
}

String describeNonJsonPayload(List<int> bytes, {String? path}) {
  final prefix = path == null ? '' : '$path ';
  if (bytes.isEmpty) return '$prefix内容为空';
  final allZero = bytes.every((b) => b == 0);
  if (allZero) return '$prefix文件已损坏（全空字节）';
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return '$prefix收到的是图片二进制而非 JSON';
  }
  if (bytes.isNotEmpty && (bytes[0] == 0x3C || bytes[0] == 0x7B)) {
    // < or { — { should have been accepted; < is HTML/XML
    if (bytes[0] == 0x3C) return '$prefix收到的是 HTML/XML 而非 JSON';
  }
  return '$prefix不是有效的 JSON（${bytes.length} 字节）';
}

/// 便于测试：检测 Uint8List
bool looksLikeJsonUint8List(Uint8List bytes) => looksLikeJsonBytes(bytes);
