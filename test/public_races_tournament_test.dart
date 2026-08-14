import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/pill_button.dart';

// Spec §9/§10: the public races screen pins FEATURED cards per active seed
// above user-created public tournament cards. Featured are free (JOIN, no
// confirm), flip to VIEW once joined, and D12 pre-disables JOIN while I'm still
// alive in another same-seed bracket. A missing `featured` key → no section.

class _FakeApi extends BackendApiService {
  _FakeApi({
    this.featured = const [],
    this.userTournaments = const [],
    this.myTournaments = const [],
    this.browser,
  });

  final List<Map<String, dynamic>> featured;
  final List<Map<String, dynamic>> userTournaments;
  final List<Map<String, dynamic>> myTournaments;
  final Map<String, dynamic>? browser;
  int featuredRaceCalls = 0;
  int publicTournamentCalls = 0;
  int myRaceCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchPublicRaceBrowser({
    required String identityToken,
  }) async => browser ?? {'races': const <Map<String, dynamic>>[]};

  @override
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async {
    featuredRaceCalls += 1;
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchPublicTournaments({
    required String identityToken,
  }) async {
    publicTournamentCalls += 1;
    return {'featured': featured, 'tournaments': userTournaments};
  }

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async {
    myRaceCalls += 1;
    return {
      'active': const [],
      'pending': const [],
      'tournaments': myTournaments,
    };
  }
}

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

Future<void> _pump(WidgetTester tester, _FakeApi api) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: PublicRacesScreen(authService: auth, backendApiService: api),
    ),
  );
  // Pumped frames (not pumpAndSettle) — the tournament cards embed a SpinningCoin
  // whose flip animation never settles.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
}

Map<String, dynamic> _featured({
  String id = 'seed1',
  String? myStatus,
  int accepted = 2,
}) => {
  'id': id,
  'name': 'Daily Dash',
  'status': 'PENDING',
  'seedId': 'seed-tournament-daily-dash',
  'seedKind': 'DAILY_DASH',
  'bracketSize': 4,
  'matchupDurationDays': 1,
  'buyInAmount': 0,
  'potCoins': 0,
  'championPrizeCoins': 150,
  'acceptedCount': accepted,
  'myStatus': ?myStatus,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unselected public-race filters stay legible in dark mode', (
    tester,
  ) async {
    final auth = await _auth();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.night(),
        home: PublicRacesScreen(
          authService: auth,
          backendApiService: _FakeApi(featured: [_featured()]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));

    // FEATURED is the default (selected) pill, so its label is dark-on-gold;
    // the legibility concern is the UNSELECTED pills on the dark track.
    for (final key in const [
      Key('public-filter-tournaments'),
      Key('public-filter-races'),
    ]) {
      final label = tester.widget<Text>(
        find.descendant(of: find.byKey(key), matching: find.byType(Text)),
      );
      expect(label.style?.color, AppPalette.night.textLight);
    }
  });

  testWidgets(
    'compact browser falls back only malformed featured and mine branches',
    (tester) async {
      final api = _FakeApi(
        browser: const {
          'contract': 'public-race-browser-v1',
          'races': <Map<String, dynamic>>[],
          'resolved': {
            'featuredRaces': true,
            'tournaments': true,
            'mine': true,
          },
          'featuredRaces': 'malformed',
          'tournaments': {
            'featured': <Map<String, dynamic>>[],
            'public': <Map<String, dynamic>>[],
            'mine': 'malformed',
          },
        },
      );

      await _pump(tester, api);

      expect(api.featuredRaceCalls, 1);
      expect(api.publicTournamentCalls, 0);
      expect(api.myRaceCalls, 1);
    },
  );

  testWidgets('open featured card shows JOIN and the prize', (tester) async {
    await _pump(tester, _FakeApi(featured: [_featured()]));
    // 'FEATURED' now appears twice — the filter-pill segment and the section
    // header — so assert it's present rather than unique.
    expect(find.text('FEATURED'), findsWidgets);
    expect(find.text('Daily Dash'.toUpperCase()), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    final btn = tester.widget<PillButton>(
      find.byKey(const Key('featured-tournament-join-seed1')),
    );
    expect(btn.label, 'JOIN');
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('joined featured card flips to VIEW', (tester) async {
    await _pump(tester, _FakeApi(featured: [_featured(myStatus: 'ACCEPTED')]));
    final btn = tester.widget<PillButton>(
      find.byKey(const Key('featured-tournament-join-seed1')),
    );
    expect(btn.label, 'VIEW');
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('nearly-full featured card still joinable; full disables', (
    tester,
  ) async {
    await _pump(tester, _FakeApi(featured: [_featured(accepted: 4)]));
    final btn = tester.widget<PillButton>(
      find.byKey(const Key('featured-tournament-join-seed1')),
    );
    expect(btn.label, 'FULL');
    expect(btn.onPressed, isNull);
  });

  testWidgets(
    'D12: JOIN disabled while still alive in another same-seed bracket',
    (tester) async {
      await _pump(
        tester,
        _FakeApi(
          featured: [_featured()],
          // I'm mid-run in an ACTIVE bracket minted from the same seed.
          myTournaments: [
            {
              'id': 'other',
              'seedKind': 'DAILY_DASH',
              'status': 'ACTIVE',
              'myStatus': 'ACCEPTED',
              'bracketSize': 4,
            },
          ],
        ),
      );
      final btn = tester.widget<PillButton>(
        find.byKey(const Key('featured-tournament-join-seed1')),
      );
      expect(btn.label, 'IN A BRACKET');
      expect(btn.onPressed, isNull);
    },
  );

  testWidgets('missing featured key → no featured section (older backend)', (
    tester,
  ) async {
    // fetchPublicTournaments returns empty lists; nothing pins.
    await _pump(tester, _FakeApi());
    expect(find.text('FEATURED'), findsNothing);
  });

  testWidgets('user-created public tournament card renders below featured', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeApi(
        featured: [_featured()],
        userTournaments: [
          {
            'id': 'u1',
            'name': 'Gauntlet',
            'status': 'PENDING',
            'bracketSize': 8,
            'matchupDurationDays': 2,
            'buyInAmount': 50,
            'potCoins': 100,
            'acceptedCount': 2,
          },
        ],
      ),
    );
    // User-created brackets live under the TOURNEYS pill now that each pill
    // shows a single group.
    await tester.tap(find.byKey(const Key('public-filter-tournaments')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('TOURNEYS'), findsWidgets);
    final btn = tester.widget<PillButton>(
      find.byKey(const Key('user-tournament-join-u1')),
    );
    expect(btn.label, 'JOIN');
  });
}
