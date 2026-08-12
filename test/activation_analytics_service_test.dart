import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _AnalyticsApi extends BackendApiService {
  bool fail = false;
  List<Map<String, dynamic>>? sent;

  @override
  Future<void> sendActivationEvents({
    required String identityToken,
    required List<Map<String, dynamic>> events,
  }) async {
    if (fail) throw const ApiException('offline');
    sent = events;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Step Tracker',
      packageName: 'com.example.steptracker',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('queue is bounded and strips non-allowlisted context', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ActivationAnalyticsService(
      backendApiService: _AnalyticsApi(),
    );
    for (var i = 0; i < 55; i++) {
      await service.record(
        'public_browser_opened',
        context: {'source': 'races', 'raceId': 'secret-$i'},
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final events = jsonDecode(prefs.getString('activation_events_v1')!) as List;
    expect(events, hasLength(ActivationAnalyticsService.maxQueuedEvents));
    expect((events.first as Map)['context'], {'source': 'races'});
  });

  test('next-race analytics keep only validated UUID identifiers', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ActivationAnalyticsService(
      backendApiService: _AnalyticsApi(),
    );

    await service.record(
      'open_race_join_succeeded',
      context: {
        'source': 'next_race',
        'race_id': '550e8400-e29b-41d4-a716-446655440000',
        'source_race_id': 'not-a-uuid',
      },
    );

    final prefs = await SharedPreferences.getInstance();
    final events = jsonDecode(prefs.getString('activation_events_v1')!) as List;
    expect((events.single as Map)['context'], {
      'source': 'next_race',
      'race_id': '550e8400-e29b-41d4-a716-446655440000',
    });
  });

  test(
    'suggested-race analytics retain only bounded contract context',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = ActivationAnalyticsService(
        backendApiService: _AnalyticsApi(),
      );

      await service.record(
        'home_suggested_races_shown',
        context: const {
          'featured_count': '2',
          'public_count': '4',
          'tournament_count': '4',
        },
      );
      await service.record(
        'home_suggested_race_tapped',
        context: const {
          'suggestion_kind': 'TOURNAMENT',
          'suggestion_id': '550e8400-e29b-41d4-a716-446655440000',
          'position': '9',
        },
      );

      final prefs = await SharedPreferences.getInstance();
      final events =
          jsonDecode(prefs.getString('activation_events_v1')!) as List;
      expect((events[0] as Map)['context'], {
        'featured_count': '2',
        'public_count': '4',
        'tournament_count': '4',
      });
      expect((events[1] as Map)['context'], {
        'suggestion_kind': 'TOURNAMENT',
        'suggestion_id': '550e8400-e29b-41d4-a716-446655440000',
        'position': '9',
      });
    },
  );

  test(
    'failed flush retains events and successful retry clears them',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = _AnalyticsApi()..fail = true;
      final service = ActivationAnalyticsService(backendApiService: api);
      await service.record('daily_opened');
      await service.flush('token');
      var prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('activation_events_v1')!) as List,
        isNotEmpty,
      );

      api.fail = false;
      await service.flush('token');
      prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('activation_events_v1')!) as List,
        isEmpty,
      );
      expect(api.sent, hasLength(1));
    },
  );
}
