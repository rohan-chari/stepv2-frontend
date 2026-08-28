import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/arcade_fx.dart';

class _TasteHomeApi extends BackendApiService {
  _TasteHomeApi({this.dailyStatus = const {'claimedToday': false}});

  final Map<String, dynamic> dailyStatus;

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => dailyStatus;
}

class _SupportedDailyRewardAds implements ExtraSpinAdController {
  @override
  bool get isReady => true;

  @override
  bool get isSupported => true;

  @override
  Future<void> load({
    required String userId,
    required String localDate,
  }) async {}

  @override
  Future<bool> showAndAwaitReward() async => true;

  @override
  void dispose() {}
}

Future<AuthService> _auth(_TasteHomeApi api, {bool hasPhoto = true}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'identity-token',
    'auth_user_identifier': 'user-identifier',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'SwiftCapybara07',
    if (hasPhoto) 'auth_profile_photo_url': 'https://example.test/profile.png',
    'auth_onboarding_v3_enabled': true,
  });
  final auth = AuthService(backendApiService: api);
  await auth.restoreSession();
  return auth;
}

Map<String, dynamic> _pendingInvite() => {
  'state': 'PENDING_INVITE',
  'data': {
    'raceId': 'race-1',
    'inviter': {'userId': 'friend-1', 'displayName': 'Jordan'},
    'participantCount': 3,
    'durationHours': 24,
  },
};

Widget _home(
  AuthService auth,
  _TasteHomeApi api, {
  Map<String, dynamic>? raceCard,
  Loadable<List<HomeRaceSuggestion>> suggestions = const Loadable.success([]),
  ExtraSpinAdController? dailyRewardAdController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: HomeTab(
        stepData: StepData(steps: 6432, date: DateTime(2026, 8, 26)),
        isLoading: false,
        error: null,
        healthAuthorized: true,
        notificationsState: true,
        displayName: 'SwiftCapybara07',
        authService: auth,
        backendApiService: api,
        onRefresh: () async {},
        onEnableHealth: () {},
        onEnableNotifications: () {},
        onDisplayNameChanged: () {},
        friendsSteps: const [],
        raceCard: raceCard ?? const {'state': 'EMPTY'},
        suggestedRacesState: suggestions,
        dailyRewardAdController: dailyRewardAdController,
        onOpenShop: () {},
        onAcceptRaceInvite: (_) async {},
        onDeclineRaceInvite: (_) async {},
      ),
    ),
  );
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.2.4',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('daily reward and Shop use equal-sized buttons', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _TasteHomeApi();
    final auth = await _auth(api);

    await tester.pumpWidget(_home(auth, api));
    await _flush(tester);

    final reward = find.byKey(const Key('home-daily-reward-button'));
    final shop = find.byKey(const Key('home-shop-button'));
    expect(reward, findsOneWidget);
    expect(shop, findsOneWidget);
    expect(tester.getSize(reward), tester.getSize(shop));
    expect(tester.getSize(shop).height, greaterThanOrEqualTo(48));
    final compactReward = find.byKey(
      const Key('home-daily-reward-compact-layout'),
    );
    expect(tester.getSize(compactReward).height, greaterThanOrEqualTo(44));
    final rewardIcon = find.descendant(
      of: compactReward,
      matching: find.byType(Icon),
    );
    final rewardLabel = find.descendant(
      of: compactReward,
      matching: find.byType(Text),
    );
    expect(
      tester.getRect(rewardIcon).center.dx,
      lessThan(tester.getRect(rewardLabel).center.dx),
    );
    expect(
      tester.getRect(rewardIcon).center.dy,
      closeTo(tester.getRect(rewardLabel).center.dy, 1),
    );
    final rewardStyle = tester.widget<Text>(rewardLabel).style!;
    final shopStyle = tester.widget<Text>(find.text('SHOP')).style!;
    expect(rewardStyle.fontFamily, shopStyle.fontFamily);
    expect(rewardStyle.fontSize, shopStyle.fontSize);
    expect(rewardStyle.fontSize, greaterThanOrEqualTo(13));
    expect(find.text('ALERTS'), findsNothing);
  });

  testWidgets(
    'quick-action labels stay at 13px and inside every supported button state',
    (WidgetTester tester) async {
      for (final width in const [320.0, 360.0, 390.0, 430.0]) {
        for (final state in const <(String, Map<String, dynamic>)>[
          ('unclaimed', {'claimedToday': false}),
          (
            'claimed',
            {
              'claimedToday': true,
              'adExtraSpin': {
                'available': false,
                'pendingGrant': false,
                'used': true,
              },
            },
          ),
          (
            'bonus',
            {
              'claimedToday': true,
              'adExtraSpin': {
                'available': true,
                'pendingGrant': false,
                'used': false,
              },
            },
          ),
        ]) {
          await tester.binding.setSurfaceSize(Size(width, 844));
          final api = _TasteHomeApi(dailyStatus: state.$2);
          final auth = await _auth(api);
          await tester.pumpWidget(
            _home(
              auth,
              api,
              dailyRewardAdController: _SupportedDailyRewardAds(),
            ),
          );
          await _flush(tester);

          final reward = find.byKey(const Key('home-daily-reward-button'));
          final shop = find.byKey(const Key('home-shop-button'));
          expect(tester.getSize(reward), tester.getSize(shop));
          expect(
            find.descendant(of: reward, matching: find.byType(FittedBox)),
            findsNothing,
            reason: 'reward width=$width state=${state.$1}',
          );
          expect(
            find.descendant(of: shop, matching: find.byType(FittedBox)),
            findsNothing,
            reason: 'shop width=$width state=${state.$1}',
          );
          final rewardTextFinders = find.descendant(
            of: reward,
            matching: find.byType(Text),
          );
          final rewardRect = tester.getRect(reward);
          for (final textFinder in rewardTextFinders.evaluate().map(
            (element) =>
                find.byElementPredicate((candidate) => candidate == element),
          )) {
            final text = tester.widget<Text>(textFinder);
            expect(
              text.style?.fontSize,
              greaterThanOrEqualTo(13),
              reason: 'reward width=$width state=${state.$1}',
            );
            final textRect = tester.getRect(textFinder);
            expect(textRect.left, greaterThanOrEqualTo(rewardRect.left));
            expect(textRect.right, lessThanOrEqualTo(rewardRect.right));
            expect(textRect.top, greaterThanOrEqualTo(rewardRect.top));
            expect(textRect.bottom, lessThanOrEqualTo(rewardRect.bottom));
          }
          expect(
            tester.widget<Text>(find.text('SHOP')).style?.fontSize,
            greaterThanOrEqualTo(13),
          );
          expect(tester.takeException(), isNull);
        }
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    },
  );

  testWidgets('a pending invite outranks incomplete setup', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _TasteHomeApi();
    final auth = await _auth(api, hasPhoto: false);

    await tester.pumpWidget(_home(auth, api, raceCard: _pendingInvite()));
    await _flush(tester);

    final invite = find.byKey(const Key('home-pending-invite'));
    final setup = find.text('SETUP');
    expect(invite, findsOneWidget);
    expect(setup, findsOneWidget);
    expect(tester.getTopLeft(invite).dy, lessThan(tester.getTopLeft(setup).dy));
  });

  testWidgets('Home ends with the restored Feedback section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _TasteHomeApi();
    final auth = await _auth(api);

    await tester.pumpWidget(_home(auth, api));
    await _flush(tester);

    final feedback = find.byKey(const Key('home-feedback-card'));
    expect(feedback, findsOneWidget);
    expect(find.byKey(const Key('home-feedback-button')), findsOneWidget);
    expect(find.text('Found a bug? Have an idea? Let us know'), findsOneWidget);
    expect(find.text('SEND FEEDBACK'), findsOneWidget);
    expect(
      tester.getTopLeft(feedback).dy,
      greaterThan(tester.getTopLeft(find.text('Suggested Races')).dy),
    );
  });

  testWidgets('only the first below-hero content group staggers into place', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _TasteHomeApi();
    final auth = await _auth(api);

    await tester.pumpWidget(_home(auth, api, raceCard: _pendingInvite()));
    await _flush(tester);

    expect(find.byType(StaggerIn), findsOneWidget);
  });
}
