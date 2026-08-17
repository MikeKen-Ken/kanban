import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/remote_actions/remote_actions_url.dart';

void main() {
  test('GitHub HTTPS 远端打开 Actions 列表', () {
    expect(
      remoteActionsUri('https://github.com/owner/repo.git'),
      Uri.parse('https://github.com/owner/repo/actions'),
    );
  });

  test('GitHub SSH 远端打开 Actions 列表', () {
    expect(
      remoteActionsUri('git@github.com:owner/repo.git'),
      Uri.parse('https://github.com/owner/repo/actions'),
    );
  });

  test('ssh 协议远端打开 Actions 列表', () {
    expect(
      remoteActionsUri('ssh://git@github.com/owner/repo.git'),
      Uri.parse('https://github.com/owner/repo/actions'),
    );
  });

  test('GitLab 远端打开流水线列表', () {
    expect(
      remoteActionsUri('git@gitlab.com:group/sub/repo.git'),
      Uri.parse('https://gitlab.com/group/sub/repo/-/pipelines'),
    );
  });

  test('无法识别的地址返回空', () {
    expect(remoteActionsUri(''), isNull);
    expect(remoteActionsUri('C:\\Users\\repo'), isNull);
    expect(remoteActionsUri('https://github.com/only-owner'), isNull);
  });
}
