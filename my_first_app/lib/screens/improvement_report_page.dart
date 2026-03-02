import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/referral_flow_api_service.dart';
import '../widgets/radar_chart.dart';

class ImprovementReportPage extends StatefulWidget {
  final String childId;
  final int? referralId;

  const ImprovementReportPage({
    super.key,
    required this.childId,
    this.referralId,
  });

  @override
  State<ImprovementReportPage> createState() => _ImprovementReportPageState();
}

class _ImprovementReportPageState extends State<ImprovementReportPage> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _isLoading = true;
  Map<String, dynamic>? _reportData;
  Map<String, dynamic>? _radarData;
  List<dynamic> _history = <dynamic>[];
  String _selectedView = 'overview';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final report = await ReferralFlowApiService.calculateImprovement(
        widget.childId,
        referralId: widget.referralId,
      );
      final radar = await ReferralFlowApiService.getRadarData(widget.childId);
      final history = await ReferralFlowApiService.getImprovementHistory(widget.childId);

      setState(() {
        _reportData = Map<String, dynamic>.from(report['data'] as Map);
        _radarData = radar;
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading report: $e')),
      );
    }
  }

  Future<void> _shareReport() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/improvement_report_${widget.childId}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Improvement report');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Color _riskColor(String? level) {
    switch ((level ?? '').toUpperCase()) {
      case 'CRITICAL':
        return Colors.red;
      case 'HIGH':
        return Colors.orange;
      case 'MEDIUM':
        return Colors.amber.shade700;
      case 'LOW':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _tab(String label, String value) {
    final selected = _selectedView == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedView = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0D5BA7) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey.shade700,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _improvementRow(String label, int before, int after, int delta) {
    final positive = delta > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$before -> $after'),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (positive ? Colors.green : Colors.orange).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${positive ? '+' : ''}$delta',
              style: TextStyle(
                color: positive ? Colors.green : Colors.orange.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Improvement Report')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_reportData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Improvement Report')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 54, color: Colors.grey),
              const SizedBox(height: 10),
              const Text('No improvement data available'),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final baseline = Map<String, dynamic>.from(_reportData!['baseline'] as Map);
    final current = Map<String, dynamic>.from(_reportData!['current'] as Map);
    final improvements = Map<String, dynamic>.from(_reportData!['improvements'] as Map);
    final milestones = List<dynamic>.from(_reportData!['milestones'] as List? ?? <dynamic>[]);
    final recommendations = List<dynamic>.from(_reportData!['recommendations'] as List? ?? <dynamic>[]);
    final completionRate = (_reportData!['completion_rate'] ?? 0).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Improvement Report'),
        backgroundColor: const Color(0xFF0D5BA7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _shareReport, icon: const Icon(Icons.share)),
        ],
      ),
      body: RepaintBoundary(
        key: _repaintKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: const Color(0xFF0D5BA7),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        _reportData!['child_name']?.toString() ?? 'Child ${widget.childId}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
                      ),
                      const SizedBox(height: 4),
                      const Text('Improvement Report', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Text('${_reportData!['period_days']} days', style: const TextStyle(color: Colors.white)),
                          Text('${completionRate.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white)),
                          Text('${improvements['overall']} pts', style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    _tab('Overview', 'overview'),
                    _tab('Domains', 'domains'),
                    _tab('Milestones', 'milestones'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedView == 'overview') ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Risk Level Progress', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text('Before'),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _riskColor(baseline['risk_level']),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    '${baseline['risk_level'] ?? 'UNKNOWN'}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('${baseline['overall_score'] ?? 0} pts'),
                              ],
                            ),
                            const Icon(Icons.arrow_forward),
                            Column(
                              children: [
                                const Text('After'),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _riskColor(current['risk_level']),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    '${current['risk_level'] ?? 'UNKNOWN'}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('${current['overall_score'] ?? 0} pts'),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (_reportData!['risk_level_change'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_radarData != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text('Domain Comparison', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 4),
                          const Text('Before vs After'),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 270,
                            child: RadarChart(
                              categories: List<String>.from(_radarData!['categories'] as List),
                              before: List<double>.from(_radarData!['before'] as List),
                              after: List<double>.from(_radarData!['after'] as List),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Key Improvements', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 8),
                        _improvementRow('Gross Motor', (baseline['gm'] ?? 0) as int, (current['gm'] ?? 0) as int, (improvements['gm'] ?? 0) as int),
                        _improvementRow('Fine Motor', (baseline['fm'] ?? 0) as int, (current['fm'] ?? 0) as int, (improvements['fm'] ?? 0) as int),
                        _improvementRow('Language', (baseline['lc'] ?? 0) as int, (current['lc'] ?? 0) as int, (improvements['lc'] ?? 0) as int),
                        _improvementRow('Cognitive', (baseline['cog'] ?? 0) as int, (current['cog'] ?? 0) as int, (improvements['cog'] ?? 0) as int),
                        _improvementRow('Social-Emotional', (baseline['se'] ?? 0) as int, (current['se'] ?? 0) as int, (improvements['se'] ?? 0) as int),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (recommendations.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Next Steps', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 8),
                          ...recommendations.map((e) {
                            final r = Map<String, dynamic>.from(e as Map);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.info_outline),
                              title: Text('${r['title'] ?? ''}'),
                              subtitle: Text('${r['description'] ?? ''}'),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
              ],
              if (_selectedView == 'domains')
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Domain-wise Progress', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 12),
                        _improvementRow('GM', (baseline['gm'] ?? 0) as int, (current['gm'] ?? 0) as int, (improvements['gm'] ?? 0) as int),
                        _improvementRow('FM', (baseline['fm'] ?? 0) as int, (current['fm'] ?? 0) as int, (improvements['fm'] ?? 0) as int),
                        _improvementRow('LC', (baseline['lc'] ?? 0) as int, (current['lc'] ?? 0) as int, (improvements['lc'] ?? 0) as int),
                        _improvementRow('COG', (baseline['cog'] ?? 0) as int, (current['cog'] ?? 0) as int, (improvements['cog'] ?? 0) as int),
                        _improvementRow('SE', (baseline['se'] ?? 0) as int, (current['se'] ?? 0) as int, (improvements['se'] ?? 0) as int),
                      ],
                    ),
                  ),
                ),
              if (_selectedView == 'milestones') ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Milestones Achieved (${milestones.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 10),
                        if (milestones.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: Text('No milestones recorded yet')),
                          )
                        else
                          ...milestones.map((m) {
                            final row = Map<String, dynamic>.from(m as Map);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.emoji_events_outlined),
                              title: Text('${row['name'] ?? 'Milestone'}'),
                              subtitle: Text('Domain: ${row['domain'] ?? 'General'}'),
                              trailing: Text('${row['date'] ?? ''}'),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _showAddMilestoneDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Milestone'),
                  ),
                ),
              ],
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 8),
                        ..._history.map((h) {
                          final row = Map<String, dynamic>.from(h as Map);
                          final awwCode = (row['aww_code'] ?? '').toString().trim();
                          final completionText = 'Completion: ${row['completion_rate']}%';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Improvement: ${row['overall_improvement']}'),
                            subtitle: Text(
                              awwCode.isNotEmpty
                                  ? 'AWW Code: $awwCode\n$completionText'
                                  : completionText,
                            ),
                            isThreeLine: awwCode.isNotEmpty,
                            trailing: Text('${row['date'] ?? ''}'),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAddMilestoneDialog() {
    final controller = TextEditingController();
    var selectedDomain = 'GM';
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Milestone'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Milestone name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedDomain,
                items: const ['GM', 'FM', 'LC', 'COG', 'SE']
                    .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => selectedDomain = v ?? 'GM',
                decoration: const InputDecoration(
                  labelText: 'Domain',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                await ReferralFlowApiService.addMilestone(widget.childId, name, selectedDomain);
                if (!mounted) return;
                Navigator.pop(context);
                _loadData();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}
