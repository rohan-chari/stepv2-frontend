import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/ad_consent_coordinator.dart';
import 'package:step_tracker/services/ad_service.dart';

String _consentBits({required int length, required Set<int> enabledIds}) {
  final bits = List<String>.filled(length, '0');
  for (final id in enabledIds) {
    bits[id - 1] = '1';
  }
  return bits.join();
}

void main() {
  tearDown(() => AdService.setConsentPermission(true));

  test('required UMP form precedes partner propagation and ads', () async {
    final calls = <String>[];
    final coordinator = AdConsentCoordinator(
      requestConsentInfoUpdate: () async => calls.add('refresh'),
      loadAndShowConsentFormIfRequired: () async => calls.add('form'),
      canRequestAds: () async {
        calls.add('can-request');
        return true;
      },
      getPrivacyOptionsRequired: () async => true,
      showPrivacyOptionsForm: () async {},
      readPartnerConsentSignals: () async {
        calls.add('read-signals');
        return const PartnerConsentSignals(
          gdprConsent: true,
          ccpaConsent: false,
        );
      },
      initializeAds: (signals) async {
        calls.add('ads:${signals.gdprConsent}:${signals.ccpaConsent}');
        return true;
      },
    );

    expect(await coordinator.bootstrap(), isTrue);
    expect(coordinator.privacyOptionsRequired, isTrue);
    expect(calls, [
      'refresh',
      'form',
      'can-request',
      'read-signals',
      'ads:true:false',
    ]);
  });

  test(
    'partner consent application completes before Mobile Ads initialization',
    () async {
      final consentApplied = Completer<void>();
      final calls = <String>[];
      final coordinator = AdConsentCoordinator(
        requestConsentInfoUpdate: () async {},
        loadAndShowConsentFormIfRequired: () async {},
        canRequestAds: () async => true,
        getPrivacyOptionsRequired: () async => false,
        showPrivacyOptionsForm: () async {},
        readPartnerConsentSignals: () async =>
            const PartnerConsentSignals(gdprConsent: true),
        applyPartnerConsent: (_) async {
          calls.add('partner-start');
          await consentApplied.future;
          calls.add('partner-complete');
        },
        initializeAds: (_) async {
          calls.add('mobile-ads');
          return true;
        },
      );

      final bootstrap = coordinator.bootstrap();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['partner-start']);

      consentApplied.complete();
      expect(await bootstrap, isTrue);
      expect(calls, ['partner-start', 'partner-complete', 'mobile-ads']);
    },
  );

  test(
    'not-required path initializes once across simultaneous callers',
    () async {
      final refresh = Completer<void>();
      var refreshCalls = 0;
      var initializationCalls = 0;
      final coordinator = AdConsentCoordinator(
        requestConsentInfoUpdate: () {
          refreshCalls++;
          return refresh.future;
        },
        loadAndShowConsentFormIfRequired: () async {},
        canRequestAds: () async => true,
        getPrivacyOptionsRequired: () async => false,
        showPrivacyOptionsForm: () async {},
        readPartnerConsentSignals: () async => const PartnerConsentSignals(),
        initializeAds: (_) async {
          initializationCalls++;
          return true;
        },
      );

      final first = coordinator.bootstrap();
      final second = coordinator.bootstrap();
      refresh.complete();

      expect(await Future.wait([first, second]), [true, true]);
      expect(await coordinator.bootstrap(), isTrue);
      expect(refreshCalls, 1);
      expect(initializationCalls, 1);
    },
  );

  test('canRequestAds false fails closed without initializing', () async {
    var initializationCalls = 0;
    final coordinator = AdConsentCoordinator(
      requestConsentInfoUpdate: () async {},
      loadAndShowConsentFormIfRequired: () async {},
      canRequestAds: () async => false,
      getPrivacyOptionsRequired: () async => true,
      showPrivacyOptionsForm: () async {},
      readPartnerConsentSignals: () async => const PartnerConsentSignals(),
      initializeAds: (_) async {
        initializationCalls++;
        return true;
      },
    );

    expect(await coordinator.bootstrap(), isFalse);
    expect(coordinator.adsAllowed, isFalse);
    expect(coordinator.privacyOptionsRequired, isTrue);
    expect(initializationCalls, 0);
  });

  for (final failureStage in ['refresh', 'form']) {
    test('$failureStage error fails closed for the launch', () async {
      var initializationCalls = 0;
      final coordinator = AdConsentCoordinator(
        requestConsentInfoUpdate: () async {
          if (failureStage == 'refresh') throw StateError('refresh failed');
        },
        loadAndShowConsentFormIfRequired: () async {
          if (failureStage == 'form') throw StateError('form failed');
        },
        canRequestAds: () async => true,
        getPrivacyOptionsRequired: () async => false,
        showPrivacyOptionsForm: () async {},
        readPartnerConsentSignals: () async => const PartnerConsentSignals(),
        initializeAds: (_) async {
          initializationCalls++;
          return true;
        },
      );

      expect(await coordinator.bootstrap(), isFalse);
      expect(await coordinator.bootstrap(), isFalse);
      expect(initializationCalls, 0);
    });
  }

  test(
    'privacy form suppresses repeated taps and republishes withdrawal',
    () async {
      final form = Completer<void>();
      var formCalls = 0;
      var allowed = true;
      var signalReads = 0;
      final permissionChanges = <bool>[];
      final coordinator = AdConsentCoordinator(
        requestConsentInfoUpdate: () async {},
        loadAndShowConsentFormIfRequired: () async {},
        canRequestAds: () async => allowed,
        getPrivacyOptionsRequired: () async => true,
        showPrivacyOptionsForm: () {
          formCalls++;
          return form.future;
        },
        readPartnerConsentSignals: () async {
          signalReads++;
          return PartnerConsentSignals(ccpaConsent: allowed);
        },
        initializeAds: (_) async => true,
        onAdsPermissionChanged: permissionChanges.add,
      );
      expect(await coordinator.bootstrap(), isTrue);

      final first = coordinator.showPrivacyOptions();
      final second = coordinator.showPrivacyOptions();
      allowed = false;
      form.complete();
      await Future.wait([first, second]);

      expect(formCalls, 1);
      expect(coordinator.adsAllowed, isFalse);
      expect(signalReads, 2);
      expect(permissionChanges, [true, false]);
    },
  );

  test(
    'privacy form invalidates old ads while refreshed signals still allow ads',
    () async {
      final form = Completer<void>();
      final calls = <String>[];
      var signals = const PartnerConsentSignals(gdprConsent: true);
      final oldHandle = _DisposableRewardedHandle();
      final adService = AdService(
        adUnitId: 'test-rewarded-unit',
        supportedOverride: true,
        sdkInitializer: RewardedAdSdkInitializer(() async => true),
        rewardedAdLoader:
            ({required adUnitId, required userId, required customData}) async =>
                oldHandle,
      );
      addTearDown(adService.dispose);
      final coordinator = AdConsentCoordinator(
        requestConsentInfoUpdate: () async {},
        loadAndShowConsentFormIfRequired: () async {},
        canRequestAds: () async => true,
        getPrivacyOptionsRequired: () async => true,
        showPrivacyOptionsForm: () => form.future,
        readPartnerConsentSignals: () async => signals,
        applyPartnerConsent: (value) async =>
            calls.add('signals:${value.gdprConsent}:${value.ccpaConsent}'),
        initializeAds: (value) async {
          calls.add('initialize:${value.gdprConsent}:${value.ccpaConsent}');
          return true;
        },
        onAdsPermissionChanged: AdService.setConsentPermission,
      );
      expect(await coordinator.bootstrap(), isTrue);
      await adService.load(userId: 'user-1', localDate: '2026-08-26');
      expect(adService.isReady, isTrue);

      signals = const PartnerConsentSignals(gdprConsent: false);
      final privacyOptions = coordinator.showPrivacyOptions();

      expect(coordinator.adsAllowed, isFalse);
      expect(AdService.adRequestsAllowed, isFalse);
      expect(oldHandle.disposed, isTrue);
      form.complete();
      await privacyOptions;

      expect(coordinator.adsAllowed, isTrue);
      expect(AdService.adRequestsAllowed, isTrue);
      expect(calls, [
        'signals:true:null',
        'initialize:true:null',
        'signals:false:null',
        'initialize:false:null',
      ]);
    },
  );

  group('authoritative IAB partner signal parsing', () {
    test('Unity TCF vendor consent requires purposes 1, 3, and 4', () {
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABTCF_gdprApplies': 1,
          'IABTCF_PurposeConsents': '1011000000',
          'IABTCF_VendorConsents': _consentBits(
            length: 1549,
            enabledIds: {1549},
          ),
        }).gdprConsent,
        isTrue,
      );
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABTCF_gdprApplies': 1,
          'IABTCF_PurposeConsents': '1001000000',
          'IABTCF_VendorConsents': _consentBits(
            length: 1549,
            enabledIds: {1549},
          ),
        }).gdprConsent,
        isFalse,
      );
    });

    test('purpose 1 alone or absent Unity vendor consent stays unknown', () {
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABTCF_gdprApplies': 1,
          'IABTCF_PurposeConsents': '1000000000',
        }).gdprConsent,
        isNull,
      );
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABTCF_gdprApplies': 1,
          'IABTCF_PurposeConsents': '1011000000',
        }).gdprConsent,
        isNull,
      );
    });

    test('Unity Additional Consent provider 3234 is authoritative', () {
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABTCF_gdprApplies': 1,
          'IABTCF_PurposeConsents': '1011000000',
          'IABTCF_AddtlConsent': '2~41.3234~dv.9.21',
        }).gdprConsent,
        isTrue,
      );
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABTCF_gdprApplies': 1,
          'IABTCF_PurposeConsents': '1011000000',
          'IABTCF_AddtlConsent': '2~41~dv.9.21',
        }).gdprConsent,
        isFalse,
      );
    });

    test(
      'Unity TCF vendor denial takes precedence over Additional Consent',
      () {
        expect(
          PartnerConsentSignals.fromIabValues({
            'IABTCF_gdprApplies': 1,
            'IABTCF_PurposeConsents': '1011000000',
            'IABTCF_VendorConsents': _consentBits(
              length: 1549,
              enabledIds: const {},
            ),
            'IABTCF_AddtlConsent': '2~3234~dv.',
          }).gdprConsent,
          isFalse,
        );
      },
    );

    test(
      'malformed Unity vendor and Additional Consent values stay unknown',
      () {
        expect(
          PartnerConsentSignals.fromIabValues({
            'IABTCF_gdprApplies': 1,
            'IABTCF_PurposeConsents': '1011000000',
            'IABTCF_VendorConsents': 'not-bits',
            'IABTCF_AddtlConsent': '2~3234.bad~dv.9',
          }).gdprConsent,
          isNull,
        );
        expect(
          PartnerConsentSignals.fromIabValues({
            'IABTCF_gdprApplies': 1,
            'IABTCF_PurposeConsents': '1011000000',
            'IABTCF_AddtlConsent': '2~3234.bad~dv.9',
          }).gdprConsent,
          isNull,
        );
      },
    );

    test(
      'legacy US privacy sale choice maps Liftoff and Unity CCPA opt-in',
      () {
        expect(
          PartnerConsentSignals.fromIabValues({
            'IABUSPrivacy_String': '1YNN',
          }).ccpaConsent,
          isTrue,
        );
        expect(
          PartnerConsentSignals.fromIabValues({
            'IABUSPrivacy_String': '1YYN',
          }).ccpaConsent,
          isFalse,
        );
      },
    );

    test('applicable US National/California GPP opt-out wins', () {
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABGPP_GppSID': '7_8',
          'IABGPP_USNAT_SaleOptOut': 2,
          'IABGPP_USNAT_SharingOptOut': 2,
          'IABGPP_USNAT_TargetedAdvertisingOptOut': 2,
          'IABGPP_USNAT_Gpc': 0,
          'IABGPP_USCA_SaleOptOut': 1,
          'IABGPP_USCA_SharingOptOut': 2,
          'IABGPP_USCA_TargetedAdvertisingOptOut': 2,
          'IABGPP_USCA_Gpc': 0,
        }).ccpaConsent,
        isFalse,
      );
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABGPP_GppSID': '7',
          'IABGPP_USNAT_SaleOptOut': 2,
          'IABGPP_USNAT_SharingOptOut': 2,
          'IABGPP_USNAT_TargetedAdvertisingOptOut': 2,
          'IABGPP_USNAT_Gpc': 0,
        }).ccpaConsent,
        isTrue,
      );
    });

    test('current GPP never falls through to stale legacy US Privacy', () {
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABGPP_GppSID': '7',
          'IABGPP_USNAT_SaleOptOut': 2,
          'IABUSPrivacy_String': '1YYN',
        }).ccpaConsent,
        isNull,
      );
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABGPP_GppSID': '7',
          'IABGPP_USNAT_SaleOptOut': 1,
          'IABUSPrivacy_String': '1YNN',
        }).ccpaConsent,
        isNull,
      );
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABGPP_GppSID': '7',
          'IABGPP_USNAT_SaleOptOut': 'bad',
          'IABGPP_USNAT_SharingOptOut': 2,
          'IABGPP_USNAT_TargetedAdvertisingOptOut': 2,
          'IABGPP_USNAT_Gpc': 0,
          'IABUSPrivacy_String': '1YNN',
        }).ccpaConsent,
        isNull,
      );
    });

    test('absent malformed and non-applicable values stay unknown', () {
      expect(PartnerConsentSignals.fromIabValues({}).gdprConsent, isNull);
      expect(PartnerConsentSignals.fromIabValues({}).ccpaConsent, isNull);
      expect(
        PartnerConsentSignals.fromIabValues({
          'IABTCF_gdprApplies': 'maybe',
          'IABUSPrivacy_String': 'bad',
          'IABGPP_GppSID': 'not_ids',
        }),
        const PartnerConsentSignals(),
      );
    });
  });

  test('native bridges expose the Unity TCF vendor-consent bitfield', () {
    expect(
      File('ios/Runner/AppDelegate.swift').readAsStringSync(),
      contains('IABTCF_VendorConsents'),
    );
    expect(
      File(
        'android/app/src/main/kotlin/com/rohanchari/steptracker/MainActivity.kt',
      ).readAsStringSync(),
      contains('IABTCF_VendorConsents'),
    );
  });
}

class _DisposableRewardedHandle implements RewardedAdNativeHandle {
  bool disposed = false;

  @override
  void dispose() => disposed = true;

  @override
  Future<bool> showAndAwaitReward({required Duration timeout}) async => true;
}
