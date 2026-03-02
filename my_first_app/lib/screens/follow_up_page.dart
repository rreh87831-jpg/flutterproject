import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/referral.dart';
import '../screens/improvement_report_page.dart';
import '../services/referral_flow_api_service.dart';
import '../widgets/activity_card.dart';
import '../widgets/progress_bar.dart';
import '../widgets/referral_card.dart';
import '../widgets/timeline_card.dart';

class FollowUpPage extends StatefulWidget {
  final int referralId;

  const FollowUpPage({super.key, required this.referralId});

  @override
  State<FollowUpPage> createState() => _FollowUpPageState();
}

class _FollowUpPageState extends State<FollowUpPage> {
  bool _isLoading = true;
  Referral? _referral;
  List<Activity> _caregiverActivities = <Activity>[];
  List<Activity> _awwActivities = <Activity>[];
  final Map<int, bool> _caregiverNoSelections = <int, bool>{};
  Map<String, dynamic>? _progress;
  Map<String, dynamic>? _timeline;
  String _selectedLanguage = 'telugu';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final referral = await ReferralFlowApiService.getReferral(widget.referralId);
      final activities = await ReferralFlowApiService.getReferralActivities(widget.referralId);
      final progress = await ReferralFlowApiService.getReferralProgress(widget.referralId);
      final timeline = await ReferralFlowApiService.getReferralTimeline(widget.referralId);

      setState(() {
        _referral = referral;
        _caregiverActivities = activities.where((a) => a.targetRole == 'CAREGIVER').toList();
        _awwActivities = activities.where((a) => a.targetRole == 'AWW').toList();
        _progress = progress;
        _timeline = timeline;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading follow-up data: $e')),
      );
    }
  }

  Future<void> _completeActivity(Activity activity) async {
    try {
      await ReferralFlowApiService.completeActivity(
        activity.id,
        reportedBy: activity.targetRole == 'AWW' ? 'AWW' : 'CAREGIVER',
      );
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activity marked complete'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete activity: $e')),
      );
    }
  }

  bool _isActivityCompleted(Activity activity) {
    return activity.status.toUpperCase() == 'COMPLETED' || activity.progress >= 100;
  }

  String _caregiverTaskLabel(Activity activity) {
    final telugu = activity.instructionsTelugu?.trim() ?? '';
    if (_selectedLanguage == 'telugu' && telugu.isNotEmpty) {
      return telugu;
    }
    return activity.title;
  }

  Future<void> _markCaregiverYes(Activity activity, bool? checked) async {
    if (checked != true || _isActivityCompleted(activity)) return;
    await _completeActivity(activity);
  }

  void _markCaregiverNo(Activity activity, bool? checked) {
    if (_isActivityCompleted(activity)) return;
    setState(() {
      _caregiverNoSelections[activity.id] = checked ?? false;
    });
  }

  void _viewImprovementReport() {
    final referral = _referral;
    if (referral == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImprovementReportPage(
          childId: referral.childId,
          referralId: widget.referralId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow-Up Plan'),
        backgroundColor: const Color(0xFF0D5BA7),
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.language),
            onSelected: (value) => setState(() => _selectedLanguage = value),
            itemBuilder: (_) => const [
              PopupMenuItem<String>(value: 'english', child: Text('English')),
              PopupMenuItem<String>(value: 'telugu', child: Text('తెలుగు')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_referral != null) ReferralCard(referral: _referral!),
              const SizedBox(height: 16),
              if (_timeline != null) ...[
                TimelineCard(timeline: _timeline!),
                const SizedBox(height: 16),
              ],
              if (_progress != null) ...[
                const Text('Overall Progress', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 8),
                ProgressBar(
                  percentage: ((_progress!['percentage'] ?? 0) as num).toInt(),
                  total: ((_progress!['total'] ?? 0) as num).toInt(),
                  completed: ((_progress!['completed'] ?? 0) as num).toInt(),
                ),
                const SizedBox(height: 18),
              ],
              if (_caregiverActivities.isNotEmpty) ...[
                const Text('Caregiver Activities', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Assigned Task')),
                      DataColumn(label: Text('Yes')),
                      DataColumn(label: Text('No')),
                    ],
                    rows: _caregiverActivities.map((activity) {
                      final completed = _isActivityCompleted(activity);
                      final noSelected = !completed && (_caregiverNoSelections[activity.id] ?? false);
                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 460,
                              child: Text(_caregiverTaskLabel(activity)),
                            ),
                          ),
                          DataCell(
                            Checkbox(
                              value: completed,
                              onChanged: completed ? null : (v) => _markCaregiverYes(activity, v),
                            ),
                          ),
                          DataCell(
                            Checkbox(
                              value: noSelected,
                              onChanged: completed ? null : (v) => _markCaregiverNo(activity, v),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_awwActivities.isNotEmpty) ...[
                const Text('AWW Monitoring Activities', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 8),
                ..._awwActivities.map(
                  (a) => ActivityCard(
                    activity: a,
                    language: _selectedLanguage,
                    onComplete: () => _completeActivity(a),
                    isAww: true,
                  ),
                ),
              ],
              if (_referral != null && _referral!.escalationLevel > 0) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Escalation Level: ${_referral!.escalationLevel}',
                    style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_progress != null && ((_progress!['percentage'] ?? 0) as num).toInt() == 100) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _viewImprovementReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.emoji_events),
                    label: const Text(
                      'View Improvement Report',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ] else ...[
                Center(
                  child: TextButton(
                    onPressed: _viewImprovementReport,
                    child: const Text('View Current Progress Report'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
