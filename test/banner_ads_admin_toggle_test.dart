import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/ad_banner_slot.dart';

class _BannerAdminApi extends BackendApiService {
  _BannerAdminApi({this.bannerEnabled = true, this.failUpdate = false});

  bool bannerEnabled;
  bool failUpdate;
  bool? lastUpdate;

  @override
  Future<Map<String, dynamic>> fetchAdminSettings({
    required String identityToken,
  }) async => {
    'bannerAdsEnabled': bannerEnabled,
    'homeServiceBannerEnabled': false,
    'homeServiceBannerMessage': '',
  };

  @override
  Future<Map<String, dynamic>> updateAdminSettings({
    required String identityToken,
    required bool bannerAdsEnabled,
  }) async {
    lastUpdate = bannerAdsEnabled;
    if (failUpdate) throw const ApiException('save failed');
    bannerEnabled = bannerAdsEnabled;
    return {
      'bannerAdsEnabled': bannerAdsEnabled,
      'homeServiceBannerEnabled': false,
      'homeServiceBannerMessage': '',
    };
  }
}

Future<AuthService> _adminAuth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'identity',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'admin-1',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AdService.setConsentPermission(true);
    AdService.setBannerUnitAvailabilityForTesting(
      standard: true,
      boxTop: true,
      native: true,
    );
    AdService.setBannerAdsEnabled(true);
  });

  tearDown(() {
    AdService.setBannerUnitAvailabilityForTesting();
    AdService.setBannerAdsEnabled(true);
    AdService.setConsentPermission(false);
  });

  group('bannerAdsEnabled auth parsing', () {
    test('explicit false is retained', () {
      final auth = AuthService();

      auth.applyBackendUser(const {
        'featureFlags': {'bannerAdsEnabled': false},
      }, authoritative: true);

      expect(auth.bannerAdsEnabled, isFalse);
      expect(AdService.bannerAdsRuntimeEnabled, isFalse);
    });

    test('missing, null, and malformed values default to enabled', () {
      for (final payload in const [
        <String, dynamic>{'featureFlags': <String, dynamic>{}},
        <String, dynamic>{
          'featureFlags': {'bannerAdsEnabled': null},
        },
        <String, dynamic>{
          'featureFlags': {'bannerAdsEnabled': 'false'},
        },
        <String, dynamic>{'id': 'old-backend'},
      ]) {
        final auth = AuthService();
        auth.applyBackendUser(payload, authoritative: true);
        expect(auth.bannerAdsEnabled, isTrue, reason: '$payload');
      }
    });

    test('sign out resets the runtime gate to enabled', () async {
      final auth = await _adminAuth();
      auth.applyBackendUser(const {
        'featureFlags': {'bannerAdsEnabled': false},
      });
      expect(AdService.bannerAdsRuntimeEnabled, isFalse);

      await auth.signOut();

      expect(auth.bannerAdsEnabled, isTrue);
      expect(AdService.bannerAdsRuntimeEnabled, isTrue);
    });
  });

  testWidgets(
    'a mounted slot and direct spacing collapse, then resume on gate changes',
    (tester) async {
      AdService.setBannerAdsEnabled(false);
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              AdBannerSlot(
                key: Key('banner-slot'),
                reserveSpaceWhileLoading: true,
              ),
              AdBannerSpacing(key: Key('banner-spacing')),
            ],
          ),
        ),
      );

      expect(tester.getSize(find.byKey(const Key('banner-slot'))).height, 0);
      expect(
        tester.getSize(find.byKey(const Key('banner-spacing'))).height,
        0,
      );

      AdService.setBannerAdsEnabled(true);
      await tester.pump();

      expect(
        tester.getSize(find.byKey(const Key('banner-spacing'))).height,
        12,
      );
      expect(
        tester.getSize(find.byKey(const Key('banner-slot'))).height,
        greaterThan(0),
      );
    },
  );

  test('runtime banner gate does not change rewarded-ad support', () {
    final before = AdService().isSupported;
    AdService.setBannerAdsEnabled(false);
    expect(AdService().isSupported, before);
  });

  group('Admin Config banner switch', () {
    testWidgets('loads and persists the existing PATCH setting', (tester) async {
      final auth = await _adminAuth();
      final api = _BannerAdminApi(bannerEnabled: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminFlagsPanel(
              authService: auth,
              backendApiService: api,
              showErrorToast: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Banner ads'), findsOneWidget);
      final toggle = find.byKey(const Key('admin-banner-ads-toggle'));
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.tap(toggle);
      await tester.pump();

      expect(api.lastUpdate, isTrue);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    });

    testWidgets('rolls back and reports an error when saving fails', (
      tester,
    ) async {
      final auth = await _adminAuth();
      final api = _BannerAdminApi(bannerEnabled: false, failUpdate: true);
      String? error;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminFlagsPanel(
              authService: auth,
              backendApiService: api,
              showErrorToast: (_, message) => error = message,
            ),
          ),
        ),
      );
      await tester.pump();

      final toggle = find.byKey(const Key('admin-banner-ads-toggle'));
      await tester.tap(toggle);
      await tester.pump();

      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(error, 'Couldn\'t save banner ads.');
    });
  });
}
