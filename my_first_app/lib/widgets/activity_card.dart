import 'package:flutter/material.dart';

import '../models/activity.dart';

class ActivityCard extends StatelessWidget {
  final Activity activity;
  final String language;
  final VoidCallback onComplete;
  final bool isAww;

  const ActivityCard({
    super.key,
    required this.activity,
    required this.language,
    required this.onComplete,
    this.isAww = false,
  });

  String _frequencyText(String value) {
    switch (value.toUpperCase()) {
      case 'DAILY':
        return 'Do daily';
      case 'WEEKLY':
        return 'Do weekly';
      default:
        return 'One-time';
    }
  }

  @override
  Widget build(BuildContext context) {
    var instruction = activity.instructionsEnglish ?? activity.description;
    if (language == 'telugu' && (activity.instructionsTelugu ?? '').isNotEmpty) {
      instruction = activity.instructionsTelugu!;
    }

    var statusColor = Colors.grey;
    if (activity.status == 'COMPLETED') {
      statusColor = Colors.green;
    } else if (activity.dueDate.isBefore(DateTime.now())) {
      statusColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAww ? Colors.purple.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    activity.domain,
                    style: TextStyle(
                      color: isAww ? Colors.purple : Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activity.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(instruction, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 10),
            Text('${activity.targetRole} • ${_frequencyText(activity.frequency)}'),
            if (activity.progress > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: activity.progress / 100,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  activity.progress >= 100 ? Colors.green : Colors.blue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${activity.progress}% complete',
                style: TextStyle(
                  fontSize: 12,
                  color: activity.progress >= 100 ? Colors.green : Colors.grey.shade700,
                ),
              ),
            ],
            if (activity.status != 'COMPLETED') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onComplete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAww ? Colors.purple : Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isAww ? 'Mark as Monitored' : 'Mark as Completed'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
