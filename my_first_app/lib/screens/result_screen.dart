import 'package:flutter/material.dart';
import 'package:my_first_app/core/localization/app_localizations.dart';
import 'package:my_first_app/core/navigation/navigation_state_service.dart';
import 'package:my_first_app/models/child_model.dart';
import 'package:my_first_app/models/screening_model.dart' as sm;
import 'package:my_first_app/screens/dashboard_screen.dart';
import 'package:my_first_app/screens/referral_screen.dart';
import 'package:my_first_app/screens/settings_screen.dart';
import 'package:my_first_app/services/local_db_service.dart';
import 'package:my_first_app/widgets/language_menu_button.dart';

class ResultScreen extends StatefulWidget {
  final Map<String, double> domainScores;
  final Map<String, String>? domainRiskLevels;
  final Map<String, int>? delaySummary;
  final int? baselineScore;
  final String? baselineCategory;
  final String overallRisk;
  final int missedMilestones;
  final String explainability;
  final String childId;
  final String awwId;
  final int ageMonths;

  const ResultScreen({
    super.key,
    required this.domainScores,
    this.domainRiskLevels,
    this.delaySummary,
    this.baselineScore,
    this.baselineCategory,
    required this.overallRisk,
    required this.missedMilestones,
    required this.explainability,
    required this.childId,
    required this.awwId,
    required this.ageMonths,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final LocalDBService _localDb = LocalDBService();

  @override
  void initState() {
    super.initState();
    NavigationStateService.instance.saveState(
      screen: NavigationStateService.screenResult,
      args: <String, dynamic>{
        'child_id': widget.childId,
        'age_months': widget.ageMonths,
        'aww_id': widget.awwId,
        'overall_risk': widget.overallRisk,
        'missed_milestones': widget.missedMilestones,
        'explainability': widget.explainability,
        'baseline_score': widget.baselineScore,
        'baseline_category': widget.baselineCategory,
        'domain_scores': widget.domainScores,
        'domain_risk_levels': widget.domainRiskLevels ?? <String, String>{},
        'delay_summary': widget.delaySummary ?? <String, int>{},
      },
    );
  }

  String _domainStatusText(double v) {
    if (v <= 0.4) return 'Critical';
    if (v <= 0.6) return 'High';
    if (v <= 0.8) return 'Medium';
    return 'Low';
  }

  String _normalizeRisk(String risk) => risk.trim().toLowerCase();

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

  String _deriveOverallRisk() {
    var worstRisk = _normalizeRisk(widget.overallRisk);
    var worstSeverity = _riskSeverity(worstRisk);

    widget.domainScores.forEach((key, value) {
      final label = widget.domainRiskLevels?[key] ?? _domainStatusText(value);
      final normalized = _normalizeRisk(label);
      final severity = _riskSeverity(normalized);
      if (severity > worstSeverity) {
        worstSeverity = severity;
        worstRisk = normalized;
      }
    });

    return worstRisk.isEmpty ? 'low' : worstRisk;
  }

  Color _riskColor(String risk) {
    switch (_normalizeRisk(risk)) {
      case 'critical':
      case 'high':
        return const Color(0xFFE53935);
      case 'medium':
        return const Color(0xFFF9A825);
      default:
        return const Color(0xFF43A047);
    }
  }

  Color _riskTint(String risk) {
    switch (_normalizeRisk(risk)) {
      case 'critical':
      case 'high':
        return const Color(0xFFFFEBEE);
      case 'medium':
        return const Color(0xFFFFF8E1);
      default:
        return const Color(0xFFE8F5E9);
    }
  }

  Color _riskTextOnBadge(String risk) {
    return _normalizeRisk(risk) == 'medium' ? Colors.black87 : Colors.white;
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

  String _localizedRiskLabel(String riskKey, AppLocalizations l10n) {
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

  Future<void> _goDashboard() async {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (route) => false,
    );
  }

  Future<void> _showChildrenCount() async {
    await _localDb.initialize();
    final count = _localDb.getAllChildren().length;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.t('children')),
        content: Text(l10n.t('total_registered_children', {'count': '$count'})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.t('ok')),
          ),
        ],
      ),
    );
  }

  Future<void> _showRiskStatus() async {
    await _localDb.initialize();
    final children = _localDb.getAllChildren();
    final all = <sm.ScreeningModel>[];
    for (final ChildModel c in children) {
      all.addAll(_localDb.getChildScreenings(c.childId));
    }

    final low = all.where((s) => s.overallRisk == sm.RiskLevel.low).length;
    final medium = all
        .where((s) => s.overallRisk == sm.RiskLevel.medium)
        .length;
    final high = all.where((s) => s.overallRisk == sm.RiskLevel.high).length;
    final critical = all
        .where((s) => s.overallRisk == sm.RiskLevel.critical)
        .length;

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.t('risk_status')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.t('risk_count_low', {'count': '$low'})),
            Text(l10n.t('risk_count_medium', {'count': '$medium'})),
            Text(l10n.t('risk_count_high', {'count': '$high'})),
            Text(l10n.t('risk_count_critical', {'count': '$critical'})),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.t('ok')),
          ),
        ],
      ),
    );
  }

  Future<void> _openPastResults() async {
    await _localDb.initialize();
    final children = _localDb.getAllChildren();
    final past = <sm.ScreeningModel>[];
    for (final c in children) {
      past.addAll(_localDb.getChildScreenings(c.childId));
    }
    past.sort((a, b) => b.screeningDate.compareTo(a.screeningDate));

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (past.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.t('no_past_results'))));
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
            title: Text(
              '${s.childId} - ${l10n.t(risk.toLowerCase()).toUpperCase()}',
            ),
            subtitle: Text(
              l10n.t('date_label', {'date': '${s.screeningDate.toLocal()}'}),
            ),
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

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  Widget _buildNavDrawer() {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            ListTile(
              title: Text(
                AppLocalizations.of(context).t('navigation'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(AppLocalizations.of(context).t('dashboard')),
              onTap: _goDashboard,
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(AppLocalizations.of(context).t('children')),
              onTap: () {
                Navigator.of(context).pop();
                _showChildrenCount();
              },
            ),
            ListTile(
              leading: const Icon(Icons.dataset_outlined),
              title: Text(AppLocalizations.of(context).t('risk_status')),
              onTap: () {
                Navigator.of(context).pop();
                _showRiskStatus();
              },
            ),
            ListTile(
              leading: const Icon(Icons.query_stats_outlined),
              title: Text(AppLocalizations.of(context).t('view_past_results')),
              onTap: () {
                Navigator.of(context).pop();
                _openPastResults();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(AppLocalizations.of(context).t('settings')),
              onTap: () {
                Navigator.of(context).pop();
                _openSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultContent(BuildContext context, {required bool desktop}) {
    final l10n = AppLocalizations.of(context);
    final overallRiskLabel = _deriveOverallRisk();
    final gmDelay = widget.delaySummary?['GM_delay'] ?? 0;
    final fmDelay = widget.delaySummary?['FM_delay'] ?? 0;
    final lcDelay = widget.delaySummary?['LC_delay'] ?? 0;
    final cogDelay = widget.delaySummary?['COG_delay'] ?? 0;
    final seDelay = widget.delaySummary?['SE_delay'] ?? 0;
    final numDelays =
        widget.delaySummary?['num_delays'] ??
        (gmDelay + fmDelay + lcDelay + cogDelay + seDelay);
    final sorted = widget.domainScores.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final focusDomain = sorted.isNotEmpty ? sorted.first : null;

    Widget domainMiniCard(String key, double score, {Color? bg}) {
      final riskKey = widget.domainRiskLevels?[key] ?? _domainStatusText(score);
      final c = _riskColor(riskKey);
      final name = _domainLabel(key, l10n);
      final displayRisk = _localizedRiskLabel(riskKey, l10n);
      return Container(
        width: 190,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg ?? _riskTint(riskKey),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 9,
              backgroundColor: c,
              child: const Icon(
                Icons.brightness_1,
                size: 7,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    l10n.t('score_percent', {
                      'score': '${(score * 100).round()}',
                    }),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF596773),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                displayRisk,
                style: TextStyle(
                  color: _riskTextOnBadge(riskKey),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        desktop ? 18 : 12,
        12,
        desktop ? 18 : 12,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: desktop ? 420 : double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _riskColor(overallRiskLabel),
                  _riskColor(overallRiskLabel).withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t('overall_risk'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.t('score_percent', {
                          'score':
                              '${(widget.domainScores.values.isEmpty ? 0 : (widget.domainScores.values.reduce((a, b) => a + b) / widget.domainScores.length) * 100).round()}',
                        }),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _riskColor(overallRiskLabel),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    _localizedRiskLabel(overallRiskLabel, l10n).toUpperCase(),
                    style: TextStyle(
                      color: _riskTextOnBadge(overallRiskLabel),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (focusDomain != null)
            Builder(
              builder: (_) {
                final focusRiskKey =
                    widget.domainRiskLevels?[focusDomain.key] ??
                    _domainStatusText(focusDomain.value);
                final focusColor = _riskColor(focusRiskKey);
                final focusRiskLabel = _localizedRiskLabel(focusRiskKey, l10n);
                return Container(
                  width: desktop ? 420 : double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _riskTint(focusRiskKey),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE6ECF3)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: focusColor,
                        child: const Icon(
                          Icons.priority_high,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _domainLabel(focusDomain.key, l10n),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              l10n.t('score_percent', {
                                'score': '${(focusDomain.value * 100).round()}',
                              }),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF5D6975),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: focusColor,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          focusRiskLabel,
                          style: TextStyle(
                            color: _riskTextOnBadge(focusRiskKey),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 10),
          Text(
            AppLocalizations.of(context).t('domain_breakdown'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF40505E),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: widget.domainScores.entries.map((e) {
                final riskText =
                    widget.domainRiskLevels?[e.key] ??
                    _domainStatusText(e.value);
                final bg = _riskTint(riskText);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: domainMiniCard(e.key, e.value, bg: bg),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFFF3EDF9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).t('delay_summary'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 32,
                      dataRowMinHeight: 34,
                      dataRowMaxHeight: 34,
                      columnSpacing: 24,
                      columns: [
                        DataColumn(
                          label: Text(
                            AppLocalizations.of(context).t('gm_delay'),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            AppLocalizations.of(context).t('fm_delay'),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            AppLocalizations.of(context).t('lc_delay'),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            AppLocalizations.of(context).t('cog_delay'),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            AppLocalizations.of(context).t('se_delay'),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            AppLocalizations.of(context).t('num_delays'),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                      rows: [
                        DataRow(
                          cells: [
                            DataCell(
                              Text(
                                '$gmDelay',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            DataCell(
                              Text(
                                '$fmDelay',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            DataCell(
                              Text(
                                '$lcDelay',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            DataCell(
                              Text(
                                '$cogDelay',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            DataCell(
                              Text(
                                '$seDelay',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            DataCell(
                              Text(
                                '$numDelays',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFFF3EDF9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              title: Text(
                AppLocalizations.of(context).t('explainability'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(widget.explainability),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: desktop ? 420 : double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.local_hospital),
              label: const Text('Continue to Referral'),
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ReferralScreen(
                      childId: widget.childId,
                      awwId: widget.awwId,
                      ageMonths: widget.ageMonths,
                      overallRisk: widget.overallRisk,
                      domainScores: widget.domainScores,
                      domainRiskLevels: widget.domainRiskLevels,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: desktop ? 420 : double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.dashboard_outlined),
              label: const Text('Back to Dashboard'),
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const DashboardScreen()),
                  (route) => false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 1000;

    if (!isDesktop) {
      return Scaffold(
        drawer: _buildNavDrawer(),
        appBar: AppBar(
          title: Text(l10n.t('screening_result')),
          backgroundColor: const Color(0xFF0D5BA7),
          foregroundColor: Colors.white,
          actions: [
            const LanguageMenuButton(iconColor: Colors.white),
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          ],
        ),
        body: _buildResultContent(context, desktop: false),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      body: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1C86DF), Color(0xFF2A9AF5)],
              ),
            ),
            child: Row(
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/images/ap_logo.png',
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        AppLocalizations.of(context).t('ap_short'),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF1976D2),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context).t('govt_andhra_pradesh'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                const LanguageMenuButton(iconColor: Colors.white, iconSize: 18),
                const Icon(Icons.search, color: Colors.white, size: 18),
                const SizedBox(width: 14),
                const Icon(
                  Icons.power_settings_new,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 14),
                const Icon(Icons.menu, color: Colors.white, size: 18),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 220,
                  color: Colors.white,
                  child: ListView(
                    children: [
                      _ResultSideItem(
                        icon: Icons.home_outlined,
                        label: l10n.t('dashboard'),
                        onTap: _goDashboard,
                      ),
                      _ResultSideItem(
                        icon: Icons.people_outline,
                        label: l10n.t('children'),
                        onTap: _showChildrenCount,
                      ),
                      _ResultSideItem(
                        icon: Icons.dataset_outlined,
                        label: l10n.t('risk_status'),
                        onTap: _showRiskStatus,
                      ),
                      _ResultSideItem(
                        icon: Icons.query_stats_outlined,
                        label: l10n.t('view_past_results'),
                        onTap: _openPastResults,
                      ),
                      _ResultSideItem(
                        icon: Icons.settings_outlined,
                        label: l10n.t('settings'),
                        onTap: _openSettings,
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildResultContent(context, desktop: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultSideItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ResultSideItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE7EDF3))),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: Icon(icon, size: 18, color: const Color(0xFF6A7580)),
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF58636F),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
