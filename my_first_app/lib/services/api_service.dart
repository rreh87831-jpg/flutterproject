import 'package:dio/dio.dart';
import 'package:my_first_app/core/constants/app_constants.dart';
import 'package:my_first_app/models/child_model.dart';
import 'auth_service.dart';

class APIService {
  late Dio _dio;
  final AuthService _authService = AuthService();

  APIService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: AppConstants.apiTimeout,
        receiveTimeout: AppConstants.apiTimeout,
        contentType: 'application/json',
      ),
    );

    // Add interceptor for auth token
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          String? token = await _authService.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            bool refreshed = await _authService.refreshToken();
            if (refreshed) {
              return handler.resolve(await _retry(error.requestOptions));
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  String _formatDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    final responseData = error.response?.data;

    String? detail;
    if (responseData is Map<String, dynamic>) {
      detail = responseData['detail']?.toString() ??
          responseData['message']?.toString() ??
          responseData['error']?.toString();
    } else if (responseData is String && responseData.trim().isNotEmpty) {
      detail = responseData.trim();
    }

    if (statusCode != null && detail != null && detail.isNotEmpty) {
      return 'HTTP $statusCode: $detail';
    }
    if (statusCode != null) {
      return 'HTTP $statusCode';
    }
    return error.message ?? 'Network error';
  }

  List<Map<String, dynamic>> _dedupeChildrenById(List<dynamic> rawItems) {
    final deduped = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    for (final item in rawItems) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final childId = (row['child_id'] ?? '').toString().trim();
      if (childId.isEmpty) continue;
      final key = childId.toLowerCase();
      if (seenIds.contains(key)) continue;
      seenIds.add(key);
      deduped.add(row);
    }
    return deduped;
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions) async {
    final options = Options(
      method: requestOptions.method,
      headers: requestOptions.headers,
    );
    return _dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }

  /// Login and return JWT token from backend.
  /// Supported response shapes:
  /// { "token": "..." } OR { "access_token": "..." } OR { "data": { "token": "..." } }
  Future<String> login(String awcCode, String password) async {
    try {
      final response = await _dio.post(
        AppConstants.loginEndpoint,
        data: {
          'awc_code': awcCode.trim().toUpperCase(),
          'password': password,
        },
      );
      final body = response.data;
      if (body is Map<String, dynamic>) {
        final directToken = body['token'] ?? body['access_token'];
        if (directToken is String && directToken.isNotEmpty) {
          return directToken;
        }
        final nested = body['data'];
        if (nested is Map<String, dynamic>) {
          final nestedToken = nested['token'] ?? nested['access_token'];
          if (nestedToken is String && nestedToken.isNotEmpty) {
            return nestedToken;
          }
        }
      }
      throw Exception('Token not present in login response');
    } on DioException catch (e) {
      throw Exception('Login failed: ${e.message}');
    }
  }

  /// Fetch AWW profile (district/mandal/name) for the logged-in AWC code.
  Future<Map<String, dynamic>?> getAwwProfile(String awcCode) async {
    final normalizedAwcCode = awcCode.trim().toUpperCase();
    if (normalizedAwcCode.isEmpty) {
      return null;
    }
    try {
      final response = await _dio.get(
        '/auth/profile',
        queryParameters: {'awc_code': normalizedAwcCode},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return null;
      }
      final profile = data['profile'];
      if (profile is Map<String, dynamic>) {
        return profile;
      }
      if (profile is Map) {
        return Map<String, dynamic>.from(profile);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw Exception('AWW profile fetch failed: ${_formatDioError(e)}');
    }
  }

  /// Register AWW (Anganwadi Worker) to PostgreSQL database
  Future<Map<String, dynamic>> registerAWW(
    Map<String, dynamic> awwData,
  ) async {
    try {
      final response = await _dio.post(
        '/auth/register',  // Backend endpoint for AWW registration
        data: awwData,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('AWW registration failed: ${_formatDioError(e)}');
    }
  }

  /// Submit screening
  Future<Map<String, dynamic>> submitScreening(
    Map<String, dynamic> screeningData,
  ) async {
    try {
      final response = await _dio.post(
        AppConstants.screeningEndpoint,
        data: screeningData,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Screening submission failed: ${e.message}');
    }
  }

  /// Predict domain delays without creating referral or saving screening.
  Future<Map<String, dynamic>> predictDomainDelays(
    Map<String, dynamic> screeningData,
  ) async {
    try {
      final response = await _dio.post(
        '/screening/predict-domain-delays',
        data: screeningData,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw Exception('Unexpected prediction response format');
    } on DioException catch (e) {
      throw Exception(
        'Domain delay prediction failed: ${_formatDioError(e)}',
      );
    }
  }

  /// Predict nutrition risk from nutrition form features.
  Future<Map<String, dynamic>> predictNutritionRisk(
    Map<String, dynamic> nutritionData,
  ) async {
    try {
      final response = await _dio.post(
        '/nutrition/predict-risk',
        data: nutritionData,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw Exception('Unexpected nutrition prediction response format');
    } on DioException catch (e) {
      throw Exception(
        'Nutrition risk prediction failed: ${_formatDioError(e)}',
      );
    }
  }

  /// Save nutrition assessment result table values.
  Future<Map<String, dynamic>> submitNutritionResult(
    Map<String, dynamic> nutritionResultData,
  ) async {
    try {
      final response = await _dio.post(
        '/nutrition/submit',
        data: nutritionResultData,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw Exception('Unexpected nutrition submit response format');
    } on DioException catch (e) {
      throw Exception(
        'Nutrition result save failed: ${_formatDioError(e)}',
      );
    }
  }

  /// Register child profile in backend source DB.
  Future<Map<String, dynamic>> registerChild(
    ChildModel child, {
    String assessmentCycle = 'Baseline',
  }) async {
    final dobIso = child.dateOfBirth.toIso8601String().split('T')[0];
    final fastApiPayload = {
      'child_id': child.childId,
      'date_of_birth': dobIso,
      'dob': dobIso,
      'gender': child.gender,
      'awc_code': child.awcCode,
      'mandal': child.mandal,
      'district': child.district,
      'assessment_cycle': assessmentCycle,
    };

    try {
      final response = await _dio.post(
        AppConstants.childRegisterEndpoint,
        data: fastApiPayload,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Child registration sync failed: ${_formatDioError(e)}');
    }
  }

  /// Get child details
  Future<Map<String, dynamic>> getChildDetails(String childId) async {
    try {
      final response = await _dio.get(
        '${AppConstants.childDetailEndpoint}/$childId',
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Failed to fetch child details: ${e.message}');
    }
  }

  /// Fetch registered children count from backend child_profile.
  Future<int> getRegisteredChildrenCount({
    int limit = 1000,
    String? awcCode,
  }) async {
    final normalizedAwcCode = awcCode?.trim().toUpperCase();
    final queryParameters = <String, dynamic>{
      'limit': limit,
      if (normalizedAwcCode != null && normalizedAwcCode.isNotEmpty)
        'awc_code': normalizedAwcCode,
    };
    try {
      final response = await _dio.get(
        AppConstants.childListEndpoint,
        queryParameters: queryParameters,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final items = data['items'];
        if (items is List) {
          return _dedupeChildrenById(items).length;
        }
        final count = data['count'];
        if (count is num) {
          return count.toInt();
        }
      }
      throw Exception('Unexpected children list response format');
    } on DioException catch (e) {
      throw Exception('Failed to fetch child count: ${_formatDioError(e)}');
    }
  }

  /// Fetch registered children list from backend child_profile.
  Future<List<Map<String, dynamic>>> getRegisteredChildren({
    int limit = 1000,
    String? awcCode,
  }) async {
    final normalizedAwcCode = awcCode?.trim().toUpperCase();
    final queryParameters = <String, dynamic>{
      'limit': limit,
      if (normalizedAwcCode != null && normalizedAwcCode.isNotEmpty)
        'awc_code': normalizedAwcCode,
    };
    try {
      final response = await _dio.get(
        AppConstants.childListEndpoint,
        queryParameters: queryParameters,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected children list response format');
      }
      final items = data['items'];
      if (items is! List) {
        return const <Map<String, dynamic>>[];
      }
      return _dedupeChildrenById(items);
    } on DioException catch (e) {
      throw Exception('Failed to fetch children list: ${_formatDioError(e)}');
    }
  }

  /// Delete one child from backend child_profile (and related records when applicable).
  Future<Map<String, dynamic>> deleteChild(
    String childId, {
    String? awcCode,
  }) async {
    final normalizedChildId = childId.trim();
    if (normalizedChildId.isEmpty) {
      throw Exception('child_id is required');
    }
    final normalizedAwcCode = awcCode?.trim().toUpperCase();
    try {
      final response = await _dio.delete(
        '/children/${Uri.encodeComponent(normalizedChildId)}',
        queryParameters: {
          if (normalizedAwcCode != null && normalizedAwcCode.isNotEmpty)
            'awc_code': normalizedAwcCode,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return {'status': 'ok'};
    } on DioException catch (e) {
      throw Exception('Failed to delete child: ${_formatDioError(e)}');
    }
  }

  /// Create referral
  Future<Map<String, dynamic>> createReferral(
    Map<String, dynamic> referralData,
  ) async {
    try {
      final response = await _dio.post(
        AppConstants.referralEndpoint,
        data: referralData,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Referral creation failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> generateProblemBInterventionPlan(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(
        '/problem-b/intervention-plan',
        data: payload,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Problem B intervention generation failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getProblemBTrend({
    required int baselineDelay,
    required int followupDelay,
  }) async {
    try {
      final response = await _dio.post(
        '/problem-b/trend',
        data: {
          'baseline_delay': baselineDelay,
          'followup_delay': followupDelay,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Problem B trend calculation failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> adjustProblemBIntensity({
    required String currentIntensity,
    required String trend,
    required int delayReduction,
  }) async {
    try {
      final response = await _dio.post(
        '/problem-b/adjust-intensity',
        data: {
          'current_intensity': currentIntensity,
          'trend': trend,
          'delay_reduction': delayReduction,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Problem B intensity adjustment failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getProblemBRules() async {
    try {
      final response = await _dio.get('/problem-b/rules');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Problem B rules fetch failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> generateProblemBActivities(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(
        '/problem-b/activities/generate',
        data: payload,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Problem B activity generation failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getProblemBActivities(String childId) async {
    try {
      final response = await _dio.get('/problem-b/activities/$childId');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Problem B activities fetch failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> markProblemBActivityStatus({
    required String childId,
    required String activityId,
    required String status,
  }) async {
    try {
      final response = await _dio.post(
        '/problem-b/activities/mark-status',
        data: {
          'child_id': childId,
          'activity_id': activityId,
          'status': status,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Problem B activity status update failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getProblemBCompliance(String childId) async {
    try {
      final response = await _dio.get('/problem-b/compliance/$childId');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Problem B compliance fetch failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> createAppointment({
    required String referralId,
    required String childId,
    required String scheduledDate,
    required String appointmentType,
    String notes = '',
  }) async {
    try {
      final response = await _dio.post(
        '/appointments',
        data: {
          'referral_id': referralId,
          'child_id': childId,
          'scheduled_date': scheduledDate,
          'appointment_type': appointmentType,
          'notes': notes,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Appointment create failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> updateAppointmentStatus({
    required String appointmentId,
    required String status,
    String notes = '',
  }) async {
    try {
      final response = await _dio.put(
        '/appointments/$appointmentId',
        data: {'status': status, 'notes': notes},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Appointment update failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getReferralAppointments(
    String referralId,
  ) async {
    try {
      final response = await _dio.get('/referral/$referralId/appointments');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Appointment fetch failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> updateReferralStatus({
    required String referralId,
    required String status,
    String? appointmentDate,
    String? completionDate,
    String? workerId,
  }) async {
    final candidates = <String>[
      _statusForBackend(status),
      status,
      _statusForLegacy(status),
    ].where((e) => e.trim().isNotEmpty).toSet().toList();

    DioException? lastError;
    for (final candidate in candidates) {
      try {
        final response = await _dio.post(
          '/referral/$referralId/status',
          data: {
            'status': candidate,
            'appointment_date': ?appointmentDate,
            'completion_date': ?completionDate,
            'worker_id': ?workerId,
          },
        );
        return response.data as Map<String, dynamic>;
      } on DioException catch (e) {
        lastError = e;
      }
    }

    // Fallback for older backend variants.
    try {
      final response = await _dio.post(
        '/referral/status',
        data: {
          'referral_id': referralId,
          'status': _statusForLegacy(status),
          'appointment_date': ?appointmentDate,
          'completion_date': ?completionDate,
          'worker_id': ?workerId,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      lastError = e;
    }

    try {
      final response = await _dio.put(
        '/update_referral_status',
        queryParameters: {
          'referral_id': referralId,
          'status': _statusForLegacy(status),
          'appointment_date': ?appointmentDate,
          'completion_date': ?completionDate,
          'worker_id': ?workerId,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      lastError = e;
    }

    try {
      final response = await _dio.post(
        '/update_referral_status',
        queryParameters: {
          'referral_id': referralId,
          'status': _statusForLegacy(status),
          'appointment_date': ?appointmentDate,
          'completion_date': ?completionDate,
          'worker_id': ?workerId,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      lastError = e;
    }

    final code = lastError.response?.statusCode;
    throw Exception(
      'Referral status update failed: ${lastError.message} (HTTP $code)',
    );
  }

  Future<Map<String, dynamic>> escalateReferral({
    required String referralId,
    String? workerId,
  }) async {
    try {
      final response = await _dio.post(
        '/referral/$referralId/escalate',
        data: {
          'worker_id': ?workerId,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Referral escalation failed: ${e.message}');
    }
  }

  String _statusForBackend(String status) {
    switch (status.trim().toUpperCase()) {
      case 'SCHEDULED':
        return 'Appointment Scheduled';
      case 'VISITED':
        return 'Under Treatment';
      case 'COMPLETED':
        return 'Completed';
      case 'MISSED':
        return 'Missed';
      default:
        return 'Pending';
    }
  }

  String _statusForLegacy(String status) {
    switch (status.trim().toUpperCase()) {
      case 'SCHEDULED':
        return 'SCHEDULED';
      case 'VISITED':
        return 'UNDER_TREATMENT';
      case 'COMPLETED':
        return 'COMPLETED';
      case 'MISSED':
        return 'MISSED';
      default:
        return 'PENDING';
    }
  }

  Future<Map<String, dynamic>> getReferralByChild(String childId) async {
    try {
      final response = await _dio.get('/referral/by-child/$childId');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Referral fetch failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getReferralDetailsByChild(String childId) async {
    try {
      final response = await _dio.get('/referral/child/$childId/details');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Referral details fetch failed: ${e.message}');
    }
  }

  Future<List<Map<String, dynamic>>> getReferralList({
    int limit = 200,
    String? awwId,
  }) async {
    final normalizedAwwId = awwId?.trim().toUpperCase();
    final queryParameters = <String, dynamic>{
      'limit': limit,
      if (normalizedAwwId != null && normalizedAwwId.isNotEmpty)
        'aww_id': normalizedAwwId,
    };
    try {
      final response = await _dio.get(
        '/referral/list',
        queryParameters: queryParameters,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return const <Map<String, dynamic>>[];
      }
      final items = data['items'];
      if (items is! List) {
        return const <Map<String, dynamic>>[];
      }
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on DioException catch (e) {
      throw Exception('Referral list fetch failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> resetProblemBFrequency({
    required String childId,
    required String frequencyType,
  }) async {
    try {
      final response = await _dio.post(
        '/problem-b/activities/reset-frequency',
        data: {'child_id': childId, 'frequency_type': frequencyType},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Problem B frequency reset failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> createInterventionPhase({
    required String childId,
    required String domain,
    required String riskLevel,
    required int baselineDelayMonths,
    required int ageMonths,
  }) async {
    try {
      final response = await _dio.post(
        '/intervention/plan/create',
        data: {
          'child_id': childId,
          'domain': domain,
          'risk_level': riskLevel,
          'baseline_delay_months': baselineDelayMonths,
          'age_months': ageMonths,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Intervention phase create failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> logInterventionProgress({
    required String phaseId,
    required double currentDelayMonths,
    required int awwCompleted,
    required int caregiverCompleted,
    String notes = '',
  }) async {
    try {
      final response = await _dio.post(
        '/intervention/$phaseId/progress/log',
        data: {
          'phase_id': phaseId,
          'current_delay_months': currentDelayMonths,
          'aww_completed': awwCompleted,
          'caregiver_completed': caregiverCompleted,
          'notes': notes,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Intervention progress log failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getInterventionActivities(String phaseId) async {
    try {
      final response = await _dio.get('/intervention/$phaseId/activities');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Intervention activities fetch failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> getInterventionHistory(String phaseId) async {
    try {
      final response = await _dio.get('/intervention/$phaseId/history');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Intervention history fetch failed: ${e.message}');
    }
  }
}
