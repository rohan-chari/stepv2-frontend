import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/ad_consent_coordinator.dart';

void main() {
  for (final failure in ['measurement', 'ads', 'privacy form']) {
    testWidgets('$failure failure stays isolated from other consent outcomes', (
      tester,
    ) async {
      final decisions = <bool>[];
      var adsAttempts = 0;
      final coordinator = AdConsentCoordinator(
        requestConsentInfoUpdate: () async {},
        loadAndShowConsentFormIfRequired: () async {},
        canRequestAds: () async => true,
        getPrivacyOptionsRequired: () async => true,
        showPrivacyOptionsForm: () async {
          if (failure == 'privacy form') throw StateError('form unavailable');
        },
        readPartnerConsentSignals: () async => const PartnerConsentSignals(),
        initializeAds: (_) async {
          adsAttempts++;
          if (failure == 'ads') throw StateError('ads unavailable');
          return true;
        },
        onMeasurementConsentResolved: (resolved) async {
          decisions.add(resolved);
          if (failure == 'measurement') throw StateError('channel unavailable');
        },
      );
      addTearDown(coordinator.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AdConsentBootstrap(
            coordinator: coordinator,
            child: const Text('Bara'),
          ),
        ),
      );
      await tester.pump();
      expect(decisions, [true]);
      expect(adsAttempts, 1);
      expect(coordinator.adsAllowed, failure != 'ads');
      await coordinator.showPrivacyOptions();
      expect(decisions, [true, false, failure != 'privacy form']);
      expect(adsAttempts, 2);
      expect(coordinator.adsAllowed, failure != 'ads');
      expect(find.text('Bara'), findsOneWidget);
    });
  }

  testWidgets('measurement resolves from CMP even when ads are disallowed', (
    tester,
  ) async {
    final decisions = <bool>[];
    var ads = 0;
    final coordinator = AdConsentCoordinator(
      requestConsentInfoUpdate: () async {},
      loadAndShowConsentFormIfRequired: () async {},
      canRequestAds: () async => false,
      getPrivacyOptionsRequired: () async => true,
      showPrivacyOptionsForm: () async {},
      readPartnerConsentSignals: () async => const PartnerConsentSignals(),
      initializeAds: (_) async {
        ads++;
        return true;
      },
      onMeasurementConsentResolved: (resolved) async => decisions.add(resolved),
    );
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AdConsentBootstrap(
          coordinator: coordinator,
          child: const Text('Bara'),
        ),
      ),
    );
    await tester.pump();
    expect(decisions, [true]);
    expect(ads, 0);
    await coordinator.showPrivacyOptions();
    expect(decisions, [true, false, true]);
    expect(find.text('Bara'), findsOneWidget);
  });

  testWidgets(
    'failed CMP resolution fails measurement closed without blocking shell',
    (tester) async {
      final decisions = <bool>[];
      final coordinator = AdConsentCoordinator(
        requestConsentInfoUpdate: () async => throw StateError('offline'),
        loadAndShowConsentFormIfRequired: () async {},
        canRequestAds: () async => true,
        getPrivacyOptionsRequired: () async => false,
        showPrivacyOptionsForm: () async {},
        readPartnerConsentSignals: () async => const PartnerConsentSignals(),
        initializeAds: (_) async => true,
        onMeasurementConsentResolved: (resolved) async =>
            decisions.add(resolved),
      );
      addTearDown(coordinator.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AdConsentBootstrap(
            coordinator: coordinator,
            child: const Text('Bara'),
          ),
        ),
      );
      await tester.pump();
      expect(decisions, [false]);
      expect(find.text('Bara'), findsOneWidget);
    },
  );
}
