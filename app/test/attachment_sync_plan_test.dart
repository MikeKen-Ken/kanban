import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/attachments/attachment_sync_plan.dart';

void main() {
  test('JSON 一致时仍应补传附件', () {
    expect(
      shouldReconcileAttachmentsWhenJsonEquals(
        jsonEquals: true,
        attachmentSyncAvailable: true,
      ),
      isTrue,
    );
    expect(
      shouldReconcileAttachmentsWhenJsonEquals(
        jsonEquals: true,
        attachmentSyncAvailable: false,
      ),
      isFalse,
    );
    expect(
      shouldReconcileAttachmentsWhenJsonEquals(
        jsonEquals: false,
        attachmentSyncAvailable: true,
      ),
      isFalse,
    );
  });

  test('仅本地有、远端无时才上传', () {
    expect(
      shouldUploadAttachmentFile(localExists: true, remoteExists: false),
      isTrue,
    );
    expect(
      shouldUploadAttachmentFile(localExists: true, remoteExists: true),
      isFalse,
    );
    expect(
      shouldUploadAttachmentFile(localExists: false, remoteExists: false),
      isFalse,
    );
    expect(
      shouldUploadAttachmentFile(localExists: false, remoteExists: true),
      isFalse,
    );
  });
}
