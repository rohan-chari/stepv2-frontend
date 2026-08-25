import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/giveaway_screen.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _HomeGiveawayApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => const {'claimedToday': true};

  @override
  Future<Map<String, dynamic>> fetchCurrentGiveaway({
    required String identityToken,
  }) async {
    final now = DateTime.now().toUtc();
    return {
      'contest': {
        'slug': 'bara-referral-2026-09',
        'title': 'Bara Referral Contest',
        'status': 'ACTIVE',
        'startsAt': now.subtract(const Duration(days: 1)).toIso8601String(),
        'endsAt': now.add(const Duration(days: 10)).toIso8601String(),
        'timezone': 'America/New_York',
        'eligibleRegions': ['US-AL'],
        'prize': {'cashMinor': 0, 'cashCurrency': 'USD', 'coinPrize': 5000},
        'rules': {
          'version': 'bara-referral-standard-v1',
          'sha256': 'a' * 64,
          'sections': [
            {
              'heading': 'How to enter',
              'body': 'Refer friends.',
              'sortOrder': 0,
            },
          ],
        },
        'sponsor': {'legalName': 'Bara', 'mailingAddress': '100 Main St'},
        'bannerMessage': 'Bara Referral Contest: win 5,000 coins.',
        'socialLinks': [],
      },
      'entry': null,
      'standing': null,
      'share': null,
    };
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
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

Widget _home(
  AuthService auth, {
  Object? banner,
  bool includeBanner = false,
  bool tutorial = false,
  bool reducedMotion = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(800, 1200),
        disableAnimations: reducedMotion,
      ),
      child: Scaffold(
        body: HomeTab(
          stepData: StepData(steps: 2400, date: DateTime(2026, 8, 25)),
          isLoading: false,
          error: null,
          healthAuthorized: true,
          notificationsState: true,
          displayName: 'Trail Walker',
          authService: auth,
          backendApiService: _HomeGiveawayApi(),
          onRefresh: () async {},
          onEnableHealth: () {},
          onEnableNotifications: () {},
          onDisplayNameChanged: () {},
          friendsSteps: const [],
          suggestedRacesState: const Loadable.success([]),
          raceCard: {
            'state': 'EMPTY',
            if (banner != null || includeBanner) 'homeGiveawayBanner': banner,
            'homeServiceBanner': {
              'enabled': true,
              'message': 'Legacy manual contest promotion',
              'action': {
                'type': 'contest',
                'contestSlug': 'bara-referral-2026-09',
              },
            },
          },
          isTutorialPreview: tutorial,
        ),
      ),
    ),
  );
}

Map<String, dynamic> _validBanner({
  String? endsAt,
  Object? coinPrize = 5000,
  Object? status = 'ACTIVE',
  Object? type = 'referral_contest',
  Object? message = 'Bring your crew. The referral trail is open.',
}) => {
  'type': type,
  'contestSlug': 'bara-referral-2026-09',
  'title': 'Bara Referral Contest',
  'message': message,
  'status': status,
  'endsAt':
      endsAt ??
      DateTime.now().toUtc().add(const Duration(hours: 4)).toIso8601String(),
  'coinPrize': coinPrize,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Home contest card source contains no gradient, shimmer, or motion', () {
    final source = File(
      'lib/widgets/home_giveaway_banner.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('Gradient')));
    expect(source.toLowerCase(), isNot(contains('shimmer')));
    expect(source, isNot(contains('AnimationController')));
    expect(source, isNot(contains('AnimatedBuilder')));
  });

  testWidgets('renders a valid automatic active contest banner', (
    tester,
  ) async {
    final auth = await _auth();
    await tester.pumpWidget(_home(auth, banner: _validBanner()));
    await tester.pump();

    expect(find.byKey(const Key('home-giveaway-banner')), findsOneWidget);
    expect(
      find.text('Bring your crew. The referral trail is open.'),
      findsOneWidget,
    );
    expect(find.textContaining('5,000 COINS'), findsOneWidget);
    expect(find.textContaining('ENDS IN'), findsOneWidget);
    expect(find.text('VIEW'), findsOneWidget);
    expect(find.textContaining('US\$'), findsNothing);
    expect(find.byKey(const Key('home-service-banner')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ignores missing or malformed automatic banner data', (
    tester,
  ) async {
    final auth = await _auth();
    final malformed = <Object?>[
      null,
      'banner',
      {..._validBanner(), 'type': 'service'},
      {..._validBanner(), 'contestSlug': 7},
      {..._validBanner(), 'title': ''},
      {..._validBanner(), 'message': null},
      {..._validBanner(), 'message': 'Too short'},
      {..._validBanner(), 'message': 'Win cash with your friends today.'},
      {..._validBanner(), 'message': 'Line one\nLine two makes it long enough'},
      {..._validBanner(), 'status': 'SCHEDULED'},
      {..._validBanner(), 'endsAt': 'not-a-date'},
      {..._validBanner(), 'coinPrize': 5000.5},
      {..._validBanner(), 'coinPrize': 0},
    ];

    for (final value in malformed) {
      await tester.pumpWidget(_home(auth, banner: value, includeBanner: true));
      await tester.pump();
      expect(find.byKey(const Key('home-giveaway-banner')), findsNothing);
      expect(find.byKey(const Key('home-service-banner')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('self-hides an expired banner and preserves Home', (
    tester,
  ) async {
    final auth = await _auth();
    await tester.pumpWidget(
      _home(
        auth,
        banner: _validBanner(
          endsAt: DateTime.now()
              .toUtc()
              .add(const Duration(milliseconds: 120))
              .toIso8601String(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('home-giveaway-banner')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpWidget(
      _home(
        auth,
        banner: _validBanner(
          endsAt: DateTime.now()
              .toUtc()
              .subtract(const Duration(milliseconds: 10))
              .toIso8601String(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('home-giveaway-banner')), findsNothing);
    expect(find.byKey(const Key('home-service-banner')), findsOneWidget);
  });

  testWidgets('valid automatic banner wins over a legacy manual banner', (
    tester,
  ) async {
    final auth = await _auth();
    await tester.pumpWidget(_home(auth, banner: _validBanner()));
    await tester.pump();
    expect(find.byKey(const Key('home-giveaway-banner')), findsOneWidget);
    expect(find.text('Legacy manual contest promotion'), findsNothing);
  });

  testWidgets('tapping automatic banner opens the matching giveaway', (
    tester,
  ) async {
    final auth = await _auth();
    await tester.pumpWidget(_home(auth, banner: _validBanner()));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('home-giveaway-banner-tap')),
    );
    final tap = tester.widget<InkWell>(
      find.byKey(const Key('home-giveaway-banner-tap')),
    );
    expect(tap.onTap, isNotNull);
    tap.onTap!();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      Navigator.of(tester.element(find.byType(HomeTab))).canPop(),
      isTrue,
      reason: 'automatic contest tap should push a route',
    );
    expect(find.byType(GiveawayScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('card has no motion in any mode and tutorial suppresses banner', (
    tester,
  ) async {
    final auth = await _auth();
    await tester.pumpWidget(
      _home(auth, banner: _validBanner(), reducedMotion: true),
    );
    await tester.pump();
    expect(find.byKey(const Key('home-giveaway-banner')), findsOneWidget);
    expect(find.byKey(const Key('home-giveaway-banner-motion')), findsNothing);

    await tester.pumpWidget(_home(auth, banner: _validBanner()));
    await tester.pump();
    expect(find.byKey(const Key('home-giveaway-banner-motion')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-giveaway-banner')),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
    );

    await tester.pumpWidget(
      _home(auth, banner: _validBanner(), tutorial: true),
    );
    await tester.pump();
    expect(find.byKey(const Key('home-giveaway-banner')), findsNothing);
  });
}
