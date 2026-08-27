import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/giveaway_screen.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/home_giveaway_banner.dart';

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

  test('Home contest card source keeps its attention treatment restrained', () {
    final source = File(
      'lib/widgets/home_giveaway_banner.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('Gradient')));
    expect(source.toLowerCase(), isNot(contains('shimmer')));
    expect(source, contains('MediaQuery.disableAnimationsOf'));
    expect(source, isNot(contains('BoxShadow')));
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
    final semantics = tester.getSemantics(
      find.byKey(const Key('home-giveaway-banner-tap')),
    );
    expect(semantics.label, contains('View contest'));
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    expect(
      tester.getSize(find.byKey(const Key('home-giveaway-banner'))).height,
      lessThan(100),
      reason: 'the Home contest promotion should read as a compact notice',
    );

    final shopY = tester
        .getTopLeft(find.byKey(const Key('home-shop-button')))
        .dy;
    final bannerY = tester
        .getTopLeft(find.byKey(const Key('home-giveaway-banner')))
        .dy;
    expect(bannerY, greaterThan(shopY));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('contest banner matches the compact 2x notice treatment', (
    tester,
  ) async {
    Widget bannerFor(ThemeMode themeMode) => MaterialApp(
      theme: AppThemeData.light(),
      darkTheme: AppThemeData.night(),
      themeMode: themeMode,
      home: Scaffold(
        body: HomeGiveawayBanner(
          message: 'Bara Referral Contest is open now.',
          coinPrize: 5000,
          endsAt: DateTime.now().add(const Duration(days: 2)),
          onTap: () {},
        ),
      ),
    );

    await tester.pumpWidget(bannerFor(ThemeMode.light));
    var banner = tester.widget<Container>(
      find.byKey(const Key('home-giveaway-banner')),
    );
    var decoration = banner.decoration! as BoxDecoration;
    expect(decoration.color, AppPalette.light.parchmentLight);
    expect(
      (decoration.border! as Border).top.color,
      AppPalette.light.woodDark.withValues(alpha: 0.28),
    );

    await tester.pumpWidget(bannerFor(ThemeMode.dark));
    await tester.pump(const Duration(milliseconds: 250));

    banner = tester.widget<Container>(
      find.byKey(const Key('home-giveaway-banner')),
    );
    decoration = banner.decoration! as BoxDecoration;
    expect(decoration.color, AppPalette.night.parchmentLight);
    expect(decoration.border, isA<Border>());
    expect(
      (decoration.border! as Border).top.color,
      AppPalette.night.woodDark.withValues(alpha: 0.28),
    );

    expect(find.textContaining('WIN 5,000 COINS · ENDS IN'), findsOneWidget);

    final headline = tester.widget<Text>(
      find.text('Bara Referral Contest is open now.'),
    );
    expect(headline.style?.color, AppPalette.night.textDark);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.emoji_events_rounded)).color,
      AppPalette.night.textLight,
    );
    expect(
      tester.widget<Text>(find.textContaining('WIN 5,000 COINS')).style?.color,
      AppPalette.night.textMid,
    );
    expect(
      tester.widget<Text>(find.text('VIEW')).style?.color,
      AppPalette.night.textLight,
    );
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

  testWidgets('card seesaws briefly, rests, and honors reduced motion', (
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
    final motion = find.byKey(const Key('home-giveaway-banner-motion'));
    expect(motion, findsOneWidget);
    final atStart = List<double>.of(
      tester.widget<Transform>(motion).transform.storage,
    );
    await tester.pump(const Duration(milliseconds: 180));
    final duringBeat = List<double>.of(
      tester.widget<Transform>(motion).transform.storage,
    );
    expect(duringBeat, isNot(atStart));
    final angle = math.atan2(duringBeat[1], duringBeat[0]).abs();
    expect(angle, lessThanOrEqualTo(.0121));
    await tester.pump(const Duration(milliseconds: 700));
    final atRest = tester.widget<Transform>(motion).transform;
    expect(atRest, Matrix4.identity());
    await tester.pump(const Duration(milliseconds: 6200));
    await tester.pump(const Duration(milliseconds: 180));
    final secondBeat = tester.widget<Transform>(motion).transform;
    expect(secondBeat, isNot(Matrix4.identity()));

    await tester.pumpWidget(
      _home(auth, banner: _validBanner(), tutorial: true),
    );
    await tester.pump();
    expect(find.byKey(const Key('home-giveaway-banner')), findsNothing);
  });

  testWidgets('motion stays stopped when mounted paused and resumes safely', (
    tester,
  ) async {
    final auth = await _auth();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    try {
      await tester.pumpWidget(_home(auth, banner: _validBanner()));
      await tester.pump();
      expect(
        find.byKey(const Key('home-giveaway-banner-motion')),
        findsNothing,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        find.byKey(const Key('home-giveaway-banner-motion')),
        findsOneWidget,
      );
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });
}
