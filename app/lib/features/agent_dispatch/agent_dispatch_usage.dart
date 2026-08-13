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

  factory AgentDispatchUsageSnapshot.fromJson(Map<String, dynamic> json) {
    return AgentDispatchUsageSnapshot(
      userEmail: json['userEmail'] as String?,
      apiKeyName: json['apiKeyName'] as String?,
      autoRemainingPercent: (json['autoRemainingPercent'] as num?)?.toDouble(),
      apiRemainingPercent: (json['apiRemainingPercent'] as num?)?.toDouble(),
      message: json['message'] as String?,
    );
  }
}
