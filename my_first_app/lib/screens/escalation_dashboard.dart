import 'package:flutter/material.dart';

import '../services/referral_flow_api_service.dart';

class EscalationDashboard extends StatefulWidget {
  const EscalationDashboard({super.key});

  @override
  State<EscalationDashboard> createState() => _EscalationDashboardState();
}

class _EscalationDashboardState extends State<EscalationDashboard> {
  bool _isLoading = true;
  List<dynamic> _escalatedReferrals = <dynamic>[];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final rows = await ReferralFlowApiService.getEscalatedReferrals(limit: 200);
      setState(() {
        _escalatedReferrals = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load escalations: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escalation Dashboard'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _escalatedReferrals.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.check_circle, size: 64, color: Colors.green),
                      SizedBox(height: 12),
                      Text('No escalations pending'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _escalatedReferrals.length,
                  itemBuilder: (context, index) {
                    final ref = Map<String, dynamic>.from(_escalatedReferrals[index] as Map);
                    return Card(
                      color: Colors.red.shade50,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          child: Text('${index + 1}'),
                        ),
                        title: Text('Referral #${ref['referral_code'] ?? ref['referral_id']}'),
                        subtitle: Text(
                          'Escalated to: ${ref['escalated_to'] ?? 'N/A'}\nReason: ${ref['escalation_reason'] ?? ''}',
                        ),
                        trailing: const Icon(Icons.warning, color: Colors.red),
                      ),
                    );
                  },
                ),
    );
  }
}
