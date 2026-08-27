import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/settings_screen.dart';
import 'package:step_tracker/services/ad_consent_coordinator.dart';
import 'package:step_tracker/services/auth_service.dart';

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Runner',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

AdConsentCoordinator _coordinator({
  required bool privacyRequired,
  Future<void> Function()? showPrivacyOptionsForm,
}) => AdConsentCoordinator(
  requestConsentInfoUpdate: () async {},
  loadAndShowConsentFormIfRequired: () async {},
  canRequestAds: () async => true,
  getPrivacyOptionsRequired: () async => privacyRequired,
  showPrivacyOptionsForm: showPrivacyOptionsForm ?? () async {},
  readPartnerConsentSignals: () async => const PartnerConsentSignals(),
  initializeAds: (_) async => true,
);

Future<void> _pump(
  WidgetTester tester,
  AdConsentCoordinator coordinator,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        authService: await _auth(),
        adConsentCoordinator: coordinator,
        onSettingsChanged: () {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('privacy action appears immediately before Privacy Policy', (
    tester,
  ) async {
    await _pump(tester, _coordinator(privacyRequired: true));

    final privacyOptions = find.byKey(const Key('settings-privacy-options'));
    final privacyPolicy = find.byKey(const Key('settings-privacy-policy'));
    expect(privacyOptions, findsOneWidget);
    expect(privacyPolicy, findsOneWidget);
    expect(
      tester.getTopLeft(privacyOptions).dy,
      lessThan(tester.getTopLeft(privacyPolicy).dy),
    );
  });

  testWidgets('not-required state leaves no row or empty layout slot', (
    tester,
  ) async {
    await _pump(tester, _coordinator(privacyRequired: false));

    expect(find.byKey(const Key('settings-privacy-options')), findsNothing);
    expect(find.byKey(const Key('settings-support')), findsOneWidget);
    expect(find.byKey(const Key('settings-privacy-policy')), findsOneWidget);
  });

  testWidgets('tap opens once, suppresses repeats, and errors do not crash', (
    tester,
  ) async {
    final completer = Completer<void>();
    var calls = 0;
    final coordinator = _coordinator(
      privacyRequired: true,
      showPrivacyOptionsForm: () {
        calls++;
        return completer.future;
      },
    );
    await _pump(tester, coordinator);
    final action = find.byKey(const Key('settings-privacy-options'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.tap(action);
    await tester.pump();
    expect(calls, 1);

    completer.completeError(StateError('UMP unavailable'));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
