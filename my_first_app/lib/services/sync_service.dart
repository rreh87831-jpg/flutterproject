import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:my_first_app/models/child_model.dart';
import 'package:my_first_app/models/referral_model.dart';
import 'package:my_first_app/models/screening_model.dart';
import 'api_service.dart';
import 'local_db_service.dart';

class SyncService {
  final Connectivity _connectivity = Connectivity();
  final APIService _apiService = APIService();
  final LocalDBService _localDBService;
  static final RegExp _awcDemoPattern = RegExp(r'^(AWW|AWS)_DEMO_(\d{3,4})$');
  static final RegExp _awcDemoReversedPattern = RegExp(
    r'^DEMO_(AWW|AWS)_(\d{3,4})$',
  );

  SyncService(this._localDBService);

  String _normalizeAwcCode(String value) {
    final raw = value.trim().toUpperCase();
    final direct = _awcDemoPattern.firstMatch(raw);
    if (direct != null) {
      return 'AWW_DEMO_${direct.group(2)}';
    }
    final reversed = _awcDemoReversedPattern.firstMatch(raw);
    if (reversed != null) {
      return 'AWW_DEMO_${reversed.group(2)}';
    }
    return raw;
  }

  bool _isCanonicalAwc(String value) => _awcDemoPattern.hasMatch(value);

  bool _hasAnyConnectivity(dynamic value) {
    if (value is ConnectivityResult) {
      return value != ConnectivityResult.none;
    }
    if (value is List<ConnectivityResult>) {
      return value.any((r) => r != ConnectivityResult.none);
    }
    return false;
  }

  /// Check internet connection
  Future<bool> hasInternetConnection() async {
    final result = await _connectivity.checkConnectivity();
    return _hasAnyConnectivity(result);
  }

  /// Sync all pending A/B data (children + screenings + referrals).
  Future<void> syncPendingData() async {
    if (!await hasInternetConnection()) {
      print('No internet connection. Sync skipped.');
      return;
    }

    try {
      // Child registration is local-only. Clear any legacy unsynced markers.
      List<ChildModel> unsyncedChildren = _localDBService.getUnsyncedChildren();
      for (var child in unsyncedChildren) {
        await _localDBService.markChildSynced(child.childId);
      }

      List<ScreeningModel> unsyncedScreenings = _localDBService.getUnsyncedScreenings();

      for (var screening in unsyncedScreenings) {
        try {
          final child = _localDBService.getChild(screening.childId);
          final payload = screening.toJson();
          payload['assessment_cycle'] = 'Baseline';
          final screeningAwc = _normalizeAwcCode(screening.awwId);
          final childAwc = _normalizeAwcCode(child?.awcCode ?? '');
          final awcForSync = _isCanonicalAwc(screeningAwc)
              ? screeningAwc
              : (_isCanonicalAwc(childAwc) ? childAwc : screeningAwc);
          payload['awc_code'] = awcForSync;
          payload['awc_id'] = awcForSync;
          payload['aww_id'] = awcForSync;
          if (child != null) {
            payload['sector_id'] = '';
            payload['mandal'] = child.mandal;
            payload['district'] = child.district;
            payload['gender'] = child.gender;
          }
          await _apiService.submitScreening(payload);

          // Update screening as synced
          ScreeningModel syncedScreening = screening.copyWith(
            submittedAt: DateTime.now(),
          );
          await _localDBService.saveScreening(syncedScreening);

          print('Screening ${screening.screeningId} synced successfully.');
        } catch (e) {
          print('Error syncing screening ${screening.screeningId}: $e');
        }
      }

      // Sync unsynced referrals
      List<ReferralModel> unsyncedReferrals = _localDBService.getUnsyncedReferrals();
      for (var referral in unsyncedReferrals) {
        try {
          await _apiService.createReferral(referral.toJson());
          final syncedReferral = referral.copyWith(
            metadata: {
              ...(referral.metadata ?? <String, dynamic>{}),
              'sync_status': 'synced',
            },
          );
          await _localDBService.saveReferral(syncedReferral);
          print('Referral ${referral.referralId} synced successfully.');
        } catch (e) {
          print('Error syncing referral ${referral.referralId}: $e');
        }
      }
    } catch (e) {
      print('Sync error: $e');
    }
  }

  /// Backward compatibility wrapper.
  Future<void> syncPendingScreenings() => syncPendingData();

  /// Listen for connectivity changes and auto-sync
  void listenForConnectivityChanges() {
    _connectivity.onConnectivityChanged.listen((result) async {
      if (_hasAnyConnectivity(result)) {
        print('Internet restored. Starting sync...');
        await syncPendingData();
      }
    });
  }
}
