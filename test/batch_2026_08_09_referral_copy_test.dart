import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/get_coins_screen.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';
import 'package:step_tracker/screens/referral_rules_screen.dart';
import 'package:step_tracker/screens/referral_screen.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Batch 2026-08-09 item 2 — referral verbiage.
///
/// The backend gate changed: a seeded daily/weekly challenge NEVER qualifies a
/// referral any more. A qualifying race is a real race with at least one other
/// real player who logs steps. Every user-facing surface that describes the
/// payout must say so, and none may still promise "your first race" (which a
/// daily challenge satisfies).
class _FakeReferralApi extends BackendApiService {
  _FakeReferralApi([this.extra = const {}]);

  final Map<String, dynamic> extra;

  @override
  Future<Map<String, dynamic>> fetchReferralStatus({
    required String identityToken,
  }) async => {
    'code': 'BARA-7F3K',
    'url': 'https://steptracker-api.org/r/BARA-7F3K',
    'referredCount': 0,
    'completedCount': 0,
    'coinsEarned': 0,
    'friends': const [],
    ...extra,
  };

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => {
    'claimedToday': false,
    'cycleLength': 6,
    'currentDay': 3,
    'ladder': <dynamic>[],
  };
}

class _NoAdController implements ExtraSpinAdController {
  @override
  bool get isSupported => false;
  @override
  bool get isReady => false;
  @override
  Future<void> load({
    required String userId,
    required String localDate,
  }) async {}
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
    'auth_display_name': 'Walker',
    'auth_coins': 100,
    'auth_held_coins': 0,
  });
  final service = AuthService();
  await service.restoreSession();
  return service;
}

Future<void> _pumpReferral(
  WidgetTester tester, [
  Map<String, dynamic> extra = const {},
]) async {
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
  WidgetTester tester, [
  Map<String, dynamic> extra = const {},
]) async {
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

/// Every rendered string on the pumped screen.
List<String> _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text, skipOffstage: false))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .toList();

Matcher _mentionsAnotherPlayer() => predicate<String>(
  (s) => s.toLowerCase().contains('player'),
  'names another real player as the qualifying condition',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.example.bara',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('rules screen', () {
    testWidgets('defines a qualifying race as a real multiplayer race', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ReferralRulesScreen()));
      await tester.pump();

      final body = _allText(tester).join(' ').toLowerCase();

      expect(
        body,
        contains('at least one other real player'),
        reason: 'the qualifying-race definition must be explicit',
      );
      expect(
        body,
        anyOf(contains("don't count"), contains('don’t count')),
        reason: 'daily/weekly challenges must be explicitly excluded',
      );
      // The OLD definition let an official daily/weekly qualify. That sentence
      // must be gone, not merely supplemented.
      expect(
        body,
        isNot(contains('either an official')),
        reason: 'seeded dailies/weeklies no longer qualify',
      );
    });
  });

  group('referral screen', () {
    testWidgets('headline names the qualifying race (no figures served)', (
      tester,
    ) async {
      await _pumpReferral(tester);

      final headline = _allText(
        tester,
      ).firstWhere((s) => s.startsWith('Send your link'));
      expect(headline, _mentionsAnotherPlayer());
      expect(
        headline.toLowerCase(),
        isNot(contains('their first race')),
        reason: 'a seeded daily is a "first race" but no longer qualifies',
      );
      // Degradation is unchanged: no server figures, no invented number.
      expect(headline, isNot(contains('500')));
    });

    testWidgets('headline still states both figures when served', (
      tester,
    ) async {
      await _pumpReferral(tester, const {
        'referrerCoins': 500,
        'refereeCoins': 500,
      });

      final headline = _allText(
        tester,
      ).firstWhere((s) => s.startsWith('Send your link'));
      expect(headline, contains('500 coins'));
      expect(headline, _mentionsAnotherPlayer());
    });

    testWidgets('the whole screen never promises "your first race"', (
      tester,
    ) async {
      await _pumpReferral(tester, const {
        'referrerCoins': 500,
        'refereeCoins': 500,
      });

      for (final line in _allText(tester)) {
        expect(
          line.toLowerCase(),
          isNot(contains('first race')),
          reason: 'stale qualifying-action copy: "$line"',
        );
      }
    });
  });

  group('shared copy builders', () {
    test('invite row names the qualifying race in both figure states', () {
      for (final copy in [
        referralInviteRowCopy(),
        referralInviteRowCopy(referrerCoins: 500, refereeCoins: 500),
        referralInviteRowCopy(referrerCoins: 1000, refereeCoins: 500),
      ]) {
        expect(copy, _mentionsAnotherPlayer(), reason: copy);
        expect(copy.toLowerCase(), isNot(contains('first race')), reason: copy);
      }
    });

    test('redeem toast names the qualifying race', () {
      for (final copy in [
        referralRedeemedCopy(),
        referralRedeemedCopy(refereeCoins: 500),
      ]) {
        expect(copy, _mentionsAnotherPlayer(), reason: copy);
        expect(copy.toLowerCase(), isNot(contains('first race')), reason: copy);
      }
    });

    test('share text names the qualifying race and keeps its figures', () {
      final text = referralShareText(
        code: 'BARA-7F3K',
        url: 'https://example.test/r/BARA-7F3K',
        steps: 8432,
        referrerCoins: 1000,
        refereeCoins: 500,
      );
      expect(text, _mentionsAnotherPlayer());
      expect(text, contains('1,000'));
      expect(text, contains('500'));
      expect(text.toLowerCase(), isNot(contains('first race')));

      final bare = referralShareText(code: 'C', url: 'u');
      expect(bare, _mentionsAnotherPlayer());
      expect(bare, isNot(contains('null')));
    });
  });

  group('Get Coins invite card', () {
    testWidgets('names the qualifying race with the figure served', (
      tester,
    ) async {
      await _pumpGetCoins(tester, const {
        'referrerCoins': 500,
        'refereeCoins': 500,
      });

      expect(find.text('INVITE FRIENDS'), findsOneWidget);
      final row = _allText(tester).firstWhere((s) => s.contains('500 coins'));
      expect(row, _mentionsAnotherPlayer());
    });

    testWidgets('older backend keeps number-free copy and the new wording', (
      tester,
    ) async {
      await _pumpGetCoins(tester);

      expect(find.text('INVITE FRIENDS'), findsOneWidget);
      expect(find.textContaining('500'), findsNothing);
      final row = _allText(
        tester,
      ).firstWhere((s) => s.startsWith('Coins land in both bags'));
      expect(row, _mentionsAnotherPlayer());
    });
  });

  group('onboarding referred-install welcome', () {
    testWidgets('names the qualifying race with a reward figure', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingReferralWelcomeStep(
            code: 'BARA-7F3K',
            onFetchPreview: (code) async => {
              'inviterName': 'Alice',
              'inviterAvatar': null,
              'rewardCoins': 100,
            },
            onContinue: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('@Alice invited you to Bara'), findsOneWidget);
      final body = _allText(tester).firstWhere((s) => s.contains('100'));
      expect(body, _mentionsAnotherPlayer());
      expect(body.toLowerCase(), isNot(contains('first race')));
    });

    testWidgets('names the qualifying race with no reward figure served', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingReferralWelcomeStep(
            code: 'BARA-7F3K',
            onFetchPreview: (code) async => {'inviterName': 'Alice'},
            onContinue: () {},
          ),
        ),
      );
      await tester.pump();

      final body = _allText(
        tester,
      ).where((s) => s.toLowerCase().contains('coins')).join(' ');
      expect(body, _mentionsAnotherPlayer());
      expect(body.toLowerCase(), isNot(contains('first race')));
    });
  });
}
