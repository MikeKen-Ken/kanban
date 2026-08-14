import 'package:crypto/crypto.dart' as crypto;

/// live 压缩包的完成标记（固定文件名，上传覆盖）。
class LiveArchiveMarker {
  const LiveArchiveMarker({
    required this.id,
    required this.sizeBytes,
    required this.sha256,
    this.createdAt,
  });

  final String id;
  final int sizeBytes;
  final String sha256;
  final String? createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        if (createdAt != null) 'createdAt': createdAt,
      };

  static LiveArchiveMarker? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['id'] as String?;
    final sha = json['sha256'] as String?;
    final size = (json['sizeBytes'] as num?)?.toInt();
    if (id == null || id.isEmpty || sha == null || sha.isEmpty || size == null) {
      return null;
    }
    return LiveArchiveMarker(
      id: id,
      sizeBytes: size,
      sha256: sha,
      createdAt: json['createdAt'] as String?,
    );
  }

  static String hashBytes(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();

  bool matchesBytes(List<int> bytes) =>
      sizeBytes == bytes.length && sha256 == hashBytes(bytes);
}
