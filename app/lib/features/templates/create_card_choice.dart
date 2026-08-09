import 'card_template.dart';

/// 新建卡片时的选择结果：空白，或指定模板。
class CreateCardChoice {
  const CreateCardChoice._(this.templateId);

  /// 空白卡片（默认项）。
  const CreateCardChoice.blank() : this._(null);

  /// 从已有模板创建。
  const CreateCardChoice.fromTemplate(String id) : this._(id);

  /// 为 `null` 表示空白；非空为模板 id。
  final String? templateId;

  bool get isBlank => templateId == null;
}

/// 从列表中移除指定模板（按 id），不存在时返回原列表引用。
List<CardTemplate> removeCardTemplateById(
  List<CardTemplate> templates,
  String id,
) {
  final next = [
    for (final template in templates)
      if (template.id != id) template,
  ];
  if (next.length == templates.length) return templates;
  return next;
}
