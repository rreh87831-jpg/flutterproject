import 'package:flutter/material.dart';
import 'package:my_first_app/core/localization/app_localizations.dart';
import 'package:my_first_app/core/navigation/navigation_state_service.dart';
import 'package:my_first_app/models/referral_model.dart';
import 'package:my_first_app/models/referral_summary_item.dart';
import 'package:my_first_app/screens/dashboard_screen.dart';
import 'package:my_first_app/services/api_service.dart';
import 'package:my_first_app/services/auth_service.dart';
import 'package:my_first_app/services/local_db_service.dart';
import 'package:my_first_app/widgets/language_menu_button.dart';

class ReferralBatchSummaryScreen extends StatefulWidget {
  final List<ReferralSummaryItem>? referrals;
  final String? childId;

  const ReferralBatchSummaryScreen({
    super.key,
    this.referrals,
    this.childId,
  });

  @override
  State<ReferralBatchSummaryScreen> createState() => _ReferralBatchSummaryScreenState();
}

class _ReferralBatchSummaryScreenState extends State<ReferralBatchSummaryScreen> {
  bool _loading = true;
  List<ReferralModel> _models = [];
  List<ReferralSummaryItem> _provided = [];
  final APIService _api = APIService();
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    NavigationStateService.instance.saveState(
      screen: NavigationStateService.screenReferralBatchSummary,
      args: <String, dynamic>{
        'child_id': widget.childId,
      },
    );
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.referrals != null && widget.referrals!.isNotEmpty) {
        _provided = widget.referrals!;
      } else {
        final db = LocalDBService();
        await db.initialize();
        if (widget.childId == null) {
          _models = db.getAllReferrals();
          final serverItems = await _loadServerReferralsForAwc();
          if (serverItems.isNotEmpty) {
            _provided = serverItems;
          }
        } else {
          _models = db.getChildReferrals(widget.childId!);
          final serverReferral = await _loadServerReferral(widget.childId!);
          if (serverReferral != null) {
            _provided = [serverReferral];
          }
        }
      }
    } catch (e) {
      _models = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<ReferralSummaryItem?> _loadServerReferral(String childId) async {
    try {
      final details = await _api.getReferralDetailsByChild(childId);
      Map<String, dynamic>? byChild;
      try {
        byChild = await _api.getReferralByChild(childId);
      } catch (_) {
        byChild = null;
      }
      return _fromServer(details, byChild);
    } catch (_) {
      try {
        final byChild = await _api.getReferralByChild(childId);
        return _fromLegacyByChild(byChild);
      } catch (_) {
        return null;
      }
    }
  }

  Future<List<ReferralSummaryItem>> _loadServerReferralsForAwc() async {
    try {
      final awcCode = (await _auth.getLoggedInAwcCode() ?? '').trim().toUpperCase();
      final rows = await _api.getReferralList(
        limit: 500,
        awwId: awcCode.isEmpty ? null : awcCode,
      );
      if (rows.isEmpty) {
        return const <ReferralSummaryItem>[];
      }
      final futures = rows.map(_fromReferralListRowWithDetails);
      final items = await Future.wait(futures);
      return items;
    } catch (_) {
      return const <ReferralSummaryItem>[];
    }
  }

  String _formatDate(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd';
  }

  Color _riskColor(String risk) {
    final r = risk.trim().toLowerCase();
    if (r == 'critical' || r == 'high') return const Color(0xFFE53935);
    if (r == 'medium') return const Color(0xFFF9A825);
    return const Color(0xFF43A047);
  }

  String _riskLabel(String risk, AppLocalizations l10n) {
    switch (risk.trim().toLowerCase()) {
      case 'critical':
        return l10n.t('critical');
      case 'high':
        return l10n.t('high');
      case 'medium':
        return l10n.t('medium');
      case 'low':
        return l10n.t('low');
      default:
        return risk;
    }
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

  String _urgencyLabel(String value, AppLocalizations l10n) {
    switch (value) {
      case 'Immediate':
        return l10n.t('urgency_immediate');
      case 'Priority':
      case 'Urgent':
        return l10n.t('urgency_urgent');
      default:
        return l10n.t('urgency_normal');
    }
  }

  String _urgencyRaw(ReferralUrgency urgency) {
    switch (urgency) {
      case ReferralUrgency.immediate:
        return 'Immediate';
      case ReferralUrgency.priority:
        return 'Priority';
      default:
        return 'Normal';
    }
  }

  List<String> _extractDomainKeys(List<String> reasons) {
    if (reasons.isEmpty) return const <String>[];
    const keys = ['GM', 'FM', 'LC', 'COG', 'SE'];
    final found = <String>{};
    for (final reason in reasons) {
      final upper = reason.toUpperCase();
      for (final key in keys) {
        if (RegExp('\\b$key\\b').hasMatch(upper)) {
          found.add(key);
        }
      }
    }
    return keys.where(found.contains).toList();
  }

  List<String> _riskFallbackActivities(String risk, AppLocalizations l10n) {
    switch (risk.trim().toLowerCase()) {
      case 'critical':
        return [
          'Arrange specialist review within 24-48 hours.',
          'Check caregiver adherence twice weekly until stable.',
          'Escalate to senior medical team if no improvement in 7 days.',
        ];
      case 'high':
        return [
          'Schedule specialist assessment within 7 days.',
          'Provide targeted home activities and monitor completion daily.',
          'Review progress with caregiver in 2 weeks.',
        ];
      case 'medium':
        return [
          'Coach caregiver on focused stimulation activities at home.',
          'Track progress weekly and reassess in 4 weeks.',
        ];
      case 'low':
        return [
          'Continue age-appropriate stimulation at home.',
          'Re-screen during the next routine visit.',
        ];
      default:
        return [l10n.t('followup_generic_1'), l10n.t('followup_generic_2')];
    }
  }

  List<String> _dedupeActions(List<String> actions) {
    final unique = <String>[];
    final seen = <String>{};
    for (final action in actions) {
      final key = action.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      unique.add(action);
    }
    return unique;
  }

  List<String> _followUpActions(ReferralSummaryItem referral, AppLocalizations l10n) {
    final domainKeys = _extractDomainKeys(referral.reasons);
    final age = referral.ageMonths;

    if (domainKeys.isEmpty) {
      return _riskFallbackActivities(referral.overallRisk, l10n);
    }

    final actions = <String>[];
    for (final domainKey in domainKeys) {
      switch (domainKey) {
        case 'GM':
          actions.addAll(_gmActivities(age));
          break;
        case 'FM':
          actions.addAll(_fmActivities(age));
          break;
        case 'LC':
          actions.addAll(_lcActivities(age));
          break;
        case 'COG':
          actions.addAll(_cogActivities(age));
          break;
        case 'SE':
          actions.addAll(_seActivities(age));
          break;
      }
    }
    return _dedupeActions(actions);
  }

  List<String> _gmActivities(int ageMonths) {
    if (ageMonths <= 12) {
      return [
        'Daily tummy time',
        'Encourage rolling',
        'Supported sitting',
        'Crawling practice',
        'Pull to stand',
        'Reach for toys',
        'Assisted cruising',
        'Floor free movement',
        'Gentle stretching',
        'Avoid prolonged cradle use',
      ];
    }
    if (ageMonths <= 24) {
      return [
        'Independent walking practice',
        'Push–pull toys',
        'Ball kicking',
        'Squat & stand games',
        'Safe climbing',
        'Dancing',
        'Outdoor walking',
        'Mini obstacle play',
        'Stair practice (with support)',
        'Playground time',
      ];
    }
    if (ageMonths <= 36) {
      return [
        'Jump with both feet',
        'Running games',
        'Throw & catch large ball',
        'Tiptoe walking',
        'Tricycle attempt',
        'Balance walking',
        'Animal walk games',
        'Climbing steps',
        'Outdoor play daily',
        'Follow-the-leader',
      ];
    }
    if (ageMonths <= 48) {
      return [
        'Hop practice',
        'Stand on one foot',
        'Ride tricycle',
        'Jump forward',
        'Obstacle course',
        'Catch big ball',
        'Simple yoga',
        'Playground climbing',
        'Dance movements',
        'Ladder climbing',
      ];
    }
    if (ageMonths <= 60) {
      return [
        'Hop on one foot',
        'Skip attempt',
        'Catch bounce ball',
        'Somersault',
        'Balance beam',
        'Jump rope start',
        'Mini races',
        'Football kick',
        'Swing play',
        'Relay games',
      ];
    }
    return [
      'Bicycle riding',
      'Smooth skipping',
      'Jump rope',
      'Team sports',
      'Running drills',
      'Climbing wall',
      'Yoga balance poses',
      'Outdoor daily play',
      'Advanced obstacle games',
      'Coordination drills',
    ];
  }

  List<String> _fmActivities(int ageMonths) {
    if (ageMonths <= 12) {
      return [
        'Grasp rattles',
        'Transfer objects',
        'Reach & grab',
        'Finger play',
        'Crinkle paper',
        'Texture exploration',
        'Self-feeding practice',
        'Soft squeeze toys',
        'Hold caregiver finger',
        'Mirror hand play',
      ];
    }
    if (ageMonths <= 24) {
      return [
        'Scribbling',
        'Stack blocks',
        'Shape sorter',
        'Turn book pages',
        'Spoon practice',
        'Put objects in container',
        'Playdough squeeze',
        'Open/close boxes',
        'Large peg board',
        'Remove socks',
      ];
    }
    if (ageMonths <= 36) {
      return [
        'Tower 6 blocks',
        'Draw lines',
        'Large bead threading',
        'Clay rolling',
        'Sticker pasting',
        'Paper tearing',
        'Water pouring',
        'Peg boards',
        'Lid opening',
        'Simple puzzles',
      ];
    }
    if (ageMonths <= 48) {
      return [
        'Draw circle',
        'Use scissors',
        'Button practice',
        'Copy shapes',
        'Fold paper',
        'Clay modeling',
        'Tweezer picking',
        'Medium bead threading',
        'Coloring control',
        'Lacing cards',
      ];
    }
    if (ageMonths <= 60) {
      return [
        'Draw square',
        'Cut straight line',
        'Trace letters',
        'Zip/unzip',
        'Fork use',
        'Small bead threading',
        'Paste within lines',
        'Pattern copying',
        'Craft work',
        'Pencil grip correction',
      ];
    }
    return [
      'Write letters',
      'Draw triangle',
      'Tie shoelaces',
      'Detailed coloring',
      'Copy patterns',
      'Handwriting practice',
      'Model building',
      'Button small buttons',
      'Dot-to-dot',
      'Fine craft work',
    ];
  }

  List<String> _lcActivities(int ageMonths) {
    if (ageMonths <= 12) {
      return [
        'Talk frequently',
        'Name objects',
        'Sing rhymes',
        'Respond to babbling',
        'Read picture books',
        'Call by name',
        'Gesture games',
        'Imitate sounds',
        'Eye contact',
        'Reduce screen time',
      ];
    }
    if (ageMonths <= 24) {
      return [
        'Label objects',
        'Encourage 2-word phrases',
        'Ask simple questions',
        'Expand child’s words',
        'Body part naming',
        'Action songs',
        'Daily reading',
        'Follow simple commands',
        'Show & tell',
        'Avoid baby talk',
      ];
    }
    if (ageMonths <= 36) {
      return [
        'Encourage short sentences',
        'Ask “what” questions',
        'Role play',
        'Picture description',
        'Color naming',
        'Story time',
        'Daily conversation',
        'Correct gently',
        'Vocabulary games',
        'Reduce screen time',
      ];
    }
    return [
      'Story narration',
      'Ask “why/how” questions',
      'Teach opposites',
      'Rhyme games',
      'Grammar correction gently',
      '3-step commands',
      'Group conversation',
      'Show & tell',
      'Memory storytelling',
      'Reading habit daily',
    ];
  }

  List<String> _cogActivities(int ageMonths) {
    if (ageMonths <= 12) {
      return [
        'Peek-a-boo',
        'Hide & find toy',
        'Cause-effect toys',
        'Mirror play',
        'Sound recognition',
        'Sensory exploration',
        'Object permanence games',
        'Imitation games',
        'Big-small concept',
        'Touch exploration',
      ];
    }
    if (ageMonths <= 24) {
      return [
        'Shape sorter',
        'Simple puzzles',
        'Matching objects',
        'Sorting colors',
        'Identify animals',
        'Pretend play',
        'Stack blocks',
        'Follow instructions',
        'Memory play',
        'Daily routine learning',
      ];
    }
    return [
      'Counting games',
      'Pattern recognition',
      'Number & letter recognition',
      'Story sequencing',
      'Problem-solving tasks',
      'Classification activities',
      'Board games',
      'Building blocks',
      'Concept learning (big/small, hot/cold)',
      'Question-answer sessions',
    ];
  }

  List<String> _seActivities(int ageMonths) {
    if (ageMonths <= 12) {
      return [
        'Smile back',
        'Cuddle time',
        'Eye contact',
        'Respond to cries',
        'Mirror expressions',
        'Routine schedule',
        'Parent bonding',
        'Face games',
        'Gentle praise',
        'Safe environment',
      ];
    }
    if (ageMonths <= 24) {
      return [
        'Parallel play',
        'Sharing encouragement',
        'Emotion naming',
        'Praise good behavior',
        'Simple group play',
        'Turn-taking',
        'Comfort when upset',
        'Consistent routine',
        'Encourage independence',
        'Avoid harsh punishment',
      ];
    }
    return [
      'Role play',
      'Teach sharing',
      'Group activities',
      'Identify feelings',
      'Story about emotions',
      'Encourage empathy',
      'Set simple rules',
      'Positive reinforcement',
      'Conflict resolution guidance',
      'Reward charts',
    ];
  }

  List<ReferralSummaryItem> _buildReferrals(AppLocalizations l10n) {
    final list = <ReferralSummaryItem>[
      ..._provided,
      ..._models.map((model) => _fromModel(model, l10n)),
    ];
    if (list.isEmpty) {
      return [];
    }
    final byId = <String, ReferralSummaryItem>{};
    for (final item in list) {
      byId[item.referralId] = item;
    }
    final deduped = byId.values.toList();
    deduped.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return deduped;
  }

  ReferralSummaryItem _fromServer(
    Map<String, dynamic> details,
    Map<String, dynamic>? byChild,
  ) {
    final childInfo = (details['child_info'] is Map)
        ? Map<String, dynamic>.from(details['child_info'] as Map)
        : <String, dynamic>{};
    final riskSummary = (details['risk_summary'] is Map)
        ? Map<String, dynamic>.from(details['risk_summary'] as Map)
        : <String, dynamic>{};
    final decision = (details['decision'] is Map)
        ? Map<String, dynamic>.from(details['decision'] as Map)
        : <String, dynamic>{};

    final severity = '${riskSummary['severity'] ?? 'LOW'}';
    final rawDelayed = riskSummary['delayed_domains'];
    final delayedDomains = rawDelayed is List ? rawDelayed.map((e) => '$e').toList() : const <String>[];
    final reasons = delayedDomains
        .map((domain) => '$domain (${severity.toUpperCase()})')
        .toList();

    return ReferralSummaryItem(
      referralId: '${details['referral_id'] ?? byChild?['referral_id'] ?? ''}',
      childId: '${childInfo['child_id'] ?? byChild?['child_id'] ?? widget.childId ?? ''}',
      awwId: '${childInfo['assigned_worker'] ?? byChild?['aww_id'] ?? ''}',
      ageMonths: _toInt(childInfo['age']),
      overallRisk: severity,
      referralType: '${byChild?['referral_type_label'] ?? 'Specialist Evaluation'}',
      urgency: '${decision['urgency'] ?? byChild?['urgency'] ?? 'Priority'}',
      status: '${details['status'] ?? byChild?['status'] ?? 'PENDING'}',
      createdAt: _toDateTime(decision['created_on'] ?? byChild?['created_on']),
      expectedFollowUpDate: _toDateTime(decision['deadline'] ?? byChild?['followup_by']),
      notes: null,
      reasons: reasons,
    );
  }

  ReferralSummaryItem _fromLegacyByChild(Map<String, dynamic> byChild) {
    return ReferralSummaryItem(
      referralId: '${byChild['referral_id'] ?? ''}',
      childId: '${byChild['child_id'] ?? widget.childId ?? ''}',
      awwId: '${byChild['aww_id'] ?? ''}',
      ageMonths: 0,
      overallRisk: 'MEDIUM',
      referralType: '${byChild['referral_type_label'] ?? 'Specialist Evaluation'}',
      urgency: '${byChild['urgency'] ?? 'Priority'}',
      status: '${byChild['status'] ?? 'PENDING'}',
      createdAt: _toDateTime(byChild['created_on']),
      expectedFollowUpDate: _toDateTime(byChild['followup_by']),
      notes: null,
      reasons: const <String>[],
    );
  }

  Future<ReferralSummaryItem> _fromReferralListRowWithDetails(
    Map<String, dynamic> row,
  ) async {
    final base = _fromReferralListRow(row);
    final childId = base.childId.trim();
    if (childId.isEmpty) {
      return base;
    }
    try {
      final details = await _api.getReferralDetailsByChild(childId);
      final riskSummary = (details['risk_summary'] is Map)
          ? Map<String, dynamic>.from(details['risk_summary'] as Map)
          : <String, dynamic>{};
      final childInfo = (details['child_info'] is Map)
          ? Map<String, dynamic>.from(details['child_info'] as Map)
          : <String, dynamic>{};

      final severity = '${riskSummary['severity'] ?? base.overallRisk}'.toUpperCase();
      final rawDelayed = riskSummary['delayed_domains'];
      final delayedDomains = rawDelayed is List
          ? rawDelayed.map((e) => '$e').toList()
          : const <String>[];
      final reasons = delayedDomains.map((domain) => '$domain ($severity)').toList();

      return ReferralSummaryItem(
        referralId: base.referralId,
        childId: base.childId,
        awwId: base.awwId,
        ageMonths: _toInt(childInfo['age']) > 0 ? _toInt(childInfo['age']) : base.ageMonths,
        overallRisk: severity,
        referralType: base.referralType,
        urgency: base.urgency,
        status: base.status,
        createdAt: base.createdAt,
        expectedFollowUpDate: base.expectedFollowUpDate,
        notes: base.notes,
        reasons: reasons.isEmpty ? base.reasons : reasons,
      );
    } catch (_) {
      return base;
    }
  }

  ReferralSummaryItem _fromReferralListRow(Map<String, dynamic> row) {
    return ReferralSummaryItem(
      referralId: '${row['referral_id'] ?? ''}',
      childId: '${row['child_id'] ?? ''}',
      awwId: '${row['aww_id'] ?? ''}',
      ageMonths: _toInt(row['age_months']),
      overallRisk: '${row['overall_risk'] ?? 'MEDIUM'}',
      referralType: '${row['referral_type_label'] ?? 'Specialist Evaluation'}',
      urgency: '${row['urgency'] ?? 'Priority'}',
      status: '${row['status'] ?? 'PENDING'}',
      createdAt: _toDateTime(row['created_on']),
      expectedFollowUpDate: _toDateTime(row['followup_by']),
      notes: null,
      reasons: const <String>[],
    );
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }

  DateTime _toDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  ReferralSummaryItem _fromModel(ReferralModel model, AppLocalizations l10n) {
    final meta = model.metadata ?? {};
    final domainKey = (meta['domain'] as String?) ?? '';
    final domainRisk = (meta['domain_risk'] as String?) ?? (meta['risk_level'] as String?) ?? 'low';
    final overallRisk = (meta['risk_level'] as String?) ?? (meta['overall_risk'] as String?) ?? domainRisk;
    final referralTypeLabel = (meta['referral_type_label'] as String?) ?? _referralTypeFallback(model.referralType);
    final ageMonthsValue = meta['age_months'];
    final ageMonths = ageMonthsValue is int
        ? ageMonthsValue
        : int.tryParse(ageMonthsValue?.toString() ?? '') ?? 0;
    final reasons = <String>[];
    final domainReason = (meta['domain_reason'] as String?) ?? '';
    if (domainReason.isNotEmpty) {
      reasons.add(domainReason);
    } else if (domainKey.isNotEmpty) {
      final label = _domainLabel(domainKey, l10n);
      if (domainRisk.isNotEmpty) {
        reasons.add('$label (${_riskLabel(domainRisk, l10n)})');
      } else {
        reasons.add(label);
      }
    }

    return ReferralSummaryItem(
      referralId: model.referralId,
      childId: model.childId,
      awwId: model.awwId,
      ageMonths: ageMonths,
      overallRisk: overallRisk,
      referralType: referralTypeLabel,
      urgency: _urgencyRaw(model.urgency),
      status: model.status.toString().split('.').last,
      createdAt: model.createdAt,
      expectedFollowUpDate: model.expectedFollowUpDate,
      notes: model.notes,
      reasons: reasons,
    );
  }

  String _referralTypeFallback(ReferralType type) {
    switch (type) {
      case ReferralType.enhancedMonitoring:
        return 'Enhanced Monitoring';
      case ReferralType.specialistEvaluation:
        return 'Specialist Evaluation';
      case ReferralType.immediateSpecialistReferral:
        return 'Immediate Specialist Referral';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isWide = MediaQuery.of(context).size.width >= 900;
    final referrals = _loading ? <ReferralSummaryItem>[] : _buildReferrals(l10n);

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
          child: Column(
            children: [
              Container(
                height: isWide ? 180 : 150,
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
                      left: 0,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () async {
                          if (Navigator.canPop(context)) {
                            Navigator.of(context).pop();
                          } else {
                            // Navigate to dashboard if no previous page
                            if (!mounted) return;
                            await NavigationStateService.instance.saveState(
                              screen: NavigationStateService.screenDashboard,
                            );
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const DashboardScreen(),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: const LanguageMenuButton(iconColor: Colors.white),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(6),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/ap_logo.png',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => Center(
                                child: Text(AppLocalizations.of(context).t('ap_short'), style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          AppLocalizations.of(context).t('govt_andhra_pradesh'),
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.t('referrals_created', {'count': referrals.length.toString()}),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isWide ? 22 : 20,
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
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_loading)
                            const Center(child: CircularProgressIndicator())
                          else if (referrals.isEmpty)
                            Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(l10n.t('no_past_results')),
                              ),
                            )
                          else ..._buildGroupedReferrals(referrals, l10n, context),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGroupedReferrals(
    List<ReferralSummaryItem> referrals,
    AppLocalizations l10n,
    BuildContext context,
  ) {
    final riskCategories = ['critical', 'high', 'medium', 'low'];
    final grouped = <String, List<ReferralSummaryItem>>{};

    for (final category in riskCategories) {
      grouped[category] = referrals
          .where((r) => r.overallRisk.toLowerCase() == category)
          .toList();
    }

    final List<Widget> categoryWidgets = [];
    for (final category in riskCategories) {
      final items = grouped[category] ?? [];
      if (items.isEmpty) continue;

      // Add category header
      categoryWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: _riskColor(category),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_riskLabel(category, l10n).toUpperCase()} (${items.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _riskColor(category),
                ),
              ),
            ],
          ),
        ),
      );

      // Add referrals for this category
      for (final referral in items) {
        categoryWidgets.add(
          Card(
            elevation: 6,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _riskColor(referral.overallRisk),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _riskLabel(referral.overallRisk, l10n).toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.t('referral_number', {'id': referral.referralId}),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                                      Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _infoTile(l10n.t('child_id'), referral.childId),
                      _infoTile(l10n.t('referral_type'), referral.referralType),
                      _infoTile(l10n.t('urgency'), _urgencyLabel(referral.urgency, l10n)),
                      _infoTile(l10n.t('created_on'), _formatDate(referral.createdAt)),
                      _infoTile(l10n.t('follow_up_by'), _formatDate(referral.expectedFollowUpDate)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.t('reasons'), style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey[800])),
                  const SizedBox(height: 6),
                  if (referral.reasons.isEmpty)
                    Text(l10n.t('no_specific_domain_triggers'))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: referral.reasons
                          .map((r) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3E0),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(r, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 14),
                  Text(l10n.t('follow_up_actions'),
                      style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey[800])),
                  const SizedBox(height: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _followUpActions(referral, l10n)
                        .map(
                          (action) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• '),
                                Expanded(child: Text(action)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    if (!_loading && referrals.isNotEmpty) {
      categoryWidgets.add(
        const SizedBox(height: 12),
      );
      categoryWidgets.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(l10n.t('back_to_dashboard')),
          ),
        ),
      );
    }

    return categoryWidgets;
  }

  Widget _infoTile(String label, String value) {
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE1E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF5D6B78), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
