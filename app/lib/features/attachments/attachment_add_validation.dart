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
        label: 'Limit reached',
        reason:
            'Each card supports up to $maxCount files. Remove one before adding more.',
        canForceSubmit: false,
      ),
    );
    return AttachmentAddAnalysis(issues: issues);
  }

  if (picked.length > remaining) {
    issues.add(
      AttachmentAddIssue(
        label: 'Too many selected',
        reason:
            'You selected ${picked.length}; only $remaining more can be added.',
        canForceSubmit: true,
      ),
    );
  }

  for (final file in picked) {
    if (file.bytes.isEmpty) {
      issues.add(
        AttachmentAddIssue(
          label: file.fileName,
          reason: 'The file is empty and cannot be added.',
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
              'Size ${formatAttachmentByteSize(file.bytes.length)} exceeds the ${maxCardFileMegabytes()} MB file limit.',
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
        label: 'Limit reached',
        reason:
            'Each card supports up to $maxCount images. Remove one before adding more.',
        canForceSubmit: false,
      ),
    );
    return AttachmentAddAnalysis(issues: issues);
  }

  if (picked.length > remaining) {
    issues.add(
      AttachmentAddIssue(
        label: 'Too many selected',
        reason:
            'You selected ${picked.length}; only $remaining more can be added.',
        canForceSubmit: true,
      ),
    );
  }

  for (final image in picked) {
    if (image.bytes.isEmpty) {
      issues.add(
        AttachmentAddIssue(
          label: image.fileName,
          reason: 'The image is empty and cannot be added.',
          canForceSubmit: false,
        ),
      );
      continue;
    }
    if (processAttachmentImage(image.bytes) == null) {
      issues.add(
        AttachmentAddIssue(
          label: image.fileName,
          reason: 'This is not a valid image.',
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
              'The original image is large (${formatAttachmentByteSize(image.bytes.length)}); processing and sync may be slower.',
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
    if (issue.label == 'Too many selected') {
      reasons.add('Only items within the card limit will be added');
    } else if (issue.reason.contains('file limit')) {
      reasons.add(
          'Large files may slow sync, fail to upload, or use more storage');
    } else if (issue.reason.contains('processing and sync')) {
      reasons.add('Large images may take longer to process and sync');
    }
  }
  if (reasons.isEmpty) {
    return 'These attachments exceed the recommended limits and may affect performance or sync. Add anyway?';
  }
  return '${reasons.join(' ')} Add anyway?';
}
