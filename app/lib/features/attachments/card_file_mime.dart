/// 根据文件名推断 MIME 类型。
String mimeTypeForFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot >= fileName.length - 1) {
    return 'application/octet-stream';
  }
  return switch (fileName.substring(dot + 1).toLowerCase()) {
    'txt' => 'text/plain',
    'md' => 'text/markdown',
    'json' => 'application/json',
    'yaml' || 'yml' => 'application/yaml',
    'xml' => 'application/xml',
    'html' || 'htm' => 'text/html',
    'css' => 'text/css',
    'js' => 'text/javascript',
    'ts' => 'text/typescript',
    'dart' => 'text/x-dart',
    'py' => 'text/x-python',
    'sh' => 'text/x-shellscript',
    'bat' || 'cmd' => 'application/x-msdownload',
    'ps1' => 'text/x-powershell',
    'pdf' => 'application/pdf',
    'zip' => 'application/zip',
    'csv' => 'text/csv',
    _ => 'application/octet-stream',
  };
}
