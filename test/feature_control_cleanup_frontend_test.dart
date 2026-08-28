import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/utils/funded_exposure_error_copy.dart';
import 'package:step_tracker/widgets/quick_create_race_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.8',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('locked compatibility envelope stays version-skew safe', () {
    test('new backend values select the permanent product behavior', () {
      final auth = AuthService();
      auth.applyBackendUser(const {
        'featureFlags': {
          'teamRacesEnabled': true,
          'customRaceWindowEnabled': true,
          'onboardingV2Enabled': true,
          'onboardingV3Enabled': true,
          'onboardingInviteCodeEnabled': false,
          'setupInviteCodePromptEnabled': true,
          'tutorialMandatoryEnabled': true,
          'stepSampleBucketMinutes': 5,
        },
      }, authoritative: true);

      expect(auth.teamRacesEnabled, isTrue);
      expect(auth.customRaceWindowEnabled, isTrue);
      expect(auth.onboardingV3Enabled, isTrue);
      expect(auth.setupInviteCodePromptEnabled, isTrue);
      expect(auth.tutorialMandatoryEnabled, isTrue);
      expect(auth.stepSampleBucketMinutes, 5);
    });

    test('banner settings reactivate the runtime ad gate', () async {
      SharedPreferences.setMockInitialValues(const {
        'auth_banner_ads_enabled': false,
        'auth_dual_box_banners_enabled': false,
      });
      final auth = AuthService();
      await auth.restoreSession();

      expect(auth.bannerAdsEnabled, isTrue);
      expect(auth.dualBoxBannersEnabled, isTrue);

      auth.applyBackendUser(const {
        'featureFlags': {
          'bannerAdsEnabled': false,
          'dualBoxBannersEnabled': false,
        },
      }, authoritative: true);

      expect(auth.bannerAdsEnabled, isFalse);
      expect(auth.dualBoxBannersEnabled, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('auth_banner_ads_enabled'), isFalse);
      expect(prefs.containsKey('auth_dual_box_banners_enabled'), isFalse);
    });

    test('missing and malformed old-backend fields retain safe downgrade', () {
      final auth = AuthService();
      auth.applyBackendUser(const {
        'featureFlags': {
          'customRaceWindowEnabled': null,
          'onboardingV3Enabled': 'yes',
          'tutorialMandatoryEnabled': 1,
          'stepSampleBucketMinutes': '5',
        },
      }, authoritative: true);

      expect(auth.teamRacesEnabled, isTrue);
      expect(auth.customRaceWindowEnabled, isFalse);
      expect(auth.onboardingV3Enabled, isFalse);
      expect(auth.setupInviteCodePromptEnabled, isFalse);
      expect(auth.tutorialMandatoryEnabled, isFalse);
      expect(auth.stepSampleBucketMinutes, 60);
    });

    test('authoritative old backend clears cached opt-in capabilities', () {
      final auth = AuthService();
      auth.applyBackendUser(const {
        'featureFlags': {
          'customRaceWindowEnabled': true,
          'onboardingV2Enabled': true,
          'onboardingV3Enabled': true,
          'setupInviteCodePromptEnabled': true,
          'tutorialMandatoryEnabled': true,
          'stepSampleBucketMinutes': 5,
        },
      }, authoritative: true);

      auth.applyBackendUser(const {'id': 'old-user'}, authoritative: true);

      expect(auth.customRaceWindowEnabled, isFalse);
      expect(auth.onboardingV2Enabled, isFalse);
      expect(auth.onboardingV3Enabled, isFalse);
      expect(auth.setupInviteCodePromptEnabled, isFalse);
      expect(auth.tutorialMandatoryEnabled, isFalse);
      expect(auth.stepSampleBucketMinutes, 60);
    });
  });

  testWidgets('compatibility admin settings exposes the banner control', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdminSettingsCardBody(
            settings: {
              'bannerAdsEnabled': true,
              'dualBoxBannersEnabled': true,
              'teamRacesEnabled': true,
              'onboardingV2Enabled': true,
              'onboardingV3Enabled': true,
              'onboardingInviteCodeEnabled': false,
              'tutorialMandatoryEnabled': true,
            },
            saving: false,
            onChanged: _noopSetting,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('admin-settings-banner-ads-toggle')),
      findsOneWidget,
    );
    expect(find.text('Banner ads'), findsOneWidget);
    expect(find.text('Dual box banners'), findsNothing);
    expect(find.text('Team races'), findsNothing);
    expect(find.text('Onboarding v2'), findsNothing);
    expect(find.text('Onboarding v3'), findsNothing);
    expect(find.text('Onboarding invite code'), findsNothing);
    expect(find.text('Mandatory tutorial'), findsNothing);
  });

  group('funded exposure errors', () {
    test('known code maps to stable explanatory copy', () {
      const error = ApiException(
        'Conflict',
        statusCode: 409,
        code: 'FUNDED_EXPOSURE_LIMIT',
        details: {
          'limitCoins': 300,
          'dailyRateLimitCoins': 40,
          'currentCoins': 280,
          'requestedCoins': 40,
          'currentDailyRateCoins': 34,
          'requestedDailyRateCoins': 7,
        },
      );

      expect(
        fundedExposureErrorCopy(error),
        'You’ve reached the active competition limit. Finish or leave an active competition, then try again.',
      );
    });

    test('unknown errors preserve the existing server message', () {
      const error = ApiException('Race is full', code: 'RACE_FULL');
      expect(fundedExposureErrorCopy(error), 'Race is full');
    });

    testWidgets('quick-create keeps the sheet open and shows inline copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickCreateRaceSheet(
              onCreate: (_) async => throw const ApiException(
                'Conflict',
                statusCode: 409,
                code: 'FUNDED_EXPOSURE_LIMIT',
              ),
              onCustomize: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('quick-create-2d')));
      await tester.pump();

      expect(find.byType(QuickCreateRaceSheet), findsOneWidget);
      expect(
        find.text(
          'You’ve reached the active competition limit. Finish or leave an active competition, then try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Conflict'), findsNothing);
    });
  });

  testWidgets(
    'quick-create uses the established sans face for its hero heading',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickCreateRaceSheet(
              onCreate: (_) async {},
              onCustomize: () {},
            ),
          ),
        ),
      );

      final heading = tester.widget<Text>(find.text('START A RACE'));
      expect(heading.style?.fontFamily, startsWith('SpaceGrotesk'));
    },
  );

  test('retired Imposter is removed from usable race inventory residue', () {
    final inventory = normalizePowerupInventory(const [
      {'id': 'retired', 'type': 'IMPOSTER', 'status': 'HELD'},
      {'id': 'box', 'status': 'MYSTERY_BOX'},
      {'id': 'live', 'type': 'SIGNAL_JAMMER', 'status': 'HELD'},
      'malformed',
    ]);

    expect(inventory.map((item) => item['id']), ['box', 'live']);
  });
}

void _noopSetting(String key, bool value) {}
