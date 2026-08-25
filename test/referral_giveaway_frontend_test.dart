import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/giveaway_rules_screen.dart';
import 'package:step_tracker/screens/giveaway_screen.dart';
import 'package:step_tracker/screens/referral_screen.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';

const _allUsRegions = <String>[
  'US-AL',
  'US-AK',
  'US-AZ',
  'US-AR',
  'US-CA',
  'US-CO',
  'US-CT',
  'US-DE',
  'US-DC',
  'US-FL',
  'US-GA',
  'US-HI',
  'US-ID',
  'US-IL',
  'US-IN',
  'US-IA',
  'US-KS',
  'US-KY',
  'US-LA',
  'US-ME',
  'US-MD',
  'US-MA',
  'US-MI',
  'US-MN',
  'US-MS',
  'US-MO',
  'US-MT',
  'US-NE',
  'US-NV',
  'US-NH',
  'US-NJ',
  'US-NM',
  'US-NY',
  'US-NC',
  'US-ND',
  'US-OH',
  'US-OK',
  'US-OR',
  'US-PA',
  'US-RI',
  'US-SC',
  'US-SD',
  'US-TN',
  'US-TX',
  'US-UT',
  'US-VT',
  'US-VA',
  'US-WA',
  'US-WV',
  'US-WI',
  'US-WY',
];

const _contest = <String, dynamic>{
  'slug': 'bara-referral-2026-09',
  'title': 'Bara Referral Contest',
  'status': 'ACTIVE',
  'startsAt': '2026-09-01T04:00:00.000Z',
  'endsAt': '2026-10-01T04:00:00.000Z',
  'governingTimeZone': 'America/New_York',
  'prize': {'cashCurrency': 'USD', 'cashMinor': 5000, 'coins': 5000},
  'minimumAge': 18,
  'eligibleCountries': ['US'],
  'eligibleRegions': _allUsRegions,
  'sponsor': {'legalName': 'Bara LLC', 'mailingAddress': '1 Trail Way'},
  'rules': {
    'version': '2026-09-v1',
    'sha256':
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    'sections': [
      {'heading': 'How to enter', 'body': 'Enter, then complete referrals.'},
      {
        'heading': 'Platform notice',
        'body': 'Apple and Google are not sponsors.',
      },
    ],
  },
  'socialLinks': [
    {
      'platform': 'instagram',
      'label': 'Instagram',
      'url': 'https://www.instagram.com/bara',
    },
  ],
};

Map<String, dynamic> currentPayload({
  Map<String, dynamic>? contest = _contest,
  String entryStatus = 'ACTION_REQUIRED',
  List<Map<String, dynamic>> leaderboard = const [
    {'rank': 1, 'displayName': 'Rohan', 'completedCount': 7},
    {'rank': 2, 'displayName': 'Scout', 'completedCount': 4},
  ],
  Map<String, dynamic>? winner,
}) => {
  'contest': contest,
  'leaderboard': leaderboard,
  'winner': winner,
  'entry': contest == null
      ? null
      : {
          'status': entryStatus,
          'acceptedAt': entryStatus != 'ACTION_REQUIRED'
              ? '2026-09-02T15:00:00.000Z'
              : null,
          'region': entryStatus != 'ACTION_REQUIRED' ? 'US-NY' : null,
          'displayName': 'Trail Walker',
        },
  'standing': contest == null || entryStatus == 'WITHDRAWN'
      ? null
      : entryStatus == 'ACTION_REQUIRED' || entryStatus == 'INELIGIBLE'
      ? {
          'verifiedCount': 0,
          'reviewableCount': 0,
          'provisionalRank': null,
          'reachedCountAt': null,
        }
      : {
          'verifiedCount': 3,
          'reviewableCount': contest['status'] == 'FINAL' ? 0 : 1,
          'provisionalRank': 8,
          'reachedCountAt': '2026-09-10T12:00:00.000Z',
        },
  'share': contest == null || entryStatus == 'WITHDRAWN'
      ? null
      : {'code': 'BARA-7F3K', 'url': 'https://barastep.com/r/BARA-7F3K'},
};

class _GiveawayApi extends BackendApiService {
  _GiveawayApi({
    this.payload,
    this.error,
    this.entryError,
    this.enterCompleter,
  });

  Map<String, dynamic>? payload;
  final Object? error;
  final Object? entryError;
  final Completer<Map<String, dynamic>>? enterCompleter;
  int currentCalls = 0;
  int entryCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchCurrentGiveaway({
    required String identityToken,
  }) async {
    currentCalls += 1;
    if (error != null) throw error!;
    return payload ?? currentPayload();
  }

  @override
  Future<Map<String, dynamic>> enterGiveaway({
    required String identityToken,
    required String slug,
    required String rulesVersion,
    required String country,
    required String region,
    required bool ageConfirmed,
    required bool residencyConfirmed,
    required bool rulesAccepted,
  }) async {
    entryCalls += 1;
    if (entryError != null) throw entryError!;
    if (enterCompleter != null) return enterCompleter!.future;
    return {
      'entry': {
        'status': 'ELIGIBLE',
        'acceptedAt': '2026-09-02T15:00:00.000Z',
        'country': 'US',
        'region': region,
        'displayName': 'Trail Walker',
        'rulesVersion': rulesVersion,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchReferralStatus({
    required String identityToken,
  }) async => {
    'code': 'BARA-7F3K',
    'url': 'https://barastep.com/r/BARA-7F3K',
    'referredCount': 2,
    'completedCount': 1,
    'coinsEarned': 500,
    'friends': const <Map<String, dynamic>>[],
  };
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'identity',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpGiveaway(
  WidgetTester tester,
  BackendApiService api, {
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: GiveawayScreen(
        slug: 'bara-referral-2026-09',
        authService: auth,
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('customer contest workflow', () {
    test(
      'advertises referral contest capability in both feature-header branches',
      () {
        for (final ads in [true, false]) {
          expect(
            BackendApiService.clientFeaturesHeaderForPlatform(
              isIos: true,
              adsSupported: ads,
              racePayoutDoubleSupported: false,
            ).split(','),
            contains('referral_contest_v1'),
          );
        }
        expect(
          BackendApiService.clientFeaturesHeader.split(','),
          contains('referral_contest_v1'),
        );
      },
    );

    testWidgets(
      'action-required user can read terms, enter, and become eligible',
      (tester) async {
        final api = _GiveawayApi();
        await _pumpGiveaway(tester, api);

        expect(find.text('REFERRAL CONTEST'), findsOneWidget);
        expect(find.text(r'US$50 + 5,000 COINS'), findsOneWidget);
        expect(find.textContaining('No purchase necessary'), findsWidgets);
        expect(find.text('ENTER CONTEST'), findsOneWidget);
        expect(find.text('PROVISIONAL'), findsWidgets);
        expect(find.textContaining('2026-10-01 04:00 UTC'), findsOneWidget);
        expect(find.textContaining('America/New_York governs'), findsOneWidget);
        expect(find.text('Instagram'), findsOneWidget);
        expect(find.textContaining('does not affect contest'), findsOneWidget);
        expect(find.textContaining('rate'), findsNothing);

        tester
            .widget<PillButton>(
              find.widgetWithText(PillButton, 'ENTER CONTEST'),
            )
            .onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('CONFIRM ENTRY'), findsWidgets);
        expect(find.textContaining('18 or older'), findsOneWidget);
        expect(find.textContaining('legal resident'), findsWidgets);
        expect(find.textContaining('Official Rules'), findsWidgets);
        expect(find.textContaining('Trail Walker'), findsWidgets);

        for (final key in const [
          Key('giveaway-age-confirmed'),
          Key('giveaway-residency-confirmed'),
          Key('giveaway-rules-accepted'),
        ]) {
          await tester.ensureVisible(find.byKey(key));
          await tester.tap(find.byKey(key));
        }
        await tester.ensureVisible(
          find.byKey(const Key('giveaway-region-field')),
        );
        await tester.tap(find.byKey(const Key('giveaway-region-field')));
        await tester.pump();
        await tester.tap(find.text('Alabama'));
        await tester.pump();
        await tester.ensureVisible(find.text('CONFIRM ENTRY').last);
        tester
            .widget<PillButton>(
              find.widgetWithText(PillButton, 'CONFIRM ENTRY'),
            )
            .onPressed!();
        await tester.pump();

        expect(api.entryCalls, 1);
        expect(find.text('YOU’RE ENTERED'), findsOneWidget);
      },
    );

    testWidgets('double tap submits one entry request', (tester) async {
      final completer = Completer<Map<String, dynamic>>();
      final api = _GiveawayApi(enterCompleter: completer);
      await _pumpGiveaway(tester, api);
      tester
          .widget<PillButton>(find.widgetWithText(PillButton, 'ENTER CONTEST'))
          .onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (final key in const [
        Key('giveaway-age-confirmed'),
        Key('giveaway-residency-confirmed'),
        Key('giveaway-rules-accepted'),
      ]) {
        await tester.ensureVisible(find.byKey(key));
        await tester.tap(find.byKey(key));
      }
      await tester.ensureVisible(
        find.byKey(const Key('giveaway-region-field')),
      );
      await tester.tap(find.byKey(const Key('giveaway-region-field')));
      await tester.pump();
      await tester.tap(find.text('Alabama'));
      await tester.pump();
      final button = find.widgetWithText(PillButton, 'CONFIRM ENTRY');
      await tester.ensureVisible(button);
      final onPressed = tester.widget<PillButton>(button).onPressed!;
      onPressed();
      onPressed();
      await tester.pump();
      expect(api.entryCalls, 1);
      completer.complete({
        'entry': {
          'status': 'ELIGIBLE',
          'acceptedAt': '2026-09-02T15:00:00.000Z',
          'country': 'US',
          'region': 'US-NY',
          'displayName': 'Trail Walker',
          'rulesVersion': '2026-09-v1',
        },
      });
      await tester.pump();
    });

    testWidgets('ranked user outside top list gets one personal standing row', (
      tester,
    ) async {
      await _pumpGiveaway(
        tester,
        _GiveawayApi(payload: currentPayload(entryStatus: 'ELIGIBLE')),
      );
      expect(find.text('YOUR STANDING'), findsOneWidget);
      expect(find.text('#8'), findsWidgets);
      expect(find.text('3 VERIFIED'), findsOneWidget);
      expect(find.text('1 UNDER REVIEW'), findsOneWidget);
      expect(find.text('Trail Walker'), findsOneWidget);
    });

    testWidgets(
      'empty, verifying, final winner, alternate, and no-winner copy',
      (tester) async {
        final api = _GiveawayApi(
          payload: currentPayload(leaderboard: const []),
        );
        await _pumpGiveaway(tester, api);
        expect(
          find.textContaining('No referrals have qualified yet'),
          findsOneWidget,
        );
        expect(find.text('SHARE YOUR INVITE'), findsOneWidget);

        api.payload = currentPayload(
          contest: {..._contest, 'status': 'VERIFYING'},
        );
        await tester.tap(find.byKey(const Key('giveaway-retry')));
        await tester.pump();
        expect(find.textContaining('results are under review'), findsOneWidget);

        api.payload = currentPayload(
          contest: {..._contest, 'status': 'FINAL'},
          winner: {'displayName': 'Scout', 'originalRank': 2},
        );
        await tester.tap(find.byKey(const Key('giveaway-retry')));
        await tester.pump();
        expect(find.text('WINNER: SCOUT'), findsOneWidget);
        expect(find.textContaining('originally ranked #2'), findsOneWidget);

        api.payload = currentPayload(
          contest: {..._contest, 'status': 'FINAL'},
          winner: null,
        );
        await tester.tap(find.byKey(const Key('giveaway-retry')));
        await tester.pump();
        expect(find.text('NO WINNER'), findsOneWidget);
      },
    );

    testWidgets('withdrawn and ineligible status cannot enter', (tester) async {
      for (final status in ['WITHDRAWN', 'INELIGIBLE']) {
        await _pumpGiveaway(
          tester,
          _GiveawayApi(payload: currentPayload(entryStatus: status)),
        );
        expect(find.text(status), findsOneWidget);
        expect(find.text('ENTER CONTEST'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('deleted entrant remains visibly withdrawn without PII', (
      tester,
    ) async {
      final payload = currentPayload(entryStatus: 'WITHDRAWN')
        ..['entry'] = {
          'status': 'WITHDRAWN',
          'acceptedAt': '2026-09-02T15:00:00.000Z',
          'region': 'US-NY',
          'displayName': null,
        };
      await _pumpGiveaway(tester, _GiveawayApi(payload: payload));
      expect(find.text('WITHDRAWN'), findsOneWidget);
      expect(find.text('Contest unavailable'), findsNothing);
      expect(find.text('ENTER CONTEST'), findsNothing);
    });

    testWidgets('malformed, 404, and rate limits fail safely with retry', (
      tester,
    ) async {
      await _pumpGiveaway(
        tester,
        _GiveawayApi(
          payload: {
            'contest': {'slug': 7},
          },
        ),
      );
      expect(find.text('Contest unavailable'), findsOneWidget);
      expect(find.byKey(const Key('giveaway-retry')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _pumpGiveaway(
        tester,
        _GiveawayApi(
          payload: currentPayload(
            contest: {
              ..._contest,
              'eligibleRegions': ['US-ZZ'],
            },
          ),
        ),
      );
      expect(find.text('Contest unavailable'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _pumpGiveaway(
        tester,
        _GiveawayApi(error: const ApiException('missing', statusCode: 404)),
      );
      expect(find.text('Contest unavailable'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _pumpGiveaway(
        tester,
        _GiveawayApi(
          error: const ApiException(
            'Try again later.',
            statusCode: 429,
            code: 'GIVEAWAY_PUBLIC_RATE_LIMITED',
          ),
        ),
      );
      expect(find.text('Contest unavailable'), findsOneWidget);
      expect(find.text('RETRY'), findsOneWidget);
    });

    testWidgets(
      'populated response rejects missing or inconsistent member state',
      (tester) async {
        final missingEntry = currentPayload()..['entry'] = null;
        final actionWithoutStanding = currentPayload()..['standing'] = null;
        final eligibleWithoutAcceptance =
            currentPayload(entryStatus: 'ELIGIBLE')
              ..['entry'] = {
                'status': 'ELIGIBLE',
                'acceptedAt': null,
                'region': 'US-NY',
                'displayName': 'Trail Walker',
              };
        final finalWithReviewable =
            currentPayload(contest: {..._contest, 'status': 'FINAL'})
              ..['standing'] = {
                'verifiedCount': 3,
                'reviewableCount': 1,
                'provisionalRank': 8,
                'reachedCountAt': '2026-09-10T12:00:00.000Z',
              };
        final foreignShareHost = currentPayload()
          ..['share'] = {
            'code': 'BARA-7F3K',
            'url': 'https://example.com/r/BARA-7F3K',
          };
        final nonCanonicalSharePath = currentPayload()
          ..['share'] = {
            'code': 'BARA-7F3K',
            'url': 'https://barastep.com/invite/BARA-7F3K',
          };

        for (final payload in [
          missingEntry,
          actionWithoutStanding,
          eligibleWithoutAcceptance,
          finalWithReviewable,
          foreignShareHost,
          nonCanonicalSharePath,
        ]) {
          await _pumpGiveaway(tester, _GiveawayApi(payload: payload));
          expect(find.text('Contest unavailable'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets('required public sponsor renders contest detail', (
      tester,
    ) async {
      await _pumpGiveaway(tester, _GiveawayApi());
      expect(find.text('REFERRAL CONTEST'), findsOneWidget);
      expect(find.text('Contest unavailable'), findsNothing);
    });

    testWidgets('dynamic nonnegative prizes render without fixed assumptions', (
      tester,
    ) async {
      await _pumpGiveaway(
        tester,
        _GiveawayApi(
          payload: currentPayload(
            contest: {
              ..._contest,
              'prize': {'cashCurrency': 'USD', 'cashMinor': 2500},
            },
          ),
        ),
      );
      expect(find.text(r'US$25'), findsOneWidget);
      expect(find.text(r'US$50 + 5,000 COINS'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _pumpGiveaway(
        tester,
        _GiveawayApi(
          payload: currentPayload(
            contest: {
              ..._contest,
              'prize': {'coins': 1234},
            },
          ),
        ),
      );
      expect(find.text('1,234 COINS'), findsOneWidget);
      expect(find.text('Contest unavailable'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _pumpGiveaway(
        tester,
        _GiveawayApi(
          payload: currentPayload(
            contest: {
              ..._contest,
              'prize': {'coins': 1000000},
            },
          ),
        ),
      );
      expect(find.text('1,000,000 COINS'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _pumpGiveaway(
        tester,
        _GiveawayApi(
          payload: currentPayload(
            contest: {
              ..._contest,
              'prize': {'coins': 1000001},
            },
          ),
        ),
      );
      expect(find.text('Contest unavailable'), findsOneWidget);
    });

    testWidgets(
      'sponsor territory and immutable-rules contract failures fail closed',
      (tester) async {
        final duplicateRegions = [..._allUsRegions]
          ..removeLast()
          ..add('US-AL');
        final invalidContests = <Map<String, dynamic>>[
          {..._contest}..remove('sponsor'),
          {..._contest, 'sponsor': null},
          {..._contest, 'sponsor': 7},
          {
            ..._contest,
            'sponsor': {'legalName': '', 'mailingAddress': '1 Trail Way'},
          },
          {..._contest, 'eligibleRegions': _allUsRegions.take(50).toList()},
          {..._contest, 'eligibleRegions': duplicateRegions},
          {
            ..._contest,
            'rules': {..._contest['rules'] as Map, 'sha256': 'abc123'},
          },
          {
            ..._contest,
            'rules': {
              ..._contest['rules'] as Map,
              'sha256':
                  'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789',
            },
          },
          {
            ..._contest,
            'rules': {..._contest['rules'] as Map, 'sections': const []},
          },
          {
            ..._contest,
            'rules': {
              ..._contest['rules'] as Map,
              'sections': List.generate(
                21,
                (index) => {'heading': 'Rule $index', 'body': 'Body'},
              ),
            },
          },
          {
            ..._contest,
            'rules': {
              ..._contest['rules'] as Map,
              'sections': [
                {'heading': List.filled(121, 'h').join(), 'body': 'Body'},
              ],
            },
          },
          {
            ..._contest,
            'rules': {
              ..._contest['rules'] as Map,
              'sections': [
                {'heading': 'Heading', 'body': List.filled(8001, 'b').join()},
              ],
            },
          },
        ];
        for (final contest in invalidContests) {
          await _pumpGiveaway(
            tester,
            _GiveawayApi(payload: currentPayload(contest: contest)),
          );
          expect(find.text('Contest unavailable'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets('standing counters require coherent rank and reached time', (
      tester,
    ) async {
      final zeroWithRank = currentPayload()
        ..['standing'] = {
          'verifiedCount': 0,
          'reviewableCount': 0,
          'provisionalRank': 1,
          'reachedCountAt': '2026-09-10T12:00:00.000Z',
        };
      final positiveWithoutRank = currentPayload()
        ..['standing'] = {
          'verifiedCount': 3,
          'reviewableCount': 1,
          'provisionalRank': null,
          'reachedCountAt': '2026-09-10T12:00:00.000Z',
        };
      final positiveWithoutReached = currentPayload()
        ..['standing'] = {
          'verifiedCount': 3,
          'reviewableCount': 1,
          'provisionalRank': 8,
          'reachedCountAt': null,
        };
      final actionRequiredReviewable = currentPayload()
        ..['standing'] = {
          'verifiedCount': 0,
          'reviewableCount': 1,
          'provisionalRank': null,
          'reachedCountAt': null,
        };
      final ineligibleScored = currentPayload(entryStatus: 'INELIGIBLE')
        ..['standing'] = {
          'verifiedCount': 1,
          'reviewableCount': 0,
          'provisionalRank': 1,
          'reachedCountAt': '2026-09-10T12:00:00.000Z',
        };
      final scheduledScored = currentPayload(
        contest: {..._contest, 'status': 'SCHEDULED'},
        entryStatus: 'ELIGIBLE',
      );
      final reachedBeforeEntry = currentPayload(entryStatus: 'ELIGIBLE')
        ..['standing'] = {
          'verifiedCount': 1,
          'reviewableCount': 0,
          'provisionalRank': 1,
          'reachedCountAt': '2026-09-02T14:59:59.000Z',
        };
      final reachedAtExclusiveEnd = currentPayload(entryStatus: 'ELIGIBLE')
        ..['standing'] = {
          'verifiedCount': 1,
          'reviewableCount': 0,
          'provisionalRank': 1,
          'reachedCountAt': '2026-10-01T04:00:00.000Z',
        };
      for (final payload in [
        zeroWithRank,
        positiveWithoutRank,
        positiveWithoutReached,
        actionRequiredReviewable,
        ineligibleScored,
        scheduledScored,
        reachedBeforeEntry,
        reachedAtExclusiveEnd,
      ]) {
        await _pumpGiveaway(tester, _GiveawayApi(payload: payload));
        expect(find.text('Contest unavailable'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('rate and body limits stay retryable without losing entry', (
      tester,
    ) async {
      for (final error in const [
        ApiException(
          'Too many entry attempts. Try again later.',
          statusCode: 429,
          code: 'GIVEAWAY_ENTRY_RATE_LIMITED',
        ),
        ApiException(
          'Entry request is too large.',
          statusCode: 413,
          code: 'GIVEAWAY_BODY_TOO_LARGE',
        ),
      ]) {
        final api = _GiveawayApi(entryError: error);
        await _pumpGiveaway(tester, api);
        tester
            .widget<PillButton>(
              find.widgetWithText(PillButton, 'ENTER CONTEST'),
            )
            .onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        for (final key in const [
          Key('giveaway-age-confirmed'),
          Key('giveaway-residency-confirmed'),
          Key('giveaway-rules-accepted'),
        ]) {
          await tester.ensureVisible(find.byKey(key));
          await tester.tap(find.byKey(key));
        }
        await tester.ensureVisible(
          find.byKey(const Key('giveaway-region-field')),
        );
        await tester.tap(find.byKey(const Key('giveaway-region-field')));
        await tester.pump();
        await tester.tap(find.text('Alabama'));
        await tester.pump();
        final button = find.widgetWithText(PillButton, 'CONFIRM ENTRY');
        await tester.ensureVisible(button);
        tester.widget<PillButton>(button).onPressed!();
        await tester.pump();
        expect(find.text(error.message), findsOneWidget);
        expect(find.text('CONFIRM ENTRY'), findsWidgets);
        expect(api.entryCalls, 1);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('rules and disclosures stay in-app', (tester) async {
      await _pumpGiveaway(tester, _GiveawayApi());
      await tester.ensureVisible(find.text('OFFICIAL RULES'));
      await tester.pump(const Duration(milliseconds: 100));
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'OFFICIAL RULES'))
          .onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GiveawayRulesScreen), findsOneWidget);
      expect(find.text('How to enter'), findsOneWidget);
      expect(find.text('Bara LLC'), findsOneWidget);
      expect(find.text('1 Trail Way'), findsOneWidget);
      expect(
        find.textContaining('Apple and Google are not sponsors'),
        findsWidgets,
      );
    });

    testWidgets(
      'narrow large-text dark surface remains scrollable and disclosed',
      (tester) async {
        await _pumpGiveaway(
          tester,
          _GiveawayApi(),
          themeMode: ThemeMode.dark,
          size: const Size(320, 700),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        await tester.fling(
          find.byType(Scrollable).first,
          const Offset(0, -1200),
          900,
        );
        await tester.pump();
        expect(find.textContaining('Apple and Google'), findsOneWidget);
      },
    );
  });

  group('shared referral discovery', () {
    testWidgets(
      'active contest card sits once above YOUR INVITES and opens detail',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final auth = await _auth();
        final api = _GiveawayApi();
        await tester.pumpWidget(
          MaterialApp(
            home: ReferralScreen(authService: auth, backendApiService: api),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('referral-contest-card')), findsOneWidget);
        expect(
          find.textContaining('Ends 2026-10-01 04:00 UTC'),
          findsOneWidget,
        );
        final cardY = tester
            .getTopLeft(find.byKey(const Key('referral-contest-card')))
            .dy;
        final invitesY = tester.getTopLeft(find.text('YOUR INVITES')).dy;
        expect(cardY, lessThan(invitesY));
        await tester.ensureVisible(find.text('VIEW CONTEST'));
        await tester.pump(const Duration(milliseconds: 100));
        tester
            .widget<PillButton>(find.widgetWithText(PillButton, 'VIEW CONTEST'))
            .onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(GiveawayScreen), findsOneWidget);
      },
    );

    testWidgets('contest card formats each enabled dynamic prize', (
      tester,
    ) async {
      for (final prizeCase in [
        (
          prize: <String, dynamic>{'cashCurrency': 'USD', 'cashMinor': 2500},
          label: r'Win US$25',
        ),
        (prize: <String, dynamic>{'coins': 1234}, label: 'Win 1,234 coins'),
      ]) {
        final auth = await _auth();
        final api = _GiveawayApi(
          payload: currentPayload(
            contest: {..._contest, 'prize': prizeCase.prize},
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ReferralScreen(authService: auth, backendApiService: api),
          ),
        );
        await tester.pump();
        expect(find.text(prizeCase.label), findsOneWidget);
        expect(find.textContaining(r'US$0 +'), findsNothing);
        expect(find.textContaining('+ 0 coins'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('404/malformed contest does not block ordinary referral UI', (
      tester,
    ) async {
      for (final api in [
        _GiveawayApi(error: const ApiException('missing', statusCode: 404)),
        _GiveawayApi(
          payload: {
            'contest': {'slug': 9},
          },
        ),
      ]) {
        final auth = await _auth();
        await tester.pumpWidget(
          MaterialApp(
            home: ReferralScreen(authService: auth, backendApiService: api),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('referral-contest-card')), findsNothing);
        expect(find.text('SHARE YOUR INVITE'), findsOneWidget);
        expect(find.text('Program rules'), findsOneWidget);
      }
    });
  });

  testWidgets(
    'Home only navigates for a valid typed contest action and suppresses tutorial',
    (tester) async {
      final auth = await _auth();
      Widget home(Map<String, dynamic>? banner, {bool tutorial = false}) =>
          MaterialApp(
            key: ValueKey('${banner?['message']}-$tutorial'),
            home: Scaffold(
              body: HomeTab(
                stepData: StepData(steps: 1000, date: DateTime(2026, 8, 25)),
                isLoading: false,
                error: null,
                healthAuthorized: true,
                notificationsState: true,
                displayName: 'Trail Walker',
                authService: auth,
                backendApiService: _GiveawayApi(),
                onRefresh: () async {},
                onEnableHealth: () {},
                onEnableNotifications: () {},
                onDisplayNameChanged: () {},
                friendsSteps: const [],
                suggestedRacesState: const Loadable.success([]),
                raceCard: {'state': 'EMPTY', 'homeServiceBanner': banner},
                isTutorialPreview: tutorial,
              ),
            ),
          );

      await tester.pumpWidget(
        home({
          'enabled': true,
          'message': r'Win US$50 + 5,000 coins',
          'action': {'type': 'contest', 'contestSlug': 'bara-referral-2026-09'},
        }),
      );
      await tester.ensureVisible(find.byKey(const Key('home-service-banner')));
      await tester.pump(const Duration(milliseconds: 100));
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(const Key('home-service-banner')),
              matching: find.byType(InkWell),
            ),
          )
          .onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GiveawayScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(GiveawayScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.pumpWidget(
        home({
          'enabled': true,
          'message': 'Maintenance tonight',
          'action': {'type': 'contest', 'contestSlug': 7},
        }),
      );
      expect(find.byKey(const Key('home-service-banner')), findsNothing);
      expect(find.byType(GiveawayScreen), findsNothing);

      await tester.pumpWidget(
        home({'enabled': true, 'message': 'Maintenance tomorrow'}),
      );
      expect(find.byKey(const Key('home-service-banner')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('home-service-banner')),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );

      await tester.pumpWidget(
        home({
          'enabled': true,
          'message': r'Win US$50 + 5,000 coins',
          'action': {'type': 'contest', 'contestSlug': 'bara-referral-2026-09'},
        }, tutorial: true),
      );
      expect(find.byKey(const Key('home-service-banner')), findsNothing);
    },
  );
}
