import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/widgets/ad_banner_slot.dart';
import 'package:step_tracker/widgets/ad_inline_card.dart';

void main() {
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
        setUnityGdprConsent: () async => calls.add('unity-gdpr'),
        setUnityCcpaConsent: () async => calls.add('unity-ccpa'),
        updateRequestConfiguration: () async => calls.add('config'),
        initializeMobileAds: () async => calls.add('mobile-ads'),
      ).run();

      expect(calls, [
        'att',
        'meta:false',
        'unity-gdpr',
        'unity-ccpa',
        'config',
        'mobile-ads',
      ]);
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
        setUnityGdprConsent: () async => throw StateError('Unity unavailable'),
        setUnityCcpaConsent: () async => calls.add('unity-ccpa'),
        updateRequestConfiguration: () async =>
            throw StateError('config unavailable'),
        initializeMobileAds: () async => calls.add('mobile-ads'),
      ).run();

      expect(calls, ['unity-ccpa', 'mobile-ads']);
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
      setUnityGdprConsent: () async {},
      setUnityCcpaConsent: () async {},
      updateRequestConfiguration: () async {},
      initializeMobileAds: () async => mobileInitialized = true,
    ).run();

    expect(attCalls, 0);
    expect(metaCalls, 0);
    expect(initialized, isTrue);
    expect(mobileInitialized, isTrue);
  });

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
      setUnityGdprConsent: () async {},
      setUnityCcpaConsent: () async {},
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
      setUnityGdprConsent: () async {},
      setUnityCcpaConsent: () async {},
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
