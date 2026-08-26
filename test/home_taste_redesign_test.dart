import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/arcade_fx.dart';

class _TasteHomeApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => const {'claimedToday': false};
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

  testWidgets(
    'daily reward is primary and Shop is a compact secondary action',
    (tester) async {
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
      expect(
        tester.getSize(reward).width,
        greaterThan(tester.getSize(shop).width * 2),
      );
      expect(tester.getSize(shop), const Size(80, 58));
      final compactReward = find.byKey(
        const Key('home-daily-reward-compact-layout'),
      );
      expect(tester.getSize(compactReward).height, 58);
      final rewardIcon = find.descendant(
        of: compactReward,
        matching: find.byType(Icon),
      );
      final rewardLabel = find.descendant(
        of: compactReward,
        matching: find.byType(Text),
      );
      expect(
        tester.getRect(rewardIcon).bottom,
        lessThan(tester.getRect(rewardLabel).top),
      );
      expect(
        tester.getRect(rewardIcon).center.dx,
        closeTo(tester.getRect(rewardLabel).center.dx, 1),
      );
      final rewardStyle = tester.widget<Text>(rewardLabel).style!;
      final shopStyle = tester.widget<Text>(find.text('SHOP')).style!;
      final alertsStyle = tester.widget<Text>(find.text('ALERTS')).style!;
      expect(rewardStyle.fontFamily, shopStyle.fontFamily);
      expect(alertsStyle.fontFamily, shopStyle.fontFamily);
      expect(rewardStyle.fontSize, shopStyle.fontSize);
      expect(alertsStyle.fontSize, shopStyle.fontSize);
      final arcadeStyle = PixelText.pill(size: 14);
      expect(rewardStyle.fontFamily, arcadeStyle.fontFamily);
      expect(rewardStyle.fontSize, arcadeStyle.fontSize);
      final alertsText = tester.widget<Text>(find.text('ALERTS'));
      expect(alertsText.data, 'ALERTS');
      expect(alertsText.softWrap, isFalse);
      expect(alertsText.overflow, TextOverflow.visible);
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

  testWidgets('Home ends with the compact Feedback section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _TasteHomeApi();
    final auth = await _auth(api);

    await tester.pumpWidget(_home(auth, api));
    await _flush(tester);

    final feedback = find.byKey(const Key('home-feedback-card'));
    expect(feedback, findsOneWidget);
    expect(find.byKey(const Key('home-feedback-button')), findsOneWidget);
    expect(find.text('FEEDBACK'), findsOneWidget);
    expect(
      tester.getTopLeft(feedback).dy,
      greaterThan(tester.getTopLeft(find.text('SUGGESTED RACES')).dy),
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
