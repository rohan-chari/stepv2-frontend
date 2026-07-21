import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';

Widget _flow({
  required Future<Map<String, dynamic>?> Function() fetchDaily,
  String? displayName,
  bool sharePending = false,
  VoidCallback? onSkip,
  // Notifications already resolved, so these cases exercise the daily-intro
  // step they are actually about. The undetermined case is its own test below.
  bool? notificationsState = true,
}) {
  return MaterialApp(
    home: OnboardingFlow(
      healthAuthorized: true,
      notificationsState: notificationsState,
      tutorialOnboardingSeen: false,
      firstRaceOnboardingSeen: false,
      onboardingV2Enabled: true,
      displayName: displayName,
      onEnableHealth: () {},
      onEnableNotifications: () {},
      onStartTutorial: () {},
      onSkipTutorial: () {},
      onEnterDaily: () async {},
      onSkipFirstRace: onSkip ?? () {},
      firstRaceShareTokenPending: sharePending,
      onFetchActiveDaily: fetchDaily,
      onEnterVerifiedDaily: (_) async {},
      onFindRace: () async {},
    ),
  );
}

void main() {
  testWidgets('v2 skips the tutorial gate and shows verified Daily', (
    tester,
  ) async {
    await tester.pumpWidget(
      _flow(
        displayName: 'Trail Walker',
        fetchDaily: () async => {
          'raceId': 'daily-1',
          'name': 'Sunrise Sprint',
          'status': 'ACTIVE',
          'myStatus': 'ACCEPTED',
          'endsAt': DateTime.now()
              .add(const Duration(hours: 2))
              .toIso8601String(),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sunrise Sprint'), findsOneWidget);
    expect(find.text('@Trail Walker'), findsOneWidget);
    expect(find.text('SEE MY RACE'), findsOneWidget);
    expect(find.text('NOTIFICATIONS'), findsNothing);
    expect(find.text('START TUTORIAL'), findsNothing);
  });

  testWidgets('v2 asks for notifications after health, before the Daily', (
    tester,
  ) async {
    // Regression: v2 used to return the daily intro ahead of this check, so a
    // brand-new user was never asked and shipped with notifications off.
    await tester.pumpWidget(
      _flow(notificationsState: null, fetchDaily: () async => null),
    );
    await tester.pump();

    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.text('Stay in the race'), findsOneWidget);
    // The daily intro waits its turn behind the gate.
    expect(find.text('SEE MY RACE'), findsNothing);
    expect(find.text('FIND A RACE'), findsNothing);
  });

  testWidgets('v2 does not re-ask once notifications are resolved', (
    tester,
  ) async {
    // Explicitly denied (false, not null) must not re-nag on the next launch.
    await tester.pumpWidget(
      _flow(notificationsState: false, fetchDaily: () async => null),
    );
    await tester.pumpAndSettle();

    expect(find.text('NOTIFICATIONS'), findsNothing);
    expect(find.text('FIND A RACE'), findsOneWidget);
  });

  testWidgets('v2 null handle uses Racer and unavailable Daily is honest', (
    tester,
  ) async {
    await tester.pumpWidget(_flow(fetchDaily: () async => null));
    await tester.pumpAndSettle();

    expect(find.text('FIND A RACE'), findsOneWidget);
    expect(
      find.textContaining('couldn’t confirm a Daily spot'),
      findsOneWidget,
    );
    expect(find.textContaining('boxes'), findsNothing);
  });

  testWidgets('pending share skips generic Daily lookup', (tester) async {
    var fetched = false;
    var skipped = false;
    await tester.pumpWidget(
      _flow(
        sharePending: true,
        fetchDaily: () async {
          fetched = true;
          return null;
        },
        onSkip: () => skipped = true,
      ),
    );
    await tester.pump();

    expect(skipped, isTrue);
    expect(fetched, isFalse);
    expect(find.text('SEE MY RACE'), findsNothing);
  });
}
