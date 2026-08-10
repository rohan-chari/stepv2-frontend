import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/friend_picker_screen.dart';
import 'package:step_tracker/screens/get_coins_screen.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';
import 'package:step_tracker/screens/race_invite_screen.dart';
import 'package:step_tracker/screens/referral_screen.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Items 12 + 16 (batch 2026-07-27).
///
/// Item 12: the invite surfaces must STATE the coin figures — and take them
/// off the wire (`referrerCoins` / `refereeCoins`, additive per spec §4.3),
/// never from a constant baked into the binary. The prod backend may not serve
/// them yet, and they may be retuned later without an App Store release, so a
/// missing or null field must degrade to the number-free wording rather than
/// print a figure that contradicts server config.
///
/// Item 16: the resulting copy is conversational — second person, no
/// "you BOTH earn coins", no shouting mid-sentence.

// --------------------------------------------------------------------------
// Fakes
// --------------------------------------------------------------------------

class _FakeReferralApi extends BackendApiService {
  _FakeReferralApi(this.extra);

  /// Merged over the base payload — pass `{}` for an older backend that serves
  /// no figures, or explicit nulls for a backend that serves them empty.
  final Map<String, dynamic> extra;

  @override
  Future<Map<String, dynamic>> fetchReferralStatus({
    required String identityToken,
  }) async {
    return {
      'code': 'BARA-7F3K',
      'url': 'https://steptracker-api.org/r/BARA-7F3K',
      'referredCount': 0,
      'completedCount': 0,
      'coinsEarned': 0,
      'friends': const [],
      ...extra,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    return {
      'claimedToday': false,
      'cycleLength': 6,
      'currentDay': 3,
      'ladder': <dynamic>[],
    };
  }
}

class _NoAdController implements ExtraSpinAdController {
  @override
  bool get isSupported => false;
  @override
  bool get isReady => false;
  @override
  Future<void> load({required String userId, required String localDate}) async {}
  @override
  Future<bool> showAndAwaitReward() async => false;
  @override
  void dispose() {}
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpReferral(
  WidgetTester tester,
  Map<String, dynamic> extra,
) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: ReferralScreen(
        authService: auth,
        backendApiService: _FakeReferralApi(extra),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpGetCoins(
  WidgetTester tester,
  Map<String, dynamic> extra,
) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: GetCoinsScreen(
        authService: auth,
        backendApiService: _FakeReferralApi(extra),
        adController: _NoAdController(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------------
  // Item 12 — figures come off the wire, or not at all
  // ------------------------------------------------------------------
  group('referral screen headline', () {
    testWidgets('states the figure when the backend serves both', (
      tester,
    ) async {
      await _pumpReferral(tester, {'referrerCoins': 500, 'refereeCoins': 500});

      expect(find.textContaining('500 coins'), findsOneWidget);
      // Item 16: the shouty construction is gone.
      expect(find.textContaining('BOTH'), findsNothing);
    });

    testWidgets('states both figures when they differ', (tester) async {
      await _pumpReferral(tester, {'referrerCoins': 1000, 'refereeCoins': 500});

      expect(find.textContaining('1,000 coins'), findsOneWidget);
      expect(find.textContaining('500'), findsOneWidget);
    });

    testWidgets('older backend (fields absent) falls back to no number', (
      tester,
    ) async {
      await _pumpReferral(tester, const {});

      expect(find.textContaining('Send your link'), findsOneWidget);
      // No figure may be invented when the server did not supply one.
      expect(find.textContaining('500'), findsNothing);
      // Still promises coins — it just declines to name a figure.
      expect(find.textContaining('Coins land in both bags'), findsOneWidget);
    });

    testWidgets('null figures behave exactly like absent ones', (tester) async {
      await _pumpReferral(tester, const {
        'referrerCoins': null,
        'refereeCoins': null,
      });

      expect(find.textContaining('Send your link'), findsOneWidget);
      expect(find.textContaining('500'), findsNothing);
    });

    testWidgets('one figure alone is not enough to print a number', (
      tester,
    ) async {
      await _pumpReferral(tester, const {'refereeCoins': 500});

      expect(find.textContaining('500'), findsNothing);
    });
  });

  group('share text', () {
    test('states the shared figure when both are served and equal', () {
      final text = referralShareText(
        code: 'BARA-7F3K',
        url: 'https://b.io/r',
        steps: 8432,
        referrerCoins: 500,
        refereeCoins: 500,
      );
      expect(text, contains('8,432 steps'));
      expect(text, contains('500 coins'));
      expect(text, contains('BARA-7F3K'));
      expect(text, contains('https://b.io/r'));
      expect(text, isNot(contains('BOTH')));
    });

    test('states each side when the figures differ', () {
      final text = referralShareText(
        code: 'C',
        url: 'u',
        steps: null,
        referrerCoins: 1000,
        refereeCoins: 500,
      );
      expect(text, contains('1,000'));
      expect(text, contains('500'));
    });

    test('drops the number entirely when the backend served none', () {
      final text = referralShareText(
        code: 'C',
        url: 'u',
        steps: 8432,
        referrerCoins: null,
        refereeCoins: null,
      );
      expect(text, contains('coin'));
      expect(text, isNot(contains('500')));
      expect(text, isNot(contains('null')));
    });
  });

  group('Get Coins invite row', () {
    testWidgets('states the figure when the backend serves it', (tester) async {
      await _pumpGetCoins(tester, {'referrerCoins': 500, 'refereeCoins': 500});

      expect(find.textContaining('500 coins'), findsOneWidget);
    });

    testWidgets('older backend keeps the number-free invite row', (
      tester,
    ) async {
      await _pumpGetCoins(tester, const {});

      expect(find.text('INVITE FRIENDS'), findsOneWidget);
      expect(find.textContaining('500'), findsNothing);
      // Batch 2026-08-09 item 2 renamed the qualifying action: a seeded daily
      // is "their first race" but no longer completes a referral. The property
      // this test guards — the number-free row still names the action — is
      // unchanged.
      expect(
        find.textContaining('finishes a race against another real player'),
        findsOneWidget,
      );
    });
  });

  // ------------------------------------------------------------------
  // Item 16 — conversational copy on every invite surface
  // ------------------------------------------------------------------
  group('invite copy register', () {
    testWidgets('friend picker asks you to pick a rival', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FriendPickerScreen(
            friends: [
              {'id': 'a', 'displayName': 'Ann'},
            ],
          ),
        ),
      );

      expect(find.text('PICK YOUR RIVAL'), findsOneWidget);
      expect(find.text('Tap a friend and the race is on.'), findsOneWidget);
    });

    testWidgets('race invite says what a tap does', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RaceInviteScreen(
            friends: [
              {'id': 'a', 'displayName': 'Ann'},
            ],
          ),
        ),
      );

      expect(
        find.text('Tap everyone you want in this race.'),
        findsOneWidget,
      );
    });

    testWidgets('race invite empty state is an invitation to act', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: RaceInviteScreen(friends: [])),
      );

      expect(find.textContaining('Nobody left to invite'), findsOneWidget);
    });

    testWidgets('the auto-enrolled step reads like a challenge', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingAutoEnrolledStep(
            onEnterDaily: () async {},
            onSkip: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        find.text('The Daily and Weekly are yours to win'),
        findsOneWidget,
      );
    });

    testWidgets('the referral welcome step drops the "both earn" phrasing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingReferralWelcomeStep(
            code: 'BARA-1',
            onContinue: () {},
            onFetchPreview: (_) async => {
              'inviterName': 'Alice',
              'rewardCoins': 500,
              'referrerCoins': 500,
              'refereeCoins': 500,
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('@Alice invited you to Bara'), findsOneWidget);
      expect(find.textContaining('500'), findsOneWidget);
      expect(find.textContaining('both earn coins'), findsNothing);
    });

    testWidgets('the referral welcome step survives a figure-less preview', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingReferralWelcomeStep(
            code: 'BARA-1',
            onContinue: () {},
            onFetchPreview: (_) async => const <String, dynamic>{},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('A friend invited you to Bara'), findsOneWidget);
      expect(find.textContaining('both earn coins'), findsNothing);
    });
  });
}
