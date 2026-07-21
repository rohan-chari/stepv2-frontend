import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
