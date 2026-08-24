import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/templates/card_template.dart';
import 'package:kanban/features/templates/create_card_choice.dart';
import 'package:kanban/features/templates/create_card_choice_sheet.dart';

void main() {
  group('CreateCardChoice', () {
    test('空白选择不带模板 id', () {
      const choice = CreateCardChoice.blank();
      expect(choice.isBlank, isTrue);
      expect(choice.templateId, isNull);
    });

    test('模板选择携带 id', () {
      const choice = CreateCardChoice.fromTemplate('t1');
      expect(choice.isBlank, isFalse);
      expect(choice.templateId, 't1');
    });
  });

  group('removeCardTemplateById', () {
    CardTemplate template(String id, String name) => CardTemplate(
          id: id,
          name: name,
          title: name,
          updatedAt: 1,
        );

    test('移除存在的模板并保持其余顺序', () {
      final templates = [
        template('a', '甲'),
        template('b', '乙'),
        template('c', '丙'),
      ];
      final next = removeCardTemplateById(templates, 'b');
      expect(next.map((item) => item.id), ['a', 'c']);
    });

    test('id 不存在时返回原列表引用', () {
      final templates = [template('a', '甲')];
      expect(
        identical(removeCardTemplateById(templates, 'missing'), templates),
        isTrue,
      );
    });
  });

  group('showCreateCardChoiceSheet', () {
    CardTemplate template(String id, String name) => CardTemplate(
          id: id,
          name: name,
          title: '标题-$name',
          updatedAt: 1,
        );

    testWidgets('默认选中空白，确认后返回空白选择', (tester) async {
      CreateCardChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showCreateCardChoiceSheet(
                    context: context,
                    columnTitle: '待办',
                    templates: [template('t1', '周报')],
                    onDeleteTemplate: (_) async {},
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('Blank card'), findsOneWidget);
      expect(find.text('周报'), findsOneWidget);

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(result?.isBlank, isTrue);
    });

    testWidgets('选中模板后确认返回该模板 id', (tester) async {
      CreateCardChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showCreateCardChoiceSheet(
                    context: context,
                    columnTitle: '待办',
                    templates: [template('t1', '周报')],
                    onDeleteTemplate: (_) async {},
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('周报'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(result?.templateId, 't1');
    });

    testWidgets('确认删除模板后列表更新且可继续创建空白', (tester) async {
      final deleted = <String>[];
      CreateCardChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showCreateCardChoiceSheet(
                    context: context,
                    columnTitle: '待办',
                    templates: [
                      template('t1', '周报'),
                      template('t2', '发布'),
                    ],
                    onDeleteTemplate: (id) async {
                      deleted.add(id);
                    },
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete template').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete template?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(deleted, ['t1']);
      expect(find.text('周报'), findsNothing);
      expect(find.text('发布'), findsOneWidget);

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(result?.isBlank, isTrue);
    });
  });
}
