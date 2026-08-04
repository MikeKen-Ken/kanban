/// 语义化版本比较（仅 major.minor.patch，忽略预发布与 build）。
class VersionCompare {
  VersionCompare._();

  /// 从 `v1.2.3` / `1.2.3+4` / `1.2.3-beta` 取出可比较的三段数字。
  static List<int> parse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    final dash = s.indexOf('-');
    if (dash >= 0) s = s.substring(0, dash);
    final parts = s.split('.');
    final numbers = <int>[];
    for (var i = 0; i < 3; i++) {
      if (i < parts.length) {
        numbers.add(int.tryParse(parts[i]) ?? 0);
      } else {
        numbers.add(0);
      }
    }
    return numbers;
  }

  /// 返回负/零/正，语义同 [Comparable.compareTo]。
  static int compare(String a, String b) {
    final left = parse(a);
    final right = parse(b);
    for (var i = 0; i < 3; i++) {
      final c = left[i].compareTo(right[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  static bool isNewer(String remote, String local) => compare(remote, local) > 0;
}
