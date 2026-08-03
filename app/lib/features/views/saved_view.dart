import 'filter_spec.dart';

/// 用户命名并可同步的保存视图。
class SavedView {
  const SavedView({
    required this.id,
    required this.name,
    required this.filter,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String id;
  final String name;
  final FilterSpec filter;
  final int createdAt;
  final int updatedAt;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'name': name,
        'filter': filter.toJson(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// 旧数据可将筛选字段直接放在视图根节点，新格式则读取 filter。
  factory SavedView.fromJson(Map<String, dynamic> json) {
    final rawFilter = json['filter'];
    final filterJson =
        rawFilter is Map ? Map<String, dynamic>.from(rawFilter) : json;
    return SavedView(
      id: json['id'] is String ? json['id'] as String : '',
      name: json['name'] is String ? json['name'] as String : '未命名视图',
      filter: FilterSpec.fromJson(filterJson),
      createdAt: _readInt(json['createdAt']),
      updatedAt: _readInt(json['updatedAt']),
    );
  }
}

int _readInt(Object? value) => value is num ? value.toInt() : 0;
