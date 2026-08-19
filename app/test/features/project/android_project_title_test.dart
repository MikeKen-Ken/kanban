import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/project/android_project_title.dart';

void main() {
  test('不超过两个字时原样返回', () {
    expect(androidCompactProjectTitle(''), '');
    expect(androidCompactProjectTitle('看'), '看');
    expect(androidCompactProjectTitle('看板'), '看板');
    expect(androidCompactProjectTitle('AB'), 'AB');
  });

  test('超过两个字时保留前两字并加两点', () {
    expect(androidCompactProjectTitle('看板项目'), '看板..');
    expect(androidCompactProjectTitle('很长的项目名字'), '很长..');
    expect(androidCompactProjectTitle('ABC'), 'AB..');
  });
}
