import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tournament_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/ad_banner_slot.dart';
import 'package:step_tracker/widgets/tournament_bracket_board.dart';

// Spec §3: the tournament sponsored slot moved from a NATIVE ad boxed inside the
// pannable/zoomable bracket (TournamentSponsorCard, now retired) to a single
// fixed AdBannerSlot pinned above the board. In tests banners are disabled
// (no banner unit id), so the slot collapses to zero height and never spins up
// a platform-view ad — no NativeAd, no AdWidget, no size/asset warnings.

class _FakeApi extends BackendApiService {
  _FakeApi(this.payload);
  final Map<String, dynamic> payload;

  @override
  Future<Map<String, dynamic>> fetchTournament({
    required String identityToken,
    required String tournamentId,
  }) async =>
      {'tournament': payload};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Me',
    'auth_coins': 500,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester, Map<String, dynamic> payload) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: TournamentDetailScreen(
        authService: auth,
        tournamentId: 't1',
        backendApiService: _FakeApi(payload),
      ),
    ),
  );
  await tester.pump(); // fetch future
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

Map<String, dynamic> _activeTournament() => {
      'id': 't1',
      'name': 'Gauntlet',
      'status': 'ACTIVE',
      'bracketSize': 4,
      'matchupDurationDays': 1,
      'currentRound': 1,
      'totalRounds': 2,
      'myStatus': 'ACCEPTED',
      'participants': const [
        {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
        {'userId': 'u2', 'displayName': 'Bob', 'status': 'ACCEPTED'},
      ],
      'rounds': const [
        {
          'round': 1,
          'label': 'SEMIFINALS',
          'matchups': [
            {
              'matchIndex': 0,
              'raceId': 'r1',
              'status': 'ACTIVE',
              'players': [
                {'userId': 'me', 'totalSteps': 100, 'forfeited': false},
                {'userId': 'u2', 'totalSteps': 90, 'forfeited': false},
              ],
              'winnerUserId': null,
            },
          ],
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tournament screen has no native ad widget on the bracket',
      (tester) async {
    await _pump(tester, _activeTournament());

    expect(find.byType(TournamentBracketBoard), findsOneWidget);
    // The retired native ad rendered through an AdWidget platform view; the new
    // AdBannerSlot never constructs one while banners are disabled.
    expect(find.byType(AdWidget), findsNothing);
    await _teardown(tester);
  });

  testWidgets('sponsored band contributes zero height with ads disabled',
      (tester) async {
    await _pump(tester, _activeTournament());

    // Exactly one sponsored banner slot, pinned above the board (the shell slot
    // is not in this pushed-route subtree).
    expect(find.byType(AdBannerSlot), findsOneWidget);
    final size = tester.getSize(find.byType(AdBannerSlot));
    expect(size.height, 0);
    await _teardown(tester);
  });
}
