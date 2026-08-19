/// 安卓顶栏项目名：最多两个字，超出用两点省略。
String androidCompactProjectTitle(String title) {
  final units = title.runes.toList();
  if (units.length <= 2) return title;
  return '${String.fromCharCodes(units.take(2))}..';
}
