import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/demo/demo_race_host.dart';
import 'package:step_tracker/demo/demo_race_script.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/screens/race_invite_screen.dart';
import 'package:step_tracker/services/backend_api_service.dart';

import 'support/demo_race_harness.dart';

/// The demo's create + invite prologue.
///
/// The demo opens on the REAL `CreateRaceScreen` and the REAL
/// `RaceInviteScreen`, so the property that matters most here is the one that
/// is invisible when it works: **nothing is created on the user's account.**
/// A create call that reached the live transport would leave a real race, in a
/// real feed, made by a user who is still in onboarding.

/// Fails loudly on any call that is not served locally. The demo host builds
/// its own `DemoRaceApiService` internally; this is the REAL-api handle it
/// takes for telemetry, and nothing in the prologue may ride it.
class _SilentApi extends BackendApiService {
  final List<String> calls = [];

  @override
  Future<void> sendActivationEvents({
    required String identityToken,
    required List<Map<String, dynamic>> events,
  }) async {
    calls.add('sendActivationEvents');
  }

  @override
  Future<Map<String, dynamic>> createRace({
    required String identityToken,
    required String name,
    int buyInAmount = 0,
    int maxDurationDays = 3,
    bool powerupsEnabled = true,
    int? powerupStepInterval,
    String payoutPreset = 'WINNER_TAKES_ALL',
    bool isPublic = false,
    int? maxParticipants,
    DateTime? scheduledStartAt,
  }) async {
    calls.add('createRace');
    return const {};
  }

  @override
  Future<Map<String, dynamic>> inviteToRace({
    required String identityToken,
    required String raceId,
    required List<String> inviteeIds,
  }) async {
    calls.add('inviteToRace');
    return const {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  ({
    SeededAuthService auth,
    DemoRaceEngine engine,
    _SilentApi api,
    List<bool> completions,
  })
  build() {
    final auth = seededRealAuthService();
    return (
      auth: auth,
      engine: DemoRaceEngine(
        myUserId: auth.userId!,
        myDisplayName: auth.displayName!,
      ),
      api: _SilentApi(),
      completions: <bool>[],
    );
  }

  Future<void> pumpHost(WidgetTester tester, dynamic ctx) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: DemoRaceHost(
          authService: ctx.auth,
          backendApiService: ctx.api,
          engine: ctx.engine,
          onDone: (completed) {
            ctx.completions.add(completed);
          },
        ),
      ),
    );
    await settleDemo(tester);
  }

  /// Taps CREATE RACE on the real create screen.
  Future<void> createTheRace(WidgetTester tester) async {
    await tester.tap(find.text('CREATE RACE'));
    await settleDemo(tester);
  }

  testWidgets('the demo opens on the REAL create screen, name pre-filled', (
    tester,
  ) async {
    final ctx = build();
    await pumpHost(tester, ctx);

    expect(find.byType(CreateRaceScreen), findsOneWidget);
    expect(find.byType(RaceDetailScreen), findsNothing);

    // The name is not the lesson — it arrives filled in, so the only decision
    // on this screen is the one the coach is asking for.
    final field = tester.widget<TextField>(
      find.byKey(const Key('race-name-field')),
    );
    expect(field.controller!.text, DemoRaceEngine.raceName);

    expect(
      find.text(kDemoBeatCopy[DemoBeat.createRace]!.title),
      findsOneWidget,
    );
    expect(find.text('STEP 1 OF $kDemoBeatCount'), findsOneWidget);
  });

  testWidgets('the create screen hides every branch that can dead-end a demo', (
    tester,
  ) async {
    final ctx = build();
    await pumpHost(tester, ctx);

    // Teams, tournaments, visibility, payout presets and scheduled starts all
    // live behind CUSTOMIZE RACE. A scripted tutorial cannot survive any of
    // them, so the whole section is gone.
    expect(find.byKey(const Key('customize-race-toggle')), findsNothing);
    expect(find.text('CUSTOMIZE RACE'), findsNothing);
    // And there is no back arrow: the coach's SKIP is the only exit.
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('picking a duration carries into the race the user lands in', (
    tester,
  ) async {
    final ctx = build();
    await pumpHost(tester, ctx);

    await tester.tap(find.byKey(const Key('duration-option-7')));
    await settleDemo(tester);
    await createTheRace(tester);

    expect(ctx.engine.durationDays, 7);
    expect(ctx.engine.raceCreated, isTrue);
  });

  testWidgets('CREATE RACE never posts a race to the real backend', (
    tester,
  ) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await createTheRace(tester);

    expect(
      ctx.api.calls.where((c) => c == 'createRace'),
      isEmpty,
      reason:
          'a real createRace here leaves a real race on the account of a user '
          'who has not finished onboarding',
    );
  });

  testWidgets('creating hands off to the REAL invite screen', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await createTheRace(tester);

    expect(ctx.engine.beat, DemoBeat.inviteFriends);
    expect(find.byType(RaceInviteScreen), findsOneWidget);
    expect(find.byType(CreateRaceScreen), findsNothing);

    // All three rivals are offered as friends the user already has.
    for (final friend in DemoRaceEngine.demoFriends) {
      expect(
        find.textContaining(friend['displayName'] as String),
        findsWidgets,
        reason: '${friend['displayName']} must be invitable',
      );
    }
  });

  testWidgets('the invite beat draws no scrim over its own controls', (
    tester,
  ) async {
    // The scrim dims everything outside the coach's anchor, and the invite beat
    // has no anchor — so it dimmed the three rows and the send button, which
    // read as "disabled" rather than "tap these". Everything on that screen is
    // the lesson, so nothing gets dimmed.
    final scrim = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_FocusScrim',
    );

    final ctx = build();
    await pumpHost(tester, ctx);
    expect(scrim, findsOneWidget, reason: 'the create beat still marks CREATE');

    await createTheRace(tester);
    expect(scrim, findsNothing);
  });

  testWidgets('inviting all three starts the race', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await createTheRace(tester);

    for (final friend in DemoRaceEngine.demoFriends) {
      await tester.tap(find.textContaining(friend['displayName'] as String));
      await settleDemo(tester, frames: 6);
    }

    await tester.tap(find.text('INVITE 3 FRIENDS'));
    await settleDemo(tester);

    expect(ctx.engine.friendsInvited, isTrue);
    expect(ctx.engine.invitedUserIds, hasLength(3));
    expect(ctx.engine.beat, DemoBeat.intro);
    expect(find.byType(RaceDetailScreen), findsOneWidget);
    expect(
      ctx.api.calls.where((c) => c == 'inviteToRace'),
      isEmpty,
      reason: 'the invites are as fake as the race they are for',
    );
  });

  testWidgets('sending fewer than three invites is refused', (tester) async {
    // The script asks for all three. Sending one would seat a race whose
    // standings show four people the user never invited.
    final ctx = build();
    await pumpHost(tester, ctx);
    await createTheRace(tester);

    await tester.tap(find.textContaining('Sam Rivera'));
    await settleDemo(tester, frames: 6);
    await tester.tap(find.text('INVITE 1 FRIEND'));
    await settleDemo(tester);

    expect(ctx.engine.friendsInvited, isFalse);
    expect(ctx.engine.beat, DemoBeat.inviteFriends);
    expect(
      find.byType(RaceInviteScreen),
      findsOneWidget,
      reason: 'the screen stays put with the selection intact',
    );

    // Completing the set sends.
    await tester.tap(find.textContaining('Jordan Lee'));
    await settleDemo(tester, frames: 6);
    await tester.tap(find.textContaining('Priya N.'));
    await settleDemo(tester, frames: 6);
    await tester.tap(find.text('INVITE 3 FRIENDS'));
    await settleDemo(tester);

    expect(ctx.engine.friendsInvited, isTrue);
    expect(ctx.engine.beat, DemoBeat.intro);
  });

  testWidgets('SKIP works on both prologue beats and grants no coins', (
    tester,
  ) async {
    for (final afterCreate in [false, true]) {
      // Tear the tree down between runs: DemoRaceHost reads its injected
      // engine once, in initState, so re-pumping the same widget type in place
      // would keep the first run's state (and its already-finished flag).
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      final ctx = build();
      await pumpHost(tester, ctx);
      if (afterCreate) await createTheRace(tester);

      expect(find.byKey(const Key('demo-skip')), findsOneWidget);
      await tester.tap(find.byKey(const Key('demo-skip')));
      await settleDemo(tester);

      expect(
        ctx.completions,
        [false],
        reason: 'skipped ${afterCreate ? 'on invite' : 'on create'}',
      );
      expect(ctx.auth.coins, 1840);
      expect(ctx.auth.tutorialRewardClaims, 0);
    }
  });
}
