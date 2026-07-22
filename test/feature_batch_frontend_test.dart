import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/screens/daily_reward_screen.dart';
import 'package:step_tracker/screens/multi_case_opening_screen.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';
import 'package:step_tracker/widgets/ad_banner_slot.dart';
import 'package:step_tracker/widgets/wooden_tab_bar.dart';
import 'package:step_tracker/widgets/home_hero_scene.dart';

class _CapturedRequest {
  String body = '';
}

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(utf8.encode('{"result":{}}')).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.capture);
  final _CapturedRequest capture;
  @override
  final HttpHeaders headers = _Headers();
  @override
  void write(Object? object) => capture.body = object.toString();
  @override
  Future<HttpClientResponse> close() async => _Response();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Client implements HttpClient {
  final capture = _CapturedRequest();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(capture);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DailyApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => const {
    'cycleLength': 6,
    'currentDay': 1,
    'claimedToday': true,
    'ladder': [],
  };
}

class _StatsApi extends BackendApiService {
  _StatsApi(this.stats);
  final Map<String, dynamic> stats;

  @override
  Future<Map<String, dynamic>> fetchAdminStats({
    required String identityToken,
  }) async => stats;
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'user',
    'auth_session_token': 'session',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_timezone'),
        (call) async => 'America/New_York',
      );
  test('new capability tokens are advertised without dropping old tokens', () {
    final tokens = BackendApiService.clientFeaturesHeader.split(',');
    expect(
      tokens,
      containsAll(<String>[
        'powerups3',
        'powerups4',
        'stealth_runner_duration',
        'hitchhike_effective_steps',
      ]),
    );
  });

  test(
    'sign out clears both persisted and live banner rollout flags',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'token',
        'auth_user_identifier': 'user',
        'auth_banner_ads_enabled': true,
        'auth_dual_box_banners_enabled': true,
      });
      final auth = AuthService();
      await auth.restoreSession();
      expect(AdService.remoteBannersEnabled, isTrue);
      expect(AdService.remoteDualBoxBannersEnabled, isTrue);

      await auth.signOut();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('auth_banner_ads_enabled'), isFalse);
      expect(prefs.containsKey('auth_dual_box_banners_enabled'), isFalse);
      expect(AdService.remoteBannersEnabled, isFalse);
      expect(AdService.remoteDualBoxBannersEnabled, isFalse);
    },
  );

  test('Quicksand has player copy and an icon mapping', () {
    expect(PowerupCopy.nameFor('QUICKSAND'), 'Quicksand');
    expect(PowerupCopy.descriptionFor('QUICKSAND'), contains('three'));
    expect(
      PowerupIcon.assetPathFor('QUICKSAND'),
      'assets/images/powerups/quicksand.png',
    );
    expect(kTargetedPowerupTypes, contains('QUICKSAND'));
  });

  test('Quicksand request serializes only ordered targetUserIds', () async {
    final client = _Client();
    final api = BackendApiService(httpClient: client);
    await api.useQuicksand(
      identityToken: 'token',
      raceId: 'race',
      powerupId: 'sand',
      targetUserIds: const ['u2', 'u1', 'u3'],
    );
    expect(jsonDecode(client.capture.body), {
      'targetUserIds': ['u2', 'u1', 'u3'],
    });
  });

  testWidgets('light navigation uses white for the unselected icon and label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: Scaffold(
          body: WoodenTabBar(
            currentIndex: 0,
            onTap: (_) {},
            items: const [
              WoodenTabItem(icon: Icons.home, label: 'HOME'),
              WoodenTabItem(icon: Icons.flag, label: 'RACES'),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('RACES')).style?.color,
      AppColors.textLight,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.flag)).color,
      AppColors.textLight,
    );
  });

  testWidgets('single and Open All routes mount top and bottom banner slots', (
    tester,
  ) async {
    AdService.remoteDualBoxBannersEnabled = true;
    addTearDown(() => AdService.remoteDualBoxBannersEnabled = false);

    await tester.pumpWidget(
      MaterialApp(
        home: CaseOpeningScreen(openMysteryBox: () async => const {}),
      ),
    );
    expect(find.byType(AdBannerSlot), findsNWidgets(2));
    for (final element in find.byType(AdBannerSlot).evaluate()) {
      expect(tester.getSize(find.byWidget(element.widget).first).height, 0);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MultiCaseOpeningScreen(
          boxCount: 2,
          openAll: () async => const [],
        ),
      ),
    );
    expect(find.byType(AdBannerSlot), findsNWidgets(2));
  });

  testWidgets('daily reward retains footer and adds a separate top slot', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'token',
      'auth_user_identifier': 'user',
      'auth_session_token': 'session',
    });
    final auth = AuthService();
    await auth.restoreSession();
    AdService.remoteDualBoxBannersEnabled = true;
    addTearDown(() => AdService.remoteDualBoxBannersEnabled = false);
    await tester.pumpWidget(
      MaterialApp(
        home: DailyRewardScreen(
          authService: auth,
          backendApiService: _DailyApi(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AdBannerSlot), findsNWidgets(2));
  });

  testWidgets('admin rewarded-ad rows render complete and malformed payloads', (
    tester,
  ) async {
    final auth = await _auth();
    Future<void> pump(Map<String, dynamic> stats) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminStatsCard(
                width: 430,
                authService: auth,
                backendApiService: _StatsApi(stats),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pump(const {
      'activity': {
        'dauToday': 120,
        'rewardedAds': {
          'coinReward': {'uniqueDauWatchers': 18, 'pctOfDau': 15},
          'extraSpin': {'uniqueDauWatchers': 9, 'pctOfDau': 8},
        },
      },
    });
    expect(find.text('18 (15%)'), findsOneWidget);
    expect(find.text('9 (8%)'), findsOneWidget);

    await pump(const {
      'activity': {
        'rewardedAds': {
          'coinReward': {'uniqueDauWatchers': '18', 'pctOfDau': null},
        },
      },
    });
    expect(find.text('DAU watched coin ad'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'five cloud assets move right-to-left and freeze for reduced motion',
    (tester) async {
      Future<void> pump({required bool reduced}) => tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.light(),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const SizedBox(
              width: 430,
              height: 400,
              child: HomeHeroScene(child: SizedBox.expand()),
            ),
          ),
        ),
      );

      await pump(reduced: false);
      final before = <double>[
        for (var i = 0; i < 5; i++)
          tester.getTopLeft(find.byKey(ValueKey('home-cloud-$i'))).dx,
      ];
      await tester.pump(const Duration(milliseconds: 100));
      final after = <double>[
        for (var i = 0; i < 5; i++)
          tester.getTopLeft(find.byKey(ValueKey('home-cloud-$i'))).dx,
      ];
      for (var i = 0; i < 5; i++) {
        expect(after[i], lessThan(before[i]));
      }

      await pump(reduced: true);
      final frozen = tester
          .getTopLeft(find.byKey(const ValueKey('home-cloud-0')))
          .dx;
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('home-cloud-0'))).dx,
        frozen,
      );
    },
  );
}
