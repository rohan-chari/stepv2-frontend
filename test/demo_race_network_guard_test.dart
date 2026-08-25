import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spec §8.4 — the network-leak guard. **Mandatory, not optional.**
///
/// `RaceDetailScreen` makes ~25 distinct `_api.*` calls (F1), and the demo
/// renders that REAL screen against a fake backend. Any call site
/// `DemoRaceApiService` does not override is a live HTTPS request against prod
/// with a fabricated race id. The transport helpers on `BackendApiService` are
/// private, so the base class cannot be cheaply sealed.
///
/// This is CLAUDE.md's "structural guard over source" carve-out, and the same
/// pattern as the `isOnboardingGate` declared-exactly-once guard. It is the
/// only mechanism that fails when someone adds a 26th API call to the race
/// screen a year from now — which is precisely when this breaks, silently, in
/// production.
///
/// If this test fails: add the missing `@override` to
/// `lib/demo/demo_race_api_service.dart`. Do not delete the assertion.
void main() {
  final demoSource = File(
    'lib/demo/demo_race_api_service.dart',
  ).readAsStringSync();
  final tutorialSource = File(
    'lib/tutorial/tutorial_preview_data.dart',
  ).readAsStringSync();

  /// Every `<receiver>.<method>(` name called on an injected api handle in
  /// [path], for the given receiver names.
  Set<String> apiCallsIn(String path, List<String> receivers) {
    final source = File(path).readAsStringSync();
    final pattern = RegExp(
      '(?:${receivers.map(RegExp.escape).join('|')})\\.([a-zA-Z0-9_]+)\\(',
    );
    return pattern.allMatches(source).map((m) => m.group(1)!).toSet();
  }

  bool overridesMethod(String name) =>
      RegExp('\\b$name\\(\\s*\\{').hasMatch(demoSource) ||
      RegExp('\\b$name\\(').hasMatch(demoSource);

  bool tutorialOverridesMethod(String name) =>
      RegExp('\\b$name\\(\\s*\\{').hasMatch(tutorialSource) ||
      RegExp('\\b$name\\(').hasMatch(tutorialSource);

  test('DemoRaceApiService overrides every _api call in RaceDetailScreen', () {
    final calls = apiCallsIn('lib/screens/race_detail_screen.dart', ['_api']);

    // Sanity: if this collapses, the regex stopped matching and the guard is
    // silently vacuous — which is exactly the failure mode it exists to catch.
    expect(
      calls.length,
      greaterThanOrEqualTo(20),
      reason: 'expected ~25 distinct _api.* call sites; found $calls',
    );

    final missing = calls.where((m) => !overridesMethod(m)).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason:
          'RaceDetailScreen calls these on the injected api but '
          'DemoRaceApiService does not override them — each one is a live '
          'request against prod with a fabricated race id: $missing',
    );
  });

  test('DemoRaceApiService overrides every api call CreateRaceScreen makes', () {
    // The demo's prologue renders the REAL create screen against the demo
    // service. An unoverridden call here is worse than a leak on the race
    // screen: `createRace` / `createTeamRace` / `createTournament` would put a
    // REAL race on the account of a user who is still inside onboarding.
    final calls = apiCallsIn('lib/screens/create_race_screen.dart', [
      'widget.backendApiService',
    ]);

    expect(
      calls,
      contains('createRace'),
      reason: 'the regex must still be matching the create call itself',
    );

    final missing = calls.where((m) => !overridesMethod(m)).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason:
          'CreateRaceScreen calls these on the injected api but '
          'DemoRaceApiService does not override them: $missing',
    );
  });

  test('RaceInviteScreen stays API-free', () {
    // The invite beat renders it directly with a local friends list. A
    // BackendApiService reference here would be an un-fakeable call site.
    final source = File(
      'lib/screens/race_invite_screen.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'BackendApiService').hasMatch(source),
      isFalse,
      reason:
          'RaceInviteScreen must stay a pure picker; an api handle here would '
          'bypass DemoRaceApiService entirely',
    );
  });

  test('DemoRaceApiService overrides every api call the chat/feed make', () {
    // The race screen hands `widget.backendApiService` to RaceChatService and
    // RaceFeedService, so their calls ride the same injection.
    final calls = {
      ...apiCallsIn('lib/services/race_chat_service.dart', ['api', '_api']),
      ...apiCallsIn('lib/services/race_feed_service.dart', ['api', '_api']),
      ...apiCallsIn('lib/services/race_stream_coordinator.dart', [
        'api',
        '_api',
      ]),
    };

    final missing = calls.where((m) => !overridesMethod(m)).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason: 'unoverridden chat/feed api calls: $missing',
    );
  });

  test('social dossier calls are explicitly offline in demo and tutorial', () {
    const required = [
      'fetchPublicProfile',
      'fetchFriends',
      'sendFriendRequest',
      'respondToFriendRequest',
      'removeFriend',
    ];
    for (final method in required) {
      expect(
        RegExp('\\b$method\\s*\\(').hasMatch(demoSource),
        isTrue,
        reason: 'DemoRaceApiService must override $method',
      );
      expect(
        RegExp('\\b$method\\s*\\(').hasMatch(tutorialSource),
        isTrue,
        reason: 'TutorialPreviewBackendApiService must override $method',
      );
    }
  });

  test('tutorial preview overrides every race-detail stream call', () {
    const calls = {
      'fetchRaceBootstrap',
      'fetchRaceProgressCompact',
      'fetchRaceMessageStreams',
    };

    final missing =
        calls.where((method) => !tutorialOverridesMethod(method)).toList()
          ..sort();
    expect(
      missing,
      isEmpty,
      reason:
          'TutorialPreviewBackendApiService does not override these calls; '
          'the real tutorial could reach the network: $missing',
    );
  });

  test('DemoRaceApiService overrides every api call CaseOpeningScreen makes', () {
    // The reel takes an `openMysteryBox` CALLBACK, not a service, and the
    // callback closes over `_api.openMysteryBox` — covered above. This asserts
    // the screen has not since grown a service of its own.
    final source = File(
      'lib/screens/case_opening_screen.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'BackendApiService').hasMatch(source),
      isFalse,
      reason:
          'CaseOpeningScreen must stay callback-injected; a BackendApiService '
          'reference here would bypass DemoRaceApiService entirely',
    );
  });

  test('the demo service never calls super, so nothing falls through', () {
    expect(
      RegExp(r'\bsuper\.[a-zA-Z]').hasMatch(demoSource),
      isFalse,
      reason:
          'a super.<method>() call inside DemoRaceApiService would reach the '
          'real transport and hit prod',
    );
  });

  test('the demo package imports no http client', () {
    for (final file in Directory('lib/demo').listSync().whereType<File>()) {
      final source = file.readAsStringSync();
      expect(
        RegExp(r'''import\s+['"](package:http/|dart:io)''').hasMatch(source),
        isFalse,
        reason: '${file.path} must not talk to the network directly',
      );
    }
  });
}
