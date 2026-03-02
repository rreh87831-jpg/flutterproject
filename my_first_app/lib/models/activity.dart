class Activity {
  final int id;
  final String activityId;
  final String title;
  final String description;
  final String? instructionsEnglish;
  final String? instructionsTelugu;
  final String domain;
  final String targetRole;
  final String frequency;
  final DateTime dueDate;
  final String status;
  final int progress;

  Activity({
    required this.id,
    required this.activityId,
    required this.title,
    required this.description,
    this.instructionsEnglish,
    this.instructionsTelugu,
    required this.domain,
    required this.targetRole,
    required this.frequency,
    required this.dueDate,
    required this.status,
    required this.progress,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      id: (json['id'] as num).toInt(),
      activityId: (json['activity_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      instructionsEnglish: json['instructions_english']?.toString(),
      instructionsTelugu: json['instructions_telugu']?.toString(),
      domain: (json['domain'] ?? 'GENERAL').toString(),
      targetRole: (json['target_role'] ?? '').toString(),
      frequency: (json['frequency'] ?? 'DAILY').toString(),
      dueDate: DateTime.parse((json['due_date'] ?? json['scheduled_date'] ?? '').toString()),
      status: (json['status'] ?? '').toString(),
      progress: ((json['progress'] ?? 0) as num).toInt(),
    );
  }
}
