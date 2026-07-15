import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/notification_service.dart';

// TR-680s (contract §11): the new team push types deep-link into the race
// like the other race pushes. TEAM_LEAD_CHANGE ("Swift Capys just took the
// lead!") and TEAM_SLACKER_NUDGE both carry a raceId.
void main() {
  final service = NotificationService();

  test('TEAM_LEAD_CHANGE routes to race detail', () {
    expect(
      service.routeFromType('TEAM_LEAD_CHANGE'),
      NotificationRoute.raceDetail,
    );
  });

  test('TEAM_SLACKER_NUDGE routes to race detail', () {
    expect(
      service.routeFromType('TEAM_SLACKER_NUDGE'),
      NotificationRoute.raceDetail,
    );
  });

  test('TEAM_FINAL_STRETCH routes to race detail', () {
    expect(
      service.routeFromType('TEAM_FINAL_STRETCH'),
      NotificationRoute.raceDetail,
    );
  });

  test('TEAM_RACE_SCHEDULED_UNEVEN routes to race detail (creator fixes the '
      'lobby there)', () {
    expect(
      service.routeFromType('TEAM_RACE_SCHEDULED_UNEVEN'),
      NotificationRoute.raceDetail,
    );
  });

  test('existing race push types keep their routing', () {
    expect(
      service.routeFromType('RACE_STARTED'),
      NotificationRoute.raceDetail,
    );
    expect(service.routeFromType('RACE_CANCELLED'), NotificationRoute.races);
    expect(service.routeFromType('SOMETHING_UNKNOWN'), isNull);
  });
}
