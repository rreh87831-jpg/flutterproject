import 'package:flutter/material.dart';

class TimelineCard extends StatelessWidget {
  final Map<String, dynamic> timeline;

  const TimelineCard({super.key, required this.timeline});

  Color _riskColor(String level) {
    switch (level.toUpperCase()) {
      case 'CRITICAL':
        return Colors.red;
      case 'HIGH':
        return Colors.orange;
      case 'MEDIUM':
        return Colors.amber.shade700;
      default:
        return Colors.green;
    }
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '-';
    try {
      final dt = DateTime.parse(value);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return value;
    }
  }

  String _daysRemaining(String? value) {
    if (value == null || value.isEmpty) return '';
    try {
      final dt = DateTime.parse(value);
      final d = dt.difference(DateTime.now()).inDays;
      if (d < 0) return 'Overdue';
      return '$d days remaining';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final referral = Map<String, dynamic>.from(timeline['referral'] as Map? ?? <String, dynamic>{});
    final stats = Map<String, dynamic>.from(timeline['stats'] as Map? ?? <String, dynamic>{});
    final risk = (referral['risk_level'] ?? 'MEDIUM').toString();
    final totalActivities = (stats['total_activities'] ?? 0) as num;
    final completedActivities = (stats['completed_activities'] ?? 0) as num;
    final compliance = (stats['compliance'] ?? 0).toDouble();
    final reviewsCompleted = (stats['reviews_completed'] ?? 0) as num;
    final escalationLevel = (stats['escalation_level'] ?? 0) as num;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Follow-Up Timeline',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _riskColor(risk).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    risk,
                    style: TextStyle(
                      color: _riskColor(risk),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _row('Referral Deadline', _formatDate(referral['deadline']?.toString()), _daysRemaining(referral['deadline']?.toString())),
            const SizedBox(height: 8),
            _row('Follow-Up End', _formatDate(referral['end_date']?.toString()), null),
            const SizedBox(height: 8),
            _row('Review Frequency', (referral['frequency'] ?? '-').toString(), null),
            const SizedBox(height: 14),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('Activities', '$completedActivities/$totalActivities', '${compliance.toStringAsFixed(0)}%'),
                _stat('Reviews', '$reviewsCompleted', null),
                _stat('Escalation', 'Level $escalationLevel', escalationLevel > 0 ? 'Action' : 'OK'),
              ],
            ),
            if (escalationLevel > 0) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Escalation active. Supervisor action required.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, String? sub) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (sub != null && sub.isNotEmpty)
              Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ],
    );
  }

  Widget _stat(String label, String value, String? sub) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        if (sub != null)
          Text(
            sub,
            style: TextStyle(
              fontSize: 12,
              color: sub.contains('%') && double.tryParse(sub.replaceAll('%', '')) != null && double.parse(sub.replaceAll('%', '')) < 40
                  ? Colors.red
                  : Colors.green,
            ),
          ),
      ],
    );
  }
}
