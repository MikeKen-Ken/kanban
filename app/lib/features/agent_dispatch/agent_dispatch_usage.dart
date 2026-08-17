class AgentDispatchUsageSnapshot {
  const AgentDispatchUsageSnapshot({
    this.userEmail,
    this.apiKeyName,
    this.autoRemainingPercent,
    this.apiRemainingPercent,
    this.message,
  });

  final String? userEmail;
  final String? apiKeyName;
  final double? autoRemainingPercent;
  final double? apiRemainingPercent;
  final String? message;

  bool get hasPoolPercents =>
      autoRemainingPercent != null || apiRemainingPercent != null;

  bool get hasAccountIdentity {
    final email = userEmail?.trim() ?? '';
    final name = apiKeyName?.trim() ?? '';
    return email.isNotEmpty || name.isNotEmpty;
  }

  bool get hasUserEmail => (userEmail?.trim() ?? '').isNotEmpty;

  /// 已保存 Key 下拉优先显示邮箱，没有邮箱时再回退 Key 名。
  String? get displayLabel {
    final email = userEmail?.trim() ?? '';
    if (email.isNotEmpty) return email;
    final name = apiKeyName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return null;
  }

  factory AgentDispatchUsageSnapshot.fromJson(Map<String, dynamic> json) {
    return AgentDispatchUsageSnapshot(
      userEmail: json['userEmail'] as String?,
      apiKeyName: json['apiKeyName'] as String?,
      autoRemainingPercent: (json['autoRemainingPercent'] as num?)?.toDouble(),
      apiRemainingPercent: (json['apiRemainingPercent'] as num?)?.toDouble(),
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (userEmail != null) 'userEmail': userEmail,
        if (apiKeyName != null) 'apiKeyName': apiKeyName,
        if (autoRemainingPercent != null)
          'autoRemainingPercent': autoRemainingPercent,
        if (apiRemainingPercent != null)
          'apiRemainingPercent': apiRemainingPercent,
        if (message != null) 'message': message,
      };
}

/// 切换 Key 下拉优先用账号快照里的邮箱，否则沿用已保存别名。
String cursorApiKeyMenuLabel({
  required String storedLabel,
  AgentDispatchUsageSnapshot? usage,
}) {
  final fromUsage = usage?.displayLabel?.trim() ?? '';
  if (fromUsage.isNotEmpty) return fromUsage;
  return storedLabel;
}
