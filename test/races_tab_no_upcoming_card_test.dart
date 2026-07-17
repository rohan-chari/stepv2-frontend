import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/widgets/featured_race_card.dart';

// Item 5: the featured row no longer renders the upcoming/opt-in "next race"
// card, even when the backend still attaches an `upcoming` payload to a featured
// race (old clients keep rendering it; this build drops it). Auto-join covers
// the next daily/weekly instead.

Future<void> _noop() async {}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 500,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Map<String, dynamic> _featuredRaceWithUpcoming() => {
      'raceId': 'fr1',
      'name': 'Daily 10K',
      'seedKind': 'DAILY_10K',
      'endsAt': DateTime.now()
          .add(const Duration(hours: 5))
          .toUtc()
          .toIso8601String(),
      'participantCount': 12,
      'finishReward': {'pool': 500, 'paidPlaces': 3},
      // Backend still sends the pre-registerable next race — must be ignored.
      'upcoming': {
        'raceId': 'fr1-next',
        'scheduledStartAt': DateTime.now()
            .add(const Duration(hours: 20))
            .toUtc()
            .toIso8601String(),
        'endsAt': DateTime.now()
            .add(const Duration(days: 1, hours: 5))
            .toUtc()
            .toIso8601String(),
        'participantCount': 2,
        'isFull': false,
      },
    };

Future<void> _pump(WidgetTester tester,
    {required List<Map<String, dynamic>> featuredRaces}) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: auth,
          racesState: Loadable.success(
            const {'active': [], 'pending': [], 'completed': []},
          ),
          friendsSteps: const [],
          featuredRaces: featuredRaces,
          featuredTournaments: const [],
          onRacesChanged: _noop,
          onJoinFeaturedTournament: (_) async => true,
          displayName: 'Trail Walker',
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('featured race with an `upcoming` payload shows only ONE card',
      (tester) async {
    await _pump(tester, featuredRaces: [_featuredRaceWithUpcoming()]);
    // Only the live featured race — no second (upcoming) FeaturedRaceCard.
    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    // The upcoming CTA copy must not appear.
    expect(find.text('OPT IN'), findsNothing);
    expect(find.text("YOU'RE IN"), findsNothing);
  });
}
