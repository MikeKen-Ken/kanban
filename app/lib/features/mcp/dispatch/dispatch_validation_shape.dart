import 'dispatch_pending_store.dart';

/// Validate the verification result reported by the Worker.
///
/// Tests run in the Agent session; the Worker only records the result, so the
/// command-result list must be empty.
String? dispatchValidationShapeError({
  required bool isManual,
  required List<DispatchValidationResult> results,
}) {
  if (results.isNotEmpty) {
    return isManual
        ? 'A manual verification declaration must not include command results'
        : 'Verification now runs in the Agent session; the Worker must not report command results';
  }
  return null;
}
