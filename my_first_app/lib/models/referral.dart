class Referral {
  final int id;
  final String referralId;
  final String childId;
  final String overallRiskLevel;
  final String facilityType;
  final String urgency;
  final DateTime deadline;
  final String status;
  final int escalationLevel;

  Referral({
    required this.id,
    required this.referralId,
    required this.childId,
    required this.overallRiskLevel,
    required this.facilityType,
    required this.urgency,
    required this.deadline,
    required this.status,
    required this.escalationLevel,
  });

  factory Referral.fromJson(Map<String, dynamic> json) {
    return Referral(
      id: (json['id'] as num).toInt(),
      referralId: (json['referral_id'] ?? '').toString(),
      childId: (json['child_id'] ?? '').toString(),
      overallRiskLevel: (json['overall_risk_level'] ?? '').toString(),
      facilityType: (json['facility_type'] ?? '').toString(),
      urgency: (json['urgency'] ?? '').toString(),
      deadline: DateTime.parse((json['deadline'] ?? json['referral_deadline'] ?? '').toString()),
      status: (json['status'] ?? '').toString(),
      escalationLevel: ((json['escalation_level'] ?? 0) as num).toInt(),
    );
  }
}
