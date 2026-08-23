/// 安卓顶栏项目名：最多五个字符，超出用两点省略。
String androidCompactProjectTitle(String title) {
  final units = title.runes.toList();
  if (units.length <= 5) return title;
  return '${String.fromCharCodes(units.take(5))}..';
}
