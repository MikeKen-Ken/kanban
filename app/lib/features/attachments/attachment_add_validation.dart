import 'attachment_image_processor.dart';
import 'picked_file_bytes.dart';
import 'picked_image_bytes.dart';

/// 建议的图片源文件体积上限（超出会提示，执意提交可绕过）。
const maxRecommendedImageSourceBytes = 20 * 1024 * 1024;

/// 单条不合规说明。
class AttachmentAddIssue {
  const AttachmentAddIssue({
    required this.label,
    required this.reason,
    required this.canForceSubmit,
  });

  /// 文件名或汇总标签（如「选择数量」）。
  final String label;
  final String reason;

  /// 是否允许用户执意提交后仍继续添加。
  final bool canForceSubmit;
}

/// 对一批待添加附件的合规性分析结果。
class AttachmentAddAnalysis {
  const AttachmentAddAnalysis({this.issues = const []});

  final List<AttachmentAddIssue> issues;

  bool get hasIssues => issues.isNotEmpty;

  /// 仅当所有问题均可执意绕过时为 true。
  bool get canForceSubmit =>
      hasIssues && issues.every((issue) => issue.canForceSubmit);
}

String formatAttachmentByteSize(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

int maxCardFileMegabytes() => maxCardFileBytes ~/ (1024 * 1024);

/// 分析待添加的通用文件附件。
AttachmentAddAnalysis analyzeFileAttachmentPicks({
  required List<PickedFileBytes> picked,
  required int currentCount,
  required int maxCount,
}) {
  final issues = <AttachmentAddIssue>[];
  final remaining = maxCount - currentCount;

  if (remaining <= 0) {
    issues.add(
      AttachmentAddIssue(
        label: '数量已满',
        reason: '每张卡片最多 $maxCount 个文件，请先删除后再添加',
        canForceSubmit: false,
      ),
    );
    return AttachmentAddAnalysis(issues: issues);
  }

  if (picked.length > remaining) {
    issues.add(
      AttachmentAddIssue(
        label: '选择数量',
        reason: '已选 ${picked.length} 个，当前最多还能添加 $remaining 个',
        canForceSubmit: true,
      ),
    );
  }

  for (final file in picked) {
    if (file.bytes.isEmpty) {
      issues.add(
        AttachmentAddIssue(
          label: file.fileName,
          reason: '文件内容为空，无法添加',
          canForceSubmit: false,
        ),
      );
      continue;
    }
    if (file.bytes.length > maxCardFileBytes) {
      issues.add(
        AttachmentAddIssue(
          label: file.fileName,
          reason:
              '大小 ${formatAttachmentByteSize(file.bytes.length)}，超过单文件 ${maxCardFileMegabytes()} MB 限制',
          canForceSubmit: true,
        ),
      );
    }
  }

  return AttachmentAddAnalysis(issues: issues);
}

/// 分析待添加的图片附件。
AttachmentAddAnalysis analyzeImageAttachmentPicks({
  required List<PickedImageBytes> picked,
  required int currentCount,
  required int maxCount,
}) {
  final issues = <AttachmentAddIssue>[];
  final remaining = maxCount - currentCount;

  if (remaining <= 0) {
    issues.add(
      AttachmentAddIssue(
        label: '数量已满',
        reason: '每张卡片最多 $maxCount 张图片，请先删除后再添加',
        canForceSubmit: false,
      ),
    );
    return AttachmentAddAnalysis(issues: issues);
  }

  if (picked.length > remaining) {
    issues.add(
      AttachmentAddIssue(
        label: '选择数量',
        reason: '已选 ${picked.length} 张，当前最多还能添加 $remaining 张',
        canForceSubmit: true,
      ),
    );
  }

  for (final image in picked) {
    if (image.bytes.isEmpty) {
      issues.add(
        AttachmentAddIssue(
          label: image.fileName,
          reason: '图片内容为空，无法添加',
          canForceSubmit: false,
        ),
      );
      continue;
    }
    if (processAttachmentImage(image.bytes) == null) {
      issues.add(
        AttachmentAddIssue(
          label: image.fileName,
          reason: '无法识别为有效图片',
          canForceSubmit: false,
        ),
      );
      continue;
    }
    if (image.bytes.length > maxRecommendedImageSourceBytes) {
      issues.add(
        AttachmentAddIssue(
          label: image.fileName,
          reason:
              '原图 ${formatAttachmentByteSize(image.bytes.length)} 较大，处理与同步可能较慢',
          canForceSubmit: true,
        ),
      );
    }
  }

  return AttachmentAddAnalysis(issues: issues);
}

/// 按剩余配额截取待添加列表（数量超额时执意提交仅添加前 [remaining] 项）。
List<T> trimPickedAttachmentsForAdd<T>(
  List<T> picked,
  int remaining,
) {
  if (remaining <= 0) return const [];
  if (picked.length <= remaining) return picked;
  return picked.sublist(0, remaining);
}

/// 执意提交时的二次确认文案。
String forceSubmitConfirmMessage(AttachmentAddAnalysis analysis) {
  final reasons = <String>{};
  for (final issue in analysis.issues) {
    if (issue.label == '选择数量') {
      reasons.add('超出数量的文件将只添加允许范围内的部分');
    } else if (issue.reason.contains('超过单文件')) {
      reasons.add('大文件可能导致同步缓慢、失败或占用更多存储');
    } else if (issue.reason.contains('较大')) {
      reasons.add('大图处理与同步可能较慢');
    }
  }
  if (reasons.isEmpty) {
    return '这些附件不符合推荐限制，继续添加可能影响性能或同步。确定仍要添加吗？';
  }
  return '${reasons.join('；')}。确定仍要添加吗？';
}
