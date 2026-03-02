import 'package:dio/dio.dart';
import 'package:my_first_app/core/constants/app_constants.dart';

import '../models/activity.dart';
import '../models/referral.dart';
import 'auth_service.dart';

class ReferralFlowApiService {
  ReferralFlowApiService._();

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: 'application/json',
    ),
  );

  static Future<Referral> createReferral(Map<String, dynamic> riskData) async {
    try {
      final timelinePayload = Map<String, dynamic>.from(riskData);
      timelinePayload.putIfAbsent('screening_date', () => DateTime.now().toIso8601String().split('T').first);
      final response = await _dio.post('/api/referrals/create', data: timelinePayload);
      return Referral.fromJson(Map<String, dynamic>.from(response.data as Map));
    } catch (_) {
      final response = await _dio.post('/api/referrals', data: riskData);
      return Referral.fromJson(Map<String, dynamic>.from(response.data as Map));
    }
  }

  static Future<Referral> getReferral(int referralId) async {
    final response = await _dio.get('/api/referrals/$referralId');
    return Referral.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  static Future<List<Activity>> getReferralActivities(
    int referralId, {
    String? targetRole,
  }) async {
    final response = await _dio.get(
      '/api/referrals/$referralId/activities',
      queryParameters: {
        if (targetRole != null && targetRole.trim().isNotEmpty)
          'target_role': targetRole,
      },
    );
    final rows = (response.data as List<dynamic>)
        .whereType<Map>()
        .map((e) => Activity.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return rows;
  }

  static Future<Map<String, dynamic>> completeActivity(
    int activityId, {
    String? notes,
    int? difficulty,
    String reportedBy = 'CAREGIVER',
  }) async {
    final response = await _dio.post(
      '/api/activities/$activityId/complete',
      data: {
        'notes': notes,
        'difficulty': difficulty,
        'reported_by': reportedBy,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> getReferralProgress(int referralId) async {
    final response = await _dio.get('/api/referrals/$referralId/progress');
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> calculateImprovement(
    String childId, {
    int? referralId,
  }) async {
    final awcCode = (await AuthService().getLoggedInAwcCode())?.trim();
    final response = await _dio.post(
      '/api/improvement/calculate/$childId',
      data: {
        if (referralId != null) 'referral_id': referralId,
        if (awcCode != null && awcCode.isNotEmpty) 'awc_code': awcCode,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> getImprovementSummary(String childId) async {
    final response = await _dio.get('/api/improvement/summary/$childId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> getRadarData(String childId) async {
    final response = await _dio.get('/api/improvement/radar/$childId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<void> addMilestone(
    String childId,
    String name,
    String domain, {
    String? notes,
  }) async {
    await _dio.post(
      '/api/improvement/milestone/$childId',
      data: {
        'milestone_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'milestone_name': name,
        'domain': domain,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes,
      },
    );
  }

  static Future<List<dynamic>> getMilestones(String childId, {int days = 30}) async {
    final response = await _dio.get(
      '/api/improvement/milestones/$childId',
      queryParameters: {'days': days},
    );
    return List<dynamic>.from(response.data as List);
  }

  static Future<List<dynamic>> getImprovementHistory(String childId, {int limit = 5}) async {
    final awcCode = (await AuthService().getLoggedInAwcCode())?.trim();
    final response = await _dio.get(
      '/api/improvement/history/$childId',
      queryParameters: {
        'limit': limit,
        if (awcCode != null && awcCode.isNotEmpty) 'awc_code': awcCode,
      },
    );
    return List<dynamic>.from(response.data as List);
  }

  static Future<Map<String, dynamic>> createTimelineReferral(Map<String, dynamic> riskData) async {
    final response = await _dio.post('/api/referrals/create', data: riskData);
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> getReferralTimeline(int referralId) async {
    final response = await _dio.get('/api/referrals/$referralId/timeline');
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> completeTimelineActivity(int referralId, int activityId) async {
    final response = await _dio.post('/api/referrals/$referralId/complete-activity/$activityId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> completeReview(
    int referralId,
    int reviewId, {
    String? notes,
  }) async {
    final response = await _dio.post(
      '/api/referrals/$referralId/complete-review/$reviewId',
      data: {
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> markSpecialistVisit(
    int referralId, {
    String? visitDateIso,
  }) async {
    final response = await _dio.post(
      '/api/referrals/$referralId/mark-specialist-visit',
      data: {
        if (visitDateIso != null && visitDateIso.trim().isNotEmpty) 'visit_date': visitDateIso,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> runEscalationCheck() async {
    final response = await _dio.post('/api/referrals/run-escalation-check');
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<List<dynamic>> getEscalatedReferrals({int limit = 100}) async {
    final response = await _dio.get('/api/referrals/timeline/escalations', queryParameters: {'limit': limit});
    return List<dynamic>.from(response.data as List);
  }
}
