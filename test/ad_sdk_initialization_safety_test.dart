import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:step_tracker/services/ad_consent_coordinator.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/widgets/ad_banner_slot.dart';
import 'package:step_tracker/widgets/ad_inline_card.dart';

void main() {
  tearDown(() {
    AdService.setConsentPermission(true);
  });

  test('ad request gates default closed before consent bootstrap', () {
    expect(AdService.adRequestsAllowed, isFalse);
    expect(AdService.adRequestPermissionListenable.value, isFalse);
    expect(AdService.bannerAdsRuntimeEnabled, isFalse);
  });

  test(
    'iOS denial continues with limited ads and every SDK seam runs',
    () async {
      final calls = <String>[];
      final initialized = await AdSdkInitializationSteps(
        isIos: true,
        resolveTrackingAuthorization: () async {
          calls.add('att');
          return false;
        },
        setMetaTrackingEnabled: (enabled) async => calls.add('meta:$enabled'),
        updateRequestConfiguration: () async => calls.add('config'),
        initializeMobileAds: () async => calls.add('mobile-ads'),
      ).run();

      expect(calls, ['att', 'meta:false', 'config', 'mobile-ads']);
      expect(initialized, isTrue);
    },
  );

  test(
    'each failing privacy seam is isolated and startup still completes',
    () async {
      final calls = <String>[];
      final initialized = await AdSdkInitializationSteps(
        isIos: true,
        resolveTrackingAuthorization: () async =>
            throw StateError('ATT unavailable'),
        setMetaTrackingEnabled: (_) async =>
            throw StateError('Meta unavailable'),
        updateRequestConfiguration: () async =>
            throw StateError('config unavailable'),
        initializeMobileAds: () async => calls.add('mobile-ads'),
      ).run();

      expect(calls, ['mobile-ads']);
      expect(initialized, isTrue);
    },
  );

  test('Android never invokes ATT or Meta', () async {
    var attCalls = 0;
    var metaCalls = 0;
    var mobileInitialized = false;
    final initialized = await AdSdkInitializationSteps(
      isIos: false,
      resolveTrackingAuthorization: () async {
        attCalls++;
        return true;
      },
      setMetaTrackingEnabled: (_) async => metaCalls++,
      updateRequestConfiguration: () async {},
      initializeMobileAds: () async => mobileInitialized = true,
    ).run();

    expect(attCalls, 0);
    expect(metaCalls, 0);
    expect(initialized, isTrue);
    expect(mobileInitialized, isTrue);
  });

  test(
    'determinate partner signals are isolated and unknown values skipped',
    () async {
      final calls = <String>[];
      await PartnerConsentPropagationSteps(
        signals: const PartnerConsentSignals(
          gdprConsent: true,
          ccpaConsent: false,
        ),
        setUnityGdprConsent: (_) async =>
            throw StateError('Unity GDPR unavailable'),
        setUnityCcpaConsent: (value) async => calls.add('unity-ccpa:$value'),
        setLiftoffCcpaConsent: (value) async =>
            calls.add('liftoff-ccpa:$value'),
      ).run();
      await PartnerConsentPropagationSteps(
        signals: const PartnerConsentSignals(),
        setUnityGdprConsent: (_) async => calls.add('unexpected-gdpr'),
        setUnityCcpaConsent: (_) async => calls.add('unexpected-unity-ccpa'),
        setLiftoffCcpaConsent: (_) async => calls.add('unexpected-liftoff'),
      ).run();

      expect(calls, ['unity-ccpa:false', 'liftoff-ccpa:false']);
    },
  );

  test(
    'Mobile Ads failure returns false and is retried instead of cached',
    () async {
      var attempts = 0;
      final initializer = RewardedAdSdkInitializer(() async {
        attempts++;
        return attempts > 1;
      });

      expect(await initializer.ensureInitialized(), isFalse);
      expect(await initializer.ensureInitialized(), isTrue);
      expect(await initializer.ensureInitialized(), isTrue);
      expect(attempts, 2);
    },
  );

  test(
    'consent withdrawal disposes a cached rewarded ad immediately',
    () async {
      final handle = _DisposableRewardedHandle();
      final service = AdService(
        adUnitId: 'test-rewarded-unit',
        supportedOverride: true,
        sdkInitializer: RewardedAdSdkInitializer(() async => true),
        rewardedAdLoader:
            ({required adUnitId, required userId, required customData}) async =>
                handle,
      );
      addTearDown(service.dispose);

      AdService.setConsentPermission(true);
      await service.load(userId: 'user-1', localDate: '2026-08-26');
      expect(service.isReady, isTrue);

      AdService.setConsentPermission(false);

      expect(handle.disposed, isTrue);
      expect(service.isReady, isFalse);
    },
  );

  testWidgets('iOS bootstrap failure collapses the banner without SDK UI', (
    tester,
  ) async {
    AdService.setBannerUnitAvailabilityForTesting(standard: true);
    AdService.setBannerAdsEnabled(true);
    addTearDown(() {
      AdService.setBannerUnitAvailabilityForTesting();
      AdService.setBannerAdsEnabled(true);
    });
    var attCalls = 0;
    var mobileCalls = 0;
    final steps = AdSdkInitializationSteps(
      isIos: true,
      resolveTrackingAuthorization: () async {
        attCalls++;
        return false;
      },
      setMetaTrackingEnabled: (_) async {},
      updateRequestConfiguration: () async {},
      initializeMobileAds: () async {
        mobileCalls++;
        throw StateError('SDK unavailable');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdBannerSlot(
          reserveSpaceWhileLoading: true,
          sdkInitializer: steps.run,
        ),
      ),
    );
    await tester.pump();

    expect(attCalls, 1);
    expect(mobileCalls, 1);
    expect(find.byType(AdWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android bootstrap failure collapses native ads and skips ATT', (
    tester,
  ) async {
    AdService.setBannerUnitAvailabilityForTesting(native: true);
    AdService.setBannerAdsEnabled(true);
    addTearDown(() {
      AdService.setBannerUnitAvailabilityForTesting();
      AdService.setBannerAdsEnabled(true);
    });
    var attCalls = 0;
    final steps = AdSdkInitializationSteps(
      isIos: false,
      resolveTrackingAuthorization: () async {
        attCalls++;
        return true;
      },
      setMetaTrackingEnabled: (_) async {},
      updateRequestConfiguration: () async {},
      initializeMobileAds: () async => throw StateError('SDK unavailable'),
    );

    await tester.pumpWidget(
      MaterialApp(home: AdInlineCard(sdkInitializer: steps.run)),
    );
    await tester.pump();

    expect(attCalls, 0);
    expect(find.byType(AdWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _DisposableRewardedHandle implements RewardedAdNativeHandle {
  bool disposed = false;

  @override
  void dispose() => disposed = true;

  @override
  Future<bool> showAndAwaitReward({required Duration timeout}) async => true;
}
