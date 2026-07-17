import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/notification_service.dart';

// Spec §8/§9/§10: the new TOURNAMENT_* push types deep-link into the bracket by
// default; TOURNAMENT_STARTED / TOURNAMENT_ROUND_STARTED re-point to the
// player's specific matchup race when a raceId rides the params. Unknown types
// fall through to null (old apps just show the alert — the #1 rule).
void main() {
  final service = NotificationService();

  group('routeFromType — base mapping', () {
    const tournamentTypes = [
      'TOURNAMENT_INVITE_SENT',
      'TOURNAMENT_STARTED',
      'TOURNAMENT_ROUND_STARTED',
      'TOURNAMENT_MATCHUP_WON',
      'TOURNAMENT_ELIMINATED',
      'TOURNAMENT_CHAMPION',
      'TOURNAMENT_COMPLETED',
      'TOURNAMENT_CANCELLED',
    ];

    test('every TOURNAMENT_* type routes to the bracket by default', () {
      for (final type in tournamentTypes) {
        expect(
          service.routeFromType(type),
          NotificationRoute.tournamentDetail,
          reason: type,
        );
      }
    });

    test('unknown type falls through to null', () {
      expect(service.routeFromType('TOURNAMENT_WAT'), isNull);
      expect(service.routeFromType(null), isNull);
    });

    test('existing race routing is untouched', () {
      expect(service.routeFromType('RACE_STARTED'), NotificationRoute.raceDetail);
      expect(service.routeFromType('RACE_CANCELLED'), NotificationRoute.races);
    });
  });

  group('resolveRoute — matchup deep-linking', () {
    test('STARTED with a raceId opens the matchup race', () {
      expect(
        service.resolveRoute('TOURNAMENT_STARTED', {'raceId': 'r1'}),
        NotificationRoute.raceDetail,
      );
      expect(
        service.resolveRoute('TOURNAMENT_ROUND_STARTED', {
          'raceId': 'r1',
          'tournamentId': 't1',
        }),
        NotificationRoute.raceDetail,
      );
    });

    test('STARTED without a raceId falls back to the bracket', () {
      expect(
        service.resolveRoute('TOURNAMENT_STARTED', {'tournamentId': 't1'}),
        NotificationRoute.tournamentDetail,
      );
    });

    test('a non-matchup tournament push ignores any raceId and opens bracket', () {
      expect(
        service.resolveRoute('TOURNAMENT_CHAMPION', {
          'tournamentId': 't1',
          'raceId': 'r1',
        }),
        NotificationRoute.tournamentDetail,
      );
    });

    test('unknown type still resolves to null', () {
      expect(service.resolveRoute('WAT', {'raceId': 'r1'}), isNull);
    });
  });
}
