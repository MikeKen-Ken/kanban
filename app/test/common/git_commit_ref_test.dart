import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/common/git_commit_ref.dart';

void main() {
  test('完整哈希收成 7 位小写短哈希', () {
    expect(
      abbreviateGitCommitRef(
        'ABCDEF0123456789abcdef0123456789abcdef01',
      ),
      'abcdef0',
    );
  });

  test('完整 SHA-256 哈希同样收成 7 位', () {
    expect(abbreviateGitCommitRef('a' * 64), 'aaaaaaa');
  });

  test('已是短哈希则只转小写', () {
    expect(abbreviateGitCommitRef('DeadBeef'), 'deadbeef');
  });

  test('非哈希原文保持不变', () {
    expect(abbreviateGitCommitRef('v1.2.3'), 'v1.2.3');
  });
}
