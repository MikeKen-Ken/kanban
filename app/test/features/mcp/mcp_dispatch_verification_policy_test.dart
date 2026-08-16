import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_pending_store.dart';
import 'package:kanban/features/mcp/dispatch/dispatch_verification_policy.dart';

void main() {
  test('允许针对具体测试文件的 flutter test', () {
    expect(
      dispatchVerificationPolicyError(
        const DispatchVerificationCommand(
          executable: 'flutter',
          args: ['test', 'test/features/foo_test.dart'],
        ),
      ),
      isNull,
    );
  });

  test('拒绝全仓库 flutter analyze 与全量 test', () {
    expect(
      dispatchVerificationPolicyError(
        const DispatchVerificationCommand(
          executable: 'flutter',
          args: ['analyze'],
        ),
      ),
      contains('禁止全仓库'),
    );
    expect(
      dispatchVerificationPolicyError(
        const DispatchVerificationCommand(
          executable: 'flutter.exe',
          args: ['analyze', '--no-fatal-infos'],
        ),
      ),
      contains('禁止全仓库'),
    );
    expect(
      dispatchVerificationPolicyError(
        const DispatchVerificationCommand(
          executable: 'flutter',
          args: ['test'],
        ),
      ),
      contains('禁止全量'),
    );
  });

  test('拒绝构建、安装和启动应用', () {
    expect(
      dispatchVerificationPolicyError(
        const DispatchVerificationCommand(
          executable: 'flutter',
          args: ['build', 'windows'],
        ),
      ),
      contains('禁止构建'),
    );
  });

  test('允许带路径的 analyze', () {
    expect(
      dispatchVerificationPolicyError(
        const DispatchVerificationCommand(
          executable: 'dart',
          args: ['analyze', 'lib/features/foo.dart'],
        ),
      ),
      isNull,
    );
  });
}
