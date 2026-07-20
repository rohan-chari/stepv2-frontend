import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/notification_service.dart';

// Spec §7/§8 (contract §9.2): the two daily-reward reminder types deep-link to
// the daily-reward screen; RACE_ENDING_SOON deep-links to the race like every
// other race-scoped push. All three are additive types — older apps that don't
// know them fall through to a null route (alert still shows, no deep-link).
void main() {
  final service = NotificationService();

  test('RACE_ENDING_SOON routes to race detail', () {
    expect(
      service.routeFromType('RACE_ENDING_SOON'),
      NotificationRoute.raceDetail,
    );
  });

  test('RACE_ENDING_SOON resolves to race detail with a raceId param', () {
    expect(
      service.resolveRoute('RACE_ENDING_SOON', {'raceId': 'r1'}),
      NotificationRoute.raceDetail,
    );
  });

  test('both daily-reward reminder slots route to the daily-reward screen', () {
    expect(
      service.routeFromType('DAILY_REWARD_REMINDER_17'),
      NotificationRoute.dailyReward,
    );
    expect(
      service.routeFromType('DAILY_REWARD_REMINDER_21'),
      NotificationRoute.dailyReward,
    );
  });

  test('existing push types keep their routing', () {
    expect(service.routeFromType('RACE_STARTED'), NotificationRoute.raceDetail);
    expect(service.routeFromType('RACE_CANCELLED'), NotificationRoute.races);
    expect(
      service.routeFromType('FRIEND_REQUEST_SENT'),
      NotificationRoute.friends,
    );
    expect(
      service.routeFromType('TOURNAMENT_CHAMPION'),
      NotificationRoute.tournamentDetail,
    );
    expect(service.routeFromType('SOMETHING_UNKNOWN'), isNull);
    // Old-client behavior: an app that predates these types returns null and
    // simply shows the alert without deep-linking.
    expect(service.routeFromType(null), isNull);
  });
}
