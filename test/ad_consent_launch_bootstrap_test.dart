import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:step_tracker/services/ad_consent_coordinator.dart';

void main() {
  testWidgets('app shell starts UMP without any ad surface mounted', (
    tester,
  ) async {
    var refreshCalls = 0;
    final coordinator = AdConsentCoordinator(
      requestConsentInfoUpdate: () async => refreshCalls++,
      loadAndShowConsentFormIfRequired: () async {},
      canRequestAds: () async => false,
      getPrivacyOptionsRequired: () async => false,
      showPrivacyOptionsForm: () async {},
      readPartnerConsentSignals: () async => const PartnerConsentSignals(),
      initializeAds: (_) async => true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdConsentBootstrap(
          coordinator: coordinator,
          child: const Scaffold(body: Text('Bara shell')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(refreshCalls, 1);
    expect(find.byType(AdWidget), findsNothing);
    expect(find.text('Bara shell'), findsOneWidget);
  });
}
