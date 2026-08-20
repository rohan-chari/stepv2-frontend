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
  });

  testWidgets('admin CONFIG exposes only the retained service-banner control', (
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

    expect(find.byType(Switch), findsNothing);
    expect(find.text('Banner ads'), findsNothing);
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
        'Finish or leave another funded race before joining this one.',
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
          'Finish or leave another funded race before joining this one.',
        ),
        findsOneWidget,
      );
      expect(find.text('Conflict'), findsNothing);
    });
  });

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
