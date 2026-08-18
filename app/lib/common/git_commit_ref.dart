/// Git 默认短哈希长度（`git rev-parse --short` / `core.abbrev`）。
const gitShortCommitRefLength = 7;

final _gitCommitHashPattern = RegExp(r'^[0-9a-fA-F]{7,64}$');

/// 将完整 Git 提交哈希（SHA-1 40 位 / SHA-256 64 位）收成 7 位小写短哈希。
/// 已经是短哈希或非哈希原文则不截断。
String abbreviateGitCommitRef(String commitRef) {
  final value = commitRef.trim();
  if (!_gitCommitHashPattern.hasMatch(value)) return value;
  final lower = value.toLowerCase();
  if (lower.length != 40 && lower.length != 64) return lower;
  return lower.substring(0, gitShortCommitRefLength);
}
