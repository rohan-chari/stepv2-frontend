import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// TR-701: New clients advertise the `team_races` capability in the
// X-Client-Features header (same pattern as the CHARACTER slot token) so the
// backend can safely surface team races to this build.
void main() {
  test('TR-701: clientFeaturesHeader advertises the team_races token', () {
    final tokens = BackendApiService.clientFeaturesHeader.split(',');
    expect(tokens, contains('team_races'));
  });

  test('TR-701: existing feature tokens are preserved alongside team_races', () {
    final tokens = BackendApiService.clientFeaturesHeader.split(',');
    expect(tokens, contains('characters'));
    expect(tokens, contains('jammer'));
    expect(tokens, contains('spinpowerups'));
  });
}
