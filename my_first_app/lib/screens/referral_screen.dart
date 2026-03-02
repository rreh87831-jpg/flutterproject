import 'package:flutter/material.dart';
import 'package:my_first_app/core/localization/app_localizations.dart';
import 'package:my_first_app/models/child_model.dart';
import 'package:my_first_app/models/referral_model.dart';
import 'package:my_first_app/models/screening_model.dart';
import 'package:my_first_app/screens/dashboard_screen.dart';
import 'package:my_first_app/screens/followup_complete_screen.dart';
import 'package:my_first_app/screens/referral_batch_summary_screen.dart';
import 'package:my_first_app/screens/registered_children_screen.dart';
import 'package:my_first_app/screens/result_screen.dart';
import 'package:my_first_app/screens/settings_screen.dart';
import 'package:my_first_app/services/api_service.dart';
import 'package:my_first_app/services/local_db_service.dart';
import 'package:my_first_app/widgets/language_menu_button.dart';

class ReferralScreen extends StatefulWidget {
  final String childId;
  final String awwId;
  final int ageMonths;
  final String overallRisk; // 'low'|'medium'|'high'|'critical'
  final Map<String, double> domainScores;
  final Map<String, String>? domainRiskLevels;

  const ReferralScreen({
    super.key,
    required this.childId,
    required this.awwId,
    required this.ageMonths,
    required this.overallRisk,
    required this.domainScores,
    this.domainRiskLevels,
  });

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _formKey = GlobalKey<FormState>();
  final LocalDBService _localDb = LocalDBService();
  bool submitting = false;

  final List<String> referralTypes = [
    'Physiotherapist',
    'Occupational Therapist',
    'Speech Therapist',
    'Developmental Specialist',
    'Child Psychologist',
    'RBSK',
    'PHC',
  ];
  final List<String> urgencies = ['Normal', 'Urgent', 'Immediate'];
  final List<_DomainRisk> _domainRisks = [];
  final List<_ReferralRecommendation> _recommendations = [];
  final List<_ReferralDraft> _referralDrafts = [];
  List<_DomainRisk> _recommendedDomains = [];

  @override
  void initState() {
    super.initState();
    _initDomainRisks();
    _applyRecommendation();
  }

  @override
  void dispose() {
    for (final draft in _referralDrafts) {
      draft.notesController.dispose();
    }
    super.dispose();
  }

  void _initDomainRisks() {
    _domainRisks.clear();
    final labels = widget.domainRiskLevels ?? {};
    widget.domainScores.forEach((key, value) {
      final riskLabel = labels[key] ?? _riskFromScore(value);
      _domainRisks.add(
        _DomainRisk(
          key: key,
          risk: _formatRisk(riskLabel),
          score: value,
          severity: _riskSeverity(riskLabel),
        ),
      );
    });
    for (final entry in labels.entries) {
      if (_domainRisks.any((d) => d.key == entry.key)) continue;
      _domainRisks.add(
        _DomainRisk(
          key: entry.key,
          risk: _formatRisk(entry.value),
          score: null,
          severity: _riskSeverity(entry.value),
        ),
      );
    }
    _domainRisks.sort((a, b) {
      final bySeverity = b.severity.compareTo(a.severity);
      if (bySeverity != 0) return bySeverity;
      final aScore = a.score ?? 1.0;
      final bScore = b.score ?? 1.0;
      return aScore.compareTo(bScore);
    });
  }

  void _applyRecommendation() {
    // Create separate referrals for every domain risk available.
    final recommendedDomains = _domainRisks.where((d) => d.key.trim().isNotEmpty).toList();

    _recommendations.clear();
    if (recommendedDomains.isNotEmpty) {
      for (final domain in recommendedDomains) {
        final rec = _recommendationForSeverity(domain.severity);
        final referralType = _referralTypeForDomain(domain);
        _recommendations.add(
          _ReferralRecommendation(
            domain: domain,
            referralType: referralType,
            urgency: rec.urgency,
            followUpDate: rec.followUpDate,
          ),
        );
      }
    }

    _recommendedDomains = recommendedDomains;
    _resetDrafts();
  }

  void _openDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  Future<void> _viewRegisteredChildren() async {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RegisteredChildrenScreen(),
      ),
    );
  }

  Future<void> _viewPastResults() async {
    await _localDb.initialize();
    final children = _localDb.getAllChildren();
    final past = <ScreeningModel>[];
    for (final ChildModel c in children) {
      past.addAll(_localDb.getChildScreenings(c.childId));
    }
    past.sort((a, b) => b.screeningDate.compareTo(a.screeningDate));

    if (!mounted) return;
    if (past.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).t('no_past_results'))),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => ListView.builder(
        itemCount: past.length,
        itemBuilder: (context, index) {
          final s = past[index];
          final risk = s.overallRisk.toString().split('.').last;
          return ListTile(
            title: Text('${s.childId} - ${AppLocalizations.of(context).t(risk.toLowerCase()).toUpperCase()}'),
            subtitle: Text(AppLocalizations.of(context).t('date_label', {'date': '${s.screeningDate.toLocal()}'})),
            trailing: const Icon(Icons.open_in_new),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ResultScreen(
                    domainScores: s.domainScores,
                    overallRisk: risk,
                    missedMilestones: s.missedMilestones,
                    explainability: s.explainability,
                    childId: s.childId,
                    awwId: s.awwId,
                    ageMonths: s.ageMonths,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showRiskStatus() async {
    await _localDb.initialize();
    final children = _localDb.getAllChildren();
    final all = <ScreeningModel>[];
    for (final ChildModel c in children) {
      all.addAll(_localDb.getChildScreenings(c.childId));
    }
    final low = all.where((s) => s.overallRisk == RiskLevel.low).length;
    final medium = all.where((s) => s.overallRisk == RiskLevel.medium).length;
    final high = all.where((s) => s.overallRisk == RiskLevel.high).length;
    final critical = all.where((s) => s.overallRisk == RiskLevel.critical).length;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context).t('risk_status')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${AppLocalizations.of(context).t('low')}: $low'),
            Text('${AppLocalizations.of(context).t('medium')}: $medium'),
            Text('${AppLocalizations.of(context).t('high')}: $high'),
            Text('${AppLocalizations.of(context).t('critical')}: $critical'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(AppLocalizations.of(context).t('ok'))),
        ],
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Widget _buildSideNav() {
    return Container(
      width: 220,
      color: const Color(0xFFF5F5F5),
      child: Column(
        children: [
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                ClipOval(
                  child: Image.asset('assets/images/ap_logo.png', width: 36, height: 36, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).t('govt_andhra_pradesh'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: Text(AppLocalizations.of(context).t('dashboard')),
            onTap: _openDashboard,
          ),
          ListTile(
            leading: const Icon(Icons.child_care),
            title: Text(AppLocalizations.of(context).t('children')),
            onTap: _viewRegisteredChildren,
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: Text(AppLocalizations.of(context).t('risk_status')),
            onTap: _showRiskStatus,
          ),
          ListTile(
            leading: const Icon(Icons.show_chart),
            title: Text(AppLocalizations.of(context).t('view_past_results')),
            onTap: _viewPastResults,
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(AppLocalizations.of(context).t('settings')),
            onTap: _openSettings,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  void _resetDrafts() {
    for (final draft in _referralDrafts) {
      draft.notesController.dispose();
    }
    _referralDrafts.clear();
    for (final rec in _recommendations) {
      _referralDrafts.add(
        _ReferralDraft(
          domain: rec.domain,
          referralType: rec.referralType,
          recommendedReferralType: rec.referralType,
          urgency: rec.urgency,
          recommendedUrgency: rec.urgency,
          followUpDate: rec.followUpDate,
          recommendedFollowUpDate: rec.followUpDate,
          notesController: TextEditingController(),
        ),
      );
    }
  }

  _ReferralRecommendation _recommendationForSeverity(int severity) {
    if (severity >= 3) {
      return _ReferralRecommendation(
        domain: null,
        referralType: 'PHC',
        urgency: 'Immediate',
        followUpDate: DateTime.now().add(const Duration(days: 2)),
      );
    }
    if (severity >= 2) {
      return _ReferralRecommendation(
        domain: null,
        referralType: 'RBSK',
        urgency: 'Urgent',
        followUpDate: DateTime.now().add(const Duration(days: 7)),
      );
    }
    return _ReferralRecommendation(
      domain: null,
      referralType: 'RBSK',
      urgency: 'Normal',
      followUpDate: DateTime.now().add(const Duration(days: 14)),
    );
  }

  String _referralTypeForDomain(_DomainRisk domain) {
    switch (domain.key) {
      case 'GM':
        return 'Physiotherapist';
      case 'FM':
        return 'Occupational Therapist';
      case 'LC':
        return 'Speech Therapist';
      case 'COG':
        return 'Developmental Specialist';
      case 'SE':
        return 'Child Psychologist';
      default:
        return 'RBSK';
    }
  }

  Future<void> _pickDate(_ReferralDraft draft) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => draft.followUpDate = picked);
    }
  }

  Future<void> _createReferral({
    _ReferralDraft? selectedDraft,
    bool openFollowUpForCreatedReferral = true,
    bool openReferralListAfterCreate = false,
  }) async {
    if (!_formKey.currentState!.validate() || submitting) return;
    final drafts = selectedDraft == null
        ? List<_ReferralDraft>.from(_referralDrafts)
        : <_ReferralDraft>[selectedDraft];
    if (drafts.isEmpty) return;

    setState(() => submitting = true);
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    String? createdReferralIdForFollowUp;
    try {
      final api = APIService();
      final localDb = LocalDBService();
      await localDb.initialize();
      var index = 0;
      for (final draft in drafts) {
        index += 1;
        final domain = draft.domain;
        final fallbackReferralId = 'ref_${now.microsecondsSinceEpoch}_$index';
        final reasons = domain == null
            ? <String>[]
            : ['${_domainLabel(domain.key, l10n)} (${_riskLabel(domain.risk, l10n)})'];
        final noteText = draft.notesController.text.trim().isNotEmpty
            ? draft.notesController.text.trim()
            : (reasons.isEmpty ? '' : l10n.t('referral_suggested_due_to', {'reasons': reasons.join(', ')}));
        final referralRisk = _formatRisk(domain?.risk ?? widget.overallRisk);

        final payload = {
          'child_id': widget.childId,
          'aww_id': widget.awwId,
          'age_months': widget.ageMonths,
          'overall_risk': referralRisk,
          'domain_scores': widget.domainScores,
          'referral_type': _backendReferralType(draft.referralType),
          'urgency': draft.urgency,
          'expected_follow_up': draft.followUpDate.toIso8601String(),
          'notes': noteText,
          'referral_timestamp': now.toIso8601String(),
        };

        final response = await api.createReferral(payload);
        final serverReferralId = '${response['referral_id'] ?? ''}'.trim();
        final referralId = serverReferralId.isEmpty ? fallbackReferralId : serverReferralId;
        createdReferralIdForFollowUp ??= referralId;
        await localDb.saveReferral(
          ReferralModel(
            referralId: referralId,
            screeningId: 'unknown_screening',
            childId: widget.childId,
            awwId: widget.awwId,
            referralType: _toReferralType(draft.referralType),
            urgency: _toUrgency(draft.urgency),
            status: ReferralStatus.pending,
            notes: noteText,
            expectedFollowUpDate: draft.followUpDate,
            createdAt: now,
            metadata: {
              'sync_status': 'synced',
              'domain': domain?.key,
              'domain_risk': domain?.risk,
              'overall_risk': _normalizeRisk(domain?.risk ?? widget.overallRisk),
              'referral_type_label': draft.referralType,
              'age_months': widget.ageMonths,
            },
          ),
        );
      }
    } catch (e) {
      final localDb = LocalDBService();
      await localDb.initialize();
      var index = 0;
      for (final draft in drafts) {
        index += 1;
        final domain = draft.domain;
        final referralId = 'ref_${now.microsecondsSinceEpoch}_$index';
        final reasons = domain == null
            ? <String>[]
            : ['${_domainLabel(domain.key, l10n)} (${_riskLabel(domain.risk, l10n)})'];
        final noteText = draft.notesController.text.trim().isNotEmpty
            ? draft.notesController.text.trim()
            : (reasons.isEmpty ? '' : l10n.t('referral_suggested_due_to', {'reasons': reasons.join(', ')}));

        await localDb.saveReferral(
          ReferralModel(
            referralId: referralId,
            screeningId: 'offline_referral',
            childId: widget.childId,
            awwId: widget.awwId,
            referralType: _toReferralType(draft.referralType),
            urgency: _toUrgency(draft.urgency),
            status: ReferralStatus.pending,
            notes: noteText,
            expectedFollowUpDate: draft.followUpDate,
            createdAt: now,
            metadata: {
              'sync_status': 'not_synced',
              'domain': domain?.key,
              'domain_risk': domain?.risk,
              'overall_risk': _normalizeRisk(domain?.risk ?? widget.overallRisk),
              'referral_type_label': draft.referralType,
              'age_months': widget.ageMonths,
            },
          ),
        );
      }
    } finally {
      for (final draft in drafts) {
        draft.notesController.dispose();
      }
      if (mounted) {
        setState(() {
          _referralDrafts.removeWhere(drafts.contains);
          submitting = false;
        });
        if (openFollowUpForCreatedReferral && createdReferralIdForFollowUp != null) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FollowupCompleteScreen(
                referralId: createdReferralIdForFollowUp!,
                childId: widget.childId,
                userRole: 'AWW',
              ),
            ),
          );
        }
        if (mounted && openReferralListAfterCreate) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ReferralBatchSummaryScreen(childId: widget.childId),
            ),
          );
        } else if (mounted && _referralDrafts.isEmpty) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
            (route) => false,
          );
        }
      }
    }
  }

  int _riskSeverity(String risk) {
    switch (_normalizeRisk(risk)) {
      case 'critical':
        return 3;
      case 'high':
        return 2;
      case 'medium':
        return 1;
      default:
        return 0;
    }
  }

  String _riskFromScore(double v) {
    if (v <= 0.4) return 'Critical';
    if (v <= 0.6) return 'High';
    if (v <= 0.8) return 'Medium';
    return 'Low';
  }

  String _normalizeRisk(String risk) => risk.trim().toLowerCase();

  String _formatRisk(String risk) {
    final n = _normalizeRisk(risk);
    return n.isEmpty ? risk : '${n[0].toUpperCase()}${n.substring(1)}';
  }

  String _domainLabel(String key, AppLocalizations l10n) {
    switch (key) {
      case 'GM':
        return l10n.t('domain_gm');
      case 'FM':
        return l10n.t('domain_fm');
      case 'LC':
        return l10n.t('domain_lc');
      case 'COG':
        return l10n.t('domain_cog');
      case 'SE':
        return l10n.t('domain_se');
      default:
        return key;
    }
  }

  String _riskLabel(String riskKey, AppLocalizations l10n) {
    switch (_normalizeRisk(riskKey)) {
      case 'critical':
        return l10n.t('critical');
      case 'high':
        return l10n.t('high');
      case 'medium':
        return l10n.t('medium');
      case 'low':
        return l10n.t('low');
      default:
        return riskKey;
    }
  }

  String _urgencyLabel(String value, AppLocalizations l10n) {
    switch (value) {
      case 'Immediate':
        return l10n.t('urgency_immediate');
      case 'Urgent':
        return l10n.t('urgency_urgent');
      default:
        return l10n.t('urgency_normal');
    }
  }

  ReferralType _toReferralType(String value) {
    switch (value) {
      case 'PHC':
        return ReferralType.enhancedMonitoring;
      case 'Physiotherapist':
      case 'Occupational Therapist':
      case 'Speech Therapist':
      case 'Developmental Specialist':
      case 'Child Psychologist':
        return ReferralType.specialistEvaluation;
      default:
        return ReferralType.enhancedMonitoring;
    }
  }

  String _backendReferralType(String value) {
    switch (value) {
      case 'PHC':
      case 'RBSK':
        return value;
      default:
        return 'PHC';
    }
  }

  ReferralUrgency _toUrgency(String value) {
    switch (value) {
      case 'Urgent':
        return ReferralUrgency.priority;
      case 'Immediate':
        return ReferralUrgency.immediate;
      default:
        return ReferralUrgency.normal;
    }
  }

  Widget _buildDraftCard(_ReferralDraft draft) {
    final l10n = AppLocalizations.of(context);
    final hasDomain = draft.domain != null;
    final chipColor = hasDomain ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9);
    final chipText = hasDomain ? const Color(0xFFE53935) : const Color(0xFF2E7D32);
    final domainLabel = hasDomain ? _domainLabel(draft.domain!.key, l10n) : '';
    final riskLabel = hasDomain ? _riskLabel(draft.domain!.risk, l10n) : '';

    return Card(
      color: const Color(0xFFF7FAFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.t('create_referral'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              l10n.t(
                'recommended_referral',
                {
                  'type': draft.referralType,
                  'urgency': _urgencyLabel(draft.urgency, l10n),
                },
              ),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (!hasDomain)
              Text(l10n.t('no_high_critical_domains'), style: const TextStyle(fontSize: 12))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      '$domainLabel ($riskLabel)',
                      style: TextStyle(fontSize: 11, color: chipText, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: draft.referralType,
              items: referralTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => draft.referralType = v ?? draft.referralType),
              decoration: InputDecoration(labelText: l10n.t('referral_type')),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: draft.urgency,
              items: urgencies.map((u) => DropdownMenuItem(value: u, child: Text(_urgencyLabel(u, l10n)))).toList(),
              onChanged: (v) => setState(() => draft.urgency = v ?? draft.urgency),
              decoration: InputDecoration(labelText: l10n.t('urgency')),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE0E6ED)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                title: Text(l10n.t('expected_followup_date')),
                subtitle: Text(
                  '${draft.followUpDate.year}-${draft.followUpDate.month.toString().padLeft(2, '0')}-${draft.followUpDate.day.toString().padLeft(2, '0')}',
                ),
                trailing: OutlinedButton(
                  onPressed: () => _pickDate(draft),
                  child: Text(l10n.t('pick_date')),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              maxLines: 3,
              controller: draft.notesController,
              decoration: InputDecoration(labelText: l10n.t('notes')),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    draft.referralType = draft.recommendedReferralType;
                    draft.urgency = draft.recommendedUrgency;
                    draft.followUpDate = draft.recommendedFollowUpDate;
                    if (hasDomain) {
                      final reasons = '$domainLabel ($riskLabel)';
                      draft.notesController.text = l10n.t('referral_suggested_due_to', {'reasons': reasons});
                    }
                  });
                },
                child: Text(l10n.t('use_recommendation')),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: submitting
                    ? null
                    : () => _createReferral(
                          selectedDraft: draft,
                          openFollowUpForCreatedReferral: false,
                          openReferralListAfterCreate: true,
                        ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(submitting ? l10n.t('submitting') : l10n.t('create_referral')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;
    final headerHeight = isWide ? 200.0 : 170.0;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF3F7FB), Color(0xFFE9F1F8)],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              _buildSideNav(),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: headerHeight,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            top: 0,
                            right: 0,
                            child: const LanguageMenuButton(iconColor: Colors.white),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                padding: const EdgeInsets.all(6),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/images/ap_logo.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stack) => Center(
                                      child: Text(
                                        AppLocalizations.of(context).t('ap_short'),
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                AppLocalizations.of(context).t('govt_andhra_pradesh'),
                                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                AppLocalizations.of(context).t('app_subtitle'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isWide ? 26 : 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 780),
                            child: Card(
                              elevation: 8,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l10n.t('create_referral'),
                                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        l10n.t('recommendation_engine_hint'),
                                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                      ),
                                      if (_recommendedDomains.length > 1) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Multiple risk domains detected. Separate referrals will be created.',
                                          style: TextStyle(color: Colors.grey[700], fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      if (_referralDrafts.isEmpty)
                                        Text(
                                          'No domains available for referral creation.',
                                          style: TextStyle(color: Colors.grey[700], fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      for (int i = 0; i < _referralDrafts.length; i++) ...[
                                        _buildDraftCard(_referralDrafts[i]),
                                        if (i < _referralDrafts.length - 1) const SizedBox(height: 12),
                                      ],
                                      if (_referralDrafts.length > 1) ...[
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: submitting
                                                ? null
                                                : () => _createReferral(
                                                      openFollowUpForCreatedReferral: false,
                                                      openReferralListAfterCreate: true,
                                                    ),
                                            style: ElevatedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                            child: Text(
                                              submitting
                                                  ? l10n.t('submitting')
                                                  : l10n.t('create_referrals'),
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DomainRisk {
  final String key;
  final String risk;
  final double? score;
  final int severity;

  const _DomainRisk({
    required this.key,
    required this.risk,
    required this.score,
    required this.severity,
  });
}

class _ReferralRecommendation {
  final _DomainRisk? domain;
  final String referralType;
  final String urgency;
  final DateTime followUpDate;

  const _ReferralRecommendation({
    required this.domain,
    required this.referralType,
    required this.urgency,
    required this.followUpDate,
  });
}

class _ReferralDraft {
  final _DomainRisk? domain;
  String referralType;
  final String recommendedReferralType;
  String urgency;
  final String recommendedUrgency;
  DateTime followUpDate;
  final DateTime recommendedFollowUpDate;
  final TextEditingController notesController;

  _ReferralDraft({
    required this.domain,
    required this.referralType,
    required this.recommendedReferralType,
    required this.urgency,
    required this.recommendedUrgency,
    required this.followUpDate,
    required this.recommendedFollowUpDate,
    required this.notesController,
  });
}
