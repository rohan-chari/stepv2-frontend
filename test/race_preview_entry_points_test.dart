// Preview-before-joining: every join-only entry point's card BODY navigates to
// a read-only preview, while its existing JOIN affordance keeps joining
// directly. Covers the six entry points in the spec's frontend section plus the
// stated disabled-button fallthrough rule.
//
// Spec: docs/race-preview-before-join-spec.md — "Frontend change — wire 'tap
// card to preview' at every join-only entry point", test-plan items 4 and 5.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/screens/tournament_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/tournament_game_card.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _publicSuggestion = <String, dynamic>{
  'kind': 'PUBLIC_RACE',
  'id': 'race-public-1',
  'name': 'Lunch Break Sprint',
  'status': 'PENDING',
  'maxDurationDays': 1,
  'endsAt': null,
  'startedAt': null,
  'participantCount': 3,
  'maxParticipants': 10,
  'buyInAmount': 0,
  'payoutPreset': 'TOP_HALF_GRADED',
  'powerupsEnabled': true,
  'prizePool': null,
  'isTeamRace': false,
  'teamSize': null,
  'teamAName': null,
  'teamBName': null,
  'teams': null,
  'joinAction': 'JOIN',
};

const _tournamentSuggestion = <String, dynamic>{
  'kind': 'TOURNAMENT',
  'id': 'tournament-1',
  'seedKind': 'DAILY_DASH',
  'name': 'Daily Dash',
  'status': 'PENDING',
  'bracketSize': 8,
  'matchupDurationDays': 1,
  'acceptedCount': 5,
  'buyInAmount': 0,
  'potCoins': 800,
  'prizePool': null,
  'powerupsEnabled': true,
  'powerupStepInterval': 2000,
  'createdAt': '2026-08-11T20:00:00.000Z',
  'joinAction': 'JOIN',
};

class _HomeApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => const {'claimedToday': true};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'identity',
    'auth_user_identifier': 'platform-user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'auth_profile_photo_prompt_dismissed_at': '2026-08-01T00:00:00Z',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

/// Records what each affordance fired so a test can prove "previewed, did NOT
/// join" and vice versa.
class _Taps {
  final openedRaces = <String>[];
  final openedTournaments = <String>[];
  final joinedRaces = <String>[];
  final joinedSuggestions = <String>[];
  int openRacesTab = 0;
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required _Taps taps,
  Loadable<List<HomeRaceSuggestion>> suggestions = const Loadable.initial(),
  Set<String> joiningSuggestionKeys = const {},
  Map<String, dynamic>? raceCard,
  bool isTutorialPreview = false,
  Completer<void>? joinGate,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: HomeTab(
        stepData: StepData(steps: 1200, date: DateTime(2026, 8, 15)),
        isLoading: false,
        error: null,
        healthAuthorized: true,
        notificationsState: true,
        displayName: 'Walker',
        authService: auth,
        backendApiService: _HomeApi(),
        onRefresh: () async {},
        onEnableHealth: () {},
        onEnableNotifications: () {},
        onDisplayNameChanged: () {},
        friendsSteps: const [],
        isTutorialPreview: isTutorialPreview,
        raceCard: raceCard,
        suggestedRacesState: suggestions,
        joiningSuggestionKeys: joiningSuggestionKeys,
        onJoinSuggestion: (s) async => taps.joinedSuggestions.add(s.id),
        onOpenRace: (id) => taps.openedRaces.add(id),
        onOpenTournament: (id) => taps.openedTournaments.add(id),
        onJoinRaceFromCard: (id) async => taps.joinedRaces.add(id),
        onJoinDiscoveredRace: (id) async {
          taps.joinedRaces.add(id);
          if (joinGate != null) await joinGate.future;
        },
        onOpenRacesTab: () => taps.openRacesTab++,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

List<HomeRaceSuggestion> _suggestions(List<Map<String, dynamic>> raw) => raw
    .map(HomeRaceSuggestion.tryParse)
    .whereType<HomeRaceSuggestion>()
    .toList();

/// Scrolls the suggested-races carousel into view.
Future<void> _revealCarousel(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
  await tester.pump();
}

// ---------------------------------------------------------------------------
// public_races_screen fixtures
// ---------------------------------------------------------------------------

class _PublicRacesApi extends BackendApiService {
  _PublicRacesApi({this.tournaments = const [], this.joinGate});

  final List<Map<String, dynamic>> tournaments;

  /// Holds `joinPublicRace` open so a test can tap the JOIN pill while it is
  /// disabled ("JOINING...").
  final Completer<void>? joinGate;

  final joinedRaceIds = <String>[];
  final joinedTournamentIds = <String>[];

  List<Map<String, dynamic>> get _races => [
    {
      'id': 'race-1',
      'name': 'Gold Sprint',
      'targetSteps': 50000,
      'participantCount': 1,
      'maxParticipants': 10,
      'buyInAmount': 0,
      'projectedPotCoins': 200,
      'creator': {'displayName': 'RaceMaker'},
      'powerupsEnabled': true,
    },
  ];

  @override
  Future<Map<String, dynamic>> fetchPublicRaceBrowser({
    required String identityToken,
  }) async => {'races': _races};

  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async => _races;

  @override
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async => const {
    'active': <Map<String, dynamic>>[],
    'pending': <Map<String, dynamic>>[],
    'tournaments': <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> fetchPublicTournaments({
    required String identityToken,
  }) async => {
    'featured': const <Map<String, dynamic>>[],
    'tournaments': tournaments,
  };

  @override
  Future<Map<String, dynamic>> joinPublicRace({
    required String identityToken,
    required String raceId,
    bool onboarding = false,
  }) async {
    joinedRaceIds.add(raceId);
    if (joinGate != null) await joinGate!.future;
    return {
      'participant': {'id': 'rp-1', 'raceId': raceId},
    };
  }

  @override
  Future<Map<String, dynamic>> joinTournament({
    required String identityToken,
    required String tournamentId,
  }) async {
    joinedTournamentIds.add(tournamentId);
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 320, 'heldCoins': 0};
}

Future<AuthService> _publicAuth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 420,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpPublicRaces(WidgetTester tester, _PublicRacesApi api) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: PublicRacesScreen(
        authService: await _publicAuth(),
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
}

Map<String, dynamic> _tournament({
  required String id,
  required String name,
  int accepted = 3,
  int bracketSize = 8,
}) => {
  'id': id,
  'name': name,
  'status': 'PENDING',
  'bracketSize': bracketSize,
  'acceptedCount': accepted,
  'matchupDurationDays': 1,
  'championPrizeCoins': 300,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'America/New_York',
        );
  });

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.6',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('entry point 1 — home suggested-race carousel', () {
    testWidgets('card body previews the race and does NOT join', (
      tester,
    ) async {
      final taps = _Taps();
      await _pumpHome(
        tester,
        taps: taps,
        suggestions: Loadable.success(_suggestions([_publicSuggestion])),
      );
      await _revealCarousel(tester);

      await tester.tap(
        find.byKey(const Key('home-suggestion-PUBLIC_RACE-race-public-1')),
      );
      await tester.pump();

      expect(taps.openedRaces, ['race-public-1']);
      expect(taps.joinedSuggestions, isEmpty);
    });

    testWidgets('a TOURNAMENT card body previews the bracket', (tester) async {
      final taps = _Taps();
      await _pumpHome(
        tester,
        taps: taps,
        suggestions: Loadable.success(_suggestions([_tournamentSuggestion])),
      );
      await _revealCarousel(tester);

      await tester.tap(
        find.byKey(const Key('home-suggestion-TOURNAMENT-tournament-1')),
      );
      await tester.pump();

      expect(taps.openedTournaments, ['tournament-1']);
      expect(taps.openedRaces, isEmpty);
      expect(taps.joinedSuggestions, isEmpty);
    });

    testWidgets('the JOIN pill still joins directly (regression guard)', (
      tester,
    ) async {
      final taps = _Taps();
      await _pumpHome(
        tester,
        taps: taps,
        suggestions: Loadable.success(_suggestions([_publicSuggestion])),
      );
      await _revealCarousel(tester);

      await tester.tap(
        find.byKey(const Key('home-suggestion-join-PUBLIC_RACE-race-public-1')),
      );
      await tester.pump();

      expect(taps.joinedSuggestions, ['race-public-1']);
      expect(taps.openedRaces, isEmpty);
    });

    testWidgets('a DISABLED JOIN pill falls through to preview', (
      tester,
    ) async {
      final taps = _Taps();
      final parsed = _suggestions([_publicSuggestion]);
      await _pumpHome(
        tester,
        taps: taps,
        suggestions: Loadable.success(parsed),
        // "JOINING..." — the pill is disabled mid-join.
        joiningSuggestionKeys: {parsed.single.stableKey},
      );
      await _revealCarousel(tester);
      expect(find.text('JOINING...'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('home-suggestion-join-PUBLIC_RACE-race-public-1')),
      );
      await tester.pump();

      expect(taps.openedRaces, ['race-public-1']);
      expect(taps.joinedSuggestions, isEmpty);
    });

    testWidgets('semantics name both the preview tap and the JOIN button', (
      tester,
    ) async {
      final taps = _Taps();
      await _pumpHome(
        tester,
        taps: taps,
        suggestions: Loadable.success(_suggestions([_publicSuggestion])),
      );
      await _revealCarousel(tester);

      expect(
        find.bySemanticsLabel(
          RegExp(
            'Public.*Lunch Break Sprint.*'
            'View Lunch Break Sprint, Join Lunch Break Sprint button',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the tutorial\'s fake home leaves the card body inert', (
      tester,
    ) async {
      final taps = _Taps();
      await _pumpHome(
        tester,
        taps: taps,
        suggestions: Loadable.success(_suggestions([_publicSuggestion])),
        isTutorialPreview: true,
      );
      await _revealCarousel(tester);

      await tester.tap(
        find.byKey(const Key('home-suggestion-PUBLIC_RACE-race-public-1')),
      );
      await tester.pump();

      expect(taps.openedRaces, isEmpty);
      expect(taps.openedTournaments, isEmpty);
    });
  });

  group('entry point 2 — home "next race" open-races row', () {
    Map<String, dynamic> raceCard() => const {
      'state': 'EMPTY',
      'nextRace': {
        'resolved': true,
        'eligible': true,
        'discoveryEnabled': true,
        'createEnabled': false,
        'openRaces': [
          {'id': 'open-1', 'name': 'First', 'participantCount': 2},
        ],
      },
    };

    testWidgets('row body previews and does NOT join', (tester) async {
      final taps = _Taps();
      await _pumpHome(tester, taps: taps, raceCard: raceCard());

      await tester.tap(find.byKey(const Key('home-next-race-row-open-1')));
      await tester.pump();

      expect(taps.openedRaces, ['open-1']);
      expect(taps.joinedRaces, isEmpty);
    });

    testWidgets('the join icon still joins directly (regression guard)', (
      tester,
    ) async {
      final taps = _Taps();
      await _pumpHome(tester, taps: taps, raceCard: raceCard());

      await tester.tap(find.byKey(const Key('home-join-open-1')));
      await tester.pump();

      expect(taps.joinedRaces, ['open-1']);
      expect(taps.openedRaces, isEmpty);
    });

    testWidgets('a DISABLED join icon falls through to preview', (
      tester,
    ) async {
      final taps = _Taps();
      final gate = Completer<void>();
      await _pumpHome(tester, taps: taps, raceCard: raceCard(), joinGate: gate);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      // First tap starts the join and disables the icon while it is in flight.
      await tester.tap(find.byKey(const Key('home-join-open-1')));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('home-join-open-1')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('home-join-open-1')));
      await tester.pump();

      expect(taps.openedRaces, ['open-1']);
      // Still exactly the one join from the first tap.
      expect(taps.joinedRaces, ['open-1']);

      gate.complete();
      await tester.pump();
    });
  });

  // Entry points 3 (friend-racing card) and 4 (public-race row) live in
  // `_buildRaceOpportunityRow`, which today is reachable ONLY through
  // `_buildPendingInviteSection` — and that early-returns for every state
  // except PENDING_INVITE (the RACES rows were superseded by the suggested-
  // races carousel in batch 2026-08-10b). So these two branches cannot be
  // exercised through the real screen, and per this repo's "unit test only
  // when an integration test structurally cannot express the property" rule
  // they get a structural guard instead — plus the tripwire below, which fails
  // the moment they DO render again, at which point the widget tests in the
  // groups above are the model to copy.
  group('entry points 3 and 4 — home race rows', () {
    /// `home_tab.dart` with `//` comments stripped and whitespace collapsed, so
    /// these guards pin CODE and never break on a comment reflow.
    final code = File('lib/screens/tabs/home_tab.dart')
        .readAsLinesSync()
        .map((l) => l.replaceFirst(RegExp(r'\s*//.*$'), ''))
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    /// The body of one `case RaceCardState.<name>:` arm.
    String arm(String name) {
      final start = code.indexOf('case RaceCardState.$name:');
      expect(start, isNonNegative, reason: 'no $name arm in home_tab.dart');
      final next = code.indexOf('case RaceCardState.', start + 1);
      return code.substring(start, next == -1 ? code.length : next);
    }

    test('friend-racing row body previews ONLY when isPublicJoinable', () {
      // Scope correction: a private friend race has no participant row for the
      // viewer and still 403s, so it must get NO preview tap target. The gate
      // is the whole point of this assertion — an ungated _previewRaceTap here
      // would route to a race the viewer cannot access.
      expect(
        arm('friendRacing'),
        contains(
          'onCardTap: isPublicJoinable ? _previewRaceTap(raceId) : null',
        ),
      );
    });

    test('public-race row body always previews', () {
      // Unconditional — a PUBLIC row is public by definition.
      expect(arm('publicRace'), contains('onCardTap: _previewRaceTap(raceId)'));
      expect(arm('publicRace'), isNot(contains('isPublicJoinable')));
    });

    test('_previewRaceTap is inert in the tutorial preview', () {
      expect(
        code,
        contains(
          'VoidCallback? _previewRaceTap(String raceId) { final open = '
          'onOpenRace; if (isTutorialPreview || open == null || '
          'raceId.isEmpty) return null;',
        ),
      );
    });

    // TRIPWIRE for the premise above, not an endorsement of the gap: today the
    // backend's FRIEND_RACING / PUBLIC_RACE home-card states render no row at
    // all. If that changes, this fails and the structural guards above must be
    // replaced with real card-body-tap widget tests.
    testWidgets('these rows do not render through HomeTab today', (
      tester,
    ) async {
      for (final state in ['FRIEND_RACING', 'PUBLIC_RACE']) {
        await _pumpHome(
          tester,
          taps: _Taps(),
          raceCard: {
            'state': state,
            'race': {
              'id': 'race-x',
              'name': 'Friendly',
              'participantCount': 4,
              'isPublicJoinable': true,
            },
            'friend': {'displayName': 'Sam'},
            'isPublicJoinable': true,
          },
        );
        expect(
          find.byKey(const Key('home-race-row-friend-racing')),
          findsNothing,
          reason: '$state now renders a row — write a real widget test',
        );
        expect(find.byKey(const Key('home-race-row-public')), findsNothing);
      }
    });
  });

  group('entry points 5 and 6 — public_races_screen', () {
    testWidgets('race card body pushes RaceDetailScreen without joining', (
      tester,
    ) async {
      final api = _PublicRacesApi();
      await _pumpPublicRaces(tester, api);
      await tester.tap(find.byKey(const Key('public-filter-races')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('public-race-card-race-1')));
      await tester.pump();

      expect(
        find.byType(RaceDetailScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(api.joinedRaceIds, isEmpty);
    });

    testWidgets('race card JOIN pill still joins directly (regression guard)', (
      tester,
    ) async {
      final api = _PublicRacesApi();
      await _pumpPublicRaces(tester, api);
      await tester.tap(find.byKey(const Key('public-filter-races')));
      await tester.pump();

      await tester.tap(find.text('JOIN'));
      await tester.pump();
      await tester.pump();

      expect(api.joinedRaceIds, ['race-1']);
      expect(find.byType(RaceDetailScreen, skipOffstage: false), findsNothing);
    });

    testWidgets('a race card\'s disabled JOIN pill falls through to preview', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = _PublicRacesApi(joinGate: gate);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await _pumpPublicRaces(tester, api);
      await tester.tap(find.byKey(const Key('public-filter-races')));
      await tester.pump();

      // First tap starts the join, which disables the pill ("JOINING...").
      await tester.tap(find.text('JOIN'));
      await tester.pump();
      final joiningPill = find.ancestor(
        of: find.text('JOINING...'),
        matching: find.byType(PillButton),
      );
      expect(joiningPill, findsOneWidget);
      expect(tester.widget<PillButton>(joiningPill).onPressed, isNull);

      await tester.tap(joiningPill);
      await tester.pump();

      expect(
        find.byType(RaceDetailScreen, skipOffstage: false),
        findsOneWidget,
      );
      // Still exactly the one join from the first tap.
      expect(api.joinedRaceIds, ['race-1']);
    });

    testWidgets('tournament card body pushes TournamentDetailScreen', (
      tester,
    ) async {
      final api = _PublicRacesApi(
        tournaments: [_tournament(id: 'tour-1', name: 'Open Bracket')],
      );
      await _pumpPublicRaces(tester, api);
      await tester.tap(find.byKey(const Key('public-filter-tournaments')));
      await tester.pump();

      await tester.tap(find.text('OPEN BRACKET'));
      await tester.pump();

      expect(
        find.byType(TournamentDetailScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(api.joinedTournamentIds, isEmpty);
    });

    testWidgets('tournament card JOIN pill still joins directly', (
      tester,
    ) async {
      final api = _PublicRacesApi(
        tournaments: [_tournament(id: 'tour-1', name: 'Open Bracket')],
      );
      await _pumpPublicRaces(tester, api);
      await tester.tap(find.byKey(const Key('public-filter-tournaments')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('user-tournament-join-tour-1')));
      await tester.pump();
      await tester.pump();

      expect(api.joinedTournamentIds, ['tour-1']);
    });

    testWidgets('a FULL tournament\'s disabled CTA falls through to preview', (
      tester,
    ) async {
      final api = _PublicRacesApi(
        tournaments: [
          _tournament(
            id: 'tour-full',
            name: 'Packed Bracket',
            accepted: 8,
            bracketSize: 8,
          ),
        ],
      );
      await _pumpPublicRaces(tester, api);
      await tester.tap(find.byKey(const Key('public-filter-tournaments')));
      await tester.pump();

      expect(find.text('FULL'), findsOneWidget);
      expect(
        tester
            .widget<PillButton>(
              find.byKey(const Key('user-tournament-join-tour-full')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('user-tournament-join-tour-full')));
      await tester.pump();

      expect(
        find.byType(TournamentDetailScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(api.joinedTournamentIds, isEmpty);
    });
  });

  group('TournamentGameCard.onCardTap', () {
    testWidgets('body tap fires onCardTap; CTA tap fires onPressed', (
      tester,
    ) async {
      var cardTaps = 0;
      var ctaTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TournamentGameCard(
                name: 'OPEN BRACKET',
                metaLine: '8 RACERS · 1-DAY KNOCKOUTS',
                filledLabel: '3/8 IN',
                prizeLabel: 'CHAMPION WINS',
                prizeValue: 300,
                ctaLabel: 'JOIN',
                ctaVariant: PillButtonVariant.primary,
                ctaKey: const Key('cta'),
                onPressed: () => ctaTaps++,
                onCardTap: () => cardTaps++,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN BRACKET'));
      await tester.pump();
      expect(cardTaps, 1);
      expect(ctaTaps, 0);

      await tester.tap(find.byKey(const Key('cta')));
      await tester.pump();
      expect(ctaTaps, 1);
      expect(cardTaps, 1);
    });

    testWidgets('a disabled CTA falls through to onCardTap', (tester) async {
      var cardTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TournamentGameCard(
                name: 'PACKED BRACKET',
                metaLine: '8 RACERS · 1-DAY KNOCKOUTS',
                filledLabel: '8/8 IN',
                prizeLabel: 'CHAMPION WINS',
                prizeValue: 300,
                ctaLabel: 'FULL',
                ctaVariant: PillButtonVariant.secondary,
                ctaKey: const Key('cta'),
                onPressed: null,
                onCardTap: () => cardTaps++,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('cta')));
      await tester.pump();
      expect(cardTaps, 1);
    });

    testWidgets('without onCardTap the body stays inert (compat)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TournamentGameCard(
                name: 'OPEN BRACKET',
                metaLine: 'meta',
                filledLabel: '3/8 IN',
                prizeLabel: 'CHAMPION WINS',
                prizeValue: 0,
                ctaLabel: 'JOIN',
                ctaVariant: PillButtonVariant.primary,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(GestureDetector), findsOneWidget);
      await tester.tap(find.text('OPEN BRACKET'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
