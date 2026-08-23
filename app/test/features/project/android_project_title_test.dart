import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/project/android_project_title.dart';

void main() {
  test('不超过五个字符时原样返回', () {
    expect(androidCompactProjectTitle(''), '');
    expect(androidCompactProjectTitle('看'), '看');
    expect(androidCompactProjectTitle('看板'), '看板');
    expect(androidCompactProjectTitle('看板项目一'), '看板项目一');
    expect(androidCompactProjectTitle('ABCDE'), 'ABCDE');
  });

  test('超过五个字符时保留前五个字符并加两点', () {
    expect(androidCompactProjectTitle('看板项目一二'), '看板项目一..');
    expect(androidCompactProjectTitle('很长的项目名字测试'), '很长的项目..');
    expect(androidCompactProjectTitle('ABCDEF'), 'ABCDE..');
  });
}
