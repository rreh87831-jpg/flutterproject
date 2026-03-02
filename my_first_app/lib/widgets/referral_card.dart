import 'package:flutter/material.dart';

import '../models/referral.dart';

class ReferralCard extends StatelessWidget {
  final Referral referral;

  const ReferralCard({super.key, required this.referral});

  Color _getRiskColor(String level) {
    switch (level) {
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

  @override
  Widget build(BuildContext context) {
    final daysRemaining = referral.deadline.difference(DateTime.now()).inDays;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Referral #${referral.referralId}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getRiskColor(referral.overallRiskLevel).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    referral.overallRiskLevel,
                    style: TextStyle(
                      color: _getRiskColor(referral.overallRiskLevel),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Facility: ${referral.facilityType.replaceAll('_', ' ')}'),
            const SizedBox(height: 6),
            Text(
              'Urgency: ${referral.urgency}',
              style: TextStyle(
                fontWeight: referral.urgency == 'IMMEDIATE' ? FontWeight.bold : FontWeight.normal,
                color: referral.urgency == 'IMMEDIATE' ? Colors.red : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Deadline: ${referral.deadline.day}/${referral.deadline.month}/${referral.deadline.year} ($daysRemaining days)',
              style: TextStyle(color: daysRemaining < 0 ? Colors.red : null),
            ),
            if (referral.escalationLevel > 0) ...[
              const Divider(),
              Text(
                'Escalation Level: ${referral.escalationLevel}',
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
