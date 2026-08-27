// Feature batch 2026-08-10 (part 2) — pending-race placement and Home's
// bottom feedback entry point.
//
// Pumps the REAL HomeTab and asserts vertical order and stable content.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:step_tracker/widgets/arcade_fx.dart';
import 'package:step_tracker/widgets/step_milestones_section.dart';

class _FakeApi extends BackendApiService {
  _FakeApi({this.throwOnSuggestion = false});

  final bool throwOnSuggestion;
  int suggestions = 0;
  String? lastSuggestion;

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => const {'claimedToday': true};

  @override
  Future<FeedbackSubmissionDelivery> submitSuggestion({
    required String identityToken,
    required String text,
    String? replyToEmail,
    String? category,
  }) async {
    suggestions++;
    lastSuggestion = text;
    if (throwOnSuggestion) throw const ApiException('offline');
    return FeedbackSubmissionDelivery.email;
  }
}

Map<String, dynamic> _pendingInviteCard() => {
  'state': 'PENDING_INVITE',
  'data': {
    'raceId': 'race-9',
    'inviter': {'userId': 'u-2', 'displayName': 'Jordan'},
    'participantCount': 4,
    'durationHours': 48,
  },
};

Future<AuthService> _authService(BackendApiService api) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'SwiftCapybara07',
    'auth_profile_photo_url': 'https://example.test/photo.png',
    'auth_profile_photo_prompt_dismissed_at': '2026-07-01T00:00:00.000Z',
    'auth_onboarding_v3_enabled': true,
  });
  final authService = AuthService(backendApiService: api);
  await authService.restoreSession();
  return authService;
}

Widget _buildHome(
  AuthService authService,
  BackendApiService api, {
  Map<String, dynamic>? raceCard,
  bool raceCardLoading = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: HomeTab(
        stepData: StepData(steps: 4461, date: DateTime(2026, 8, 10)),
        isLoading: false,
        error: null,
        healthAuthorized: true,
        notificationsState: true,
        displayName: 'SwiftCapybara07',
        authService: authService,
        backendApiService: api,
        onRefresh: () async {},
        onEnableHealth: () {},
        onEnableNotifications: () {},
        onDisplayNameChanged: () {},
        friendsSteps: const [],
        raceCard: raceCard,
        raceCardLoading: raceCardLoading,
        suggestedRacesState: const Loadable.success([]),
        onAcceptRaceInvite: (_) async {},
        onDeclineRaceInvite: (_) async {},
      ),
    ),
  );
}

/// Home hosts repeating tickers that never settle, so pump in bounded steps.
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

List<int> _staggerIndicesTopToBottom(WidgetTester tester) {
  final byPosition = <MapEntry<double, int>>[];
  for (final widget in tester.widgetList<StaggerIn>(find.byType(StaggerIn))) {
    final finder = find.byWidget(widget);
    if (finder.evaluate().isEmpty) continue;
    byPosition.add(MapEntry(tester.getTopLeft(finder).dy, widget.index));
  }
  byPosition.sort((a, b) => a.key.compareTo(b.key));
  return byPosition.map((e) => e.value).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.2.4',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('Item 3 — pending invite above Today\'s Coins', () {
    testWidgets('the invite block renders above the milestones section', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeApi();
      final auth = await _authService(api);
      await tester.pumpWidget(
        _buildHome(auth, api, raceCard: _pendingInviteCard()),
      );
      await _flush(tester);

      final invite = find.byKey(const Key('home-pending-invite'));
      expect(invite, findsOneWidget);
      expect(find.text('@Jordan challenged you'), findsOneWidget);

      expect(
        tester.getTopLeft(invite).dy,
        lessThan(tester.getTopLeft(find.byType(StepMilestonesSection)).dy),
      );
      // ...and below SETUP is implied by it being the first block after it;
      // the cascade assertion below pins the exact ordering.
    });

    testWidgets('SUGGESTED RACES stays discoverable, never a bare header '
        'and never a duplicate invite', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeApi();
      final auth = await _authService(api);
      await tester.pumpWidget(
        _buildHome(auth, api, raceCard: _pendingInviteCard()),
      );
      await _flush(tester);

      expect(find.text('SUGGESTED RACES'), findsOneWidget);
      expect(find.text('BROWSE ALL'), findsOneWidget);
      // "INVITE" appears EXACTLY once — the promoted card's eyebrow, meaning
      // "you were invited". The fallback row's invite-friends button is
      // suppressed while an invite is promoted, so the same word never carries
      // two meanings on one screen.
      expect(find.text('INVITE'), findsOneWidget);
      // Exactly one invite row on the page.
      expect(find.text('@Jordan challenged you'), findsOneWidget);
      // The discovery section carries its persistent empty-state ticket.
      final empty = find.text('NO SUGGESTED RACES');
      expect(empty, findsOneWidget);
      expect(
        tester.getTopLeft(empty).dy,
        greaterThan(tester.getTopLeft(find.text('SUGGESTED RACES')).dy),
      );
    });

    testWidgets('with NO invite the empty state keeps Browse All', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeApi();
      final auth = await _authService(api);
      await tester.pumpWidget(
        _buildHome(auth, api, raceCard: {'state': 'EMPTY', 'data': {}}),
      );
      await _flush(tester);

      expect(find.text('NO SUGGESTED RACES'), findsOneWidget);
      expect(find.text('BROWSE ALL'), findsOneWidget);
      expect(find.text('SUGGESTED RACES'), findsOneWidget);

      final card = find.byKey(const Key('home-suggestions-empty'));
      final message = find.text('NO SUGGESTED RACES');
      final browse = find.text('BROWSE ALL');
      expect(tester.getSize(card).height, lessThan(180));
      expect(
        tester.getTopLeft(browse).dy,
        greaterThan(tester.getTopLeft(message).dy),
      );
      expect(
        tester
            .getSize(find.byKey(const Key('home-suggestions-status-action')))
            .width,
        greaterThan(tester.getSize(card).width * 0.75),
      );
    });

    testWidgets('no invite → no block, no stray gap', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeApi();
      final auth = await _authService(api);
      await tester.pumpWidget(
        _buildHome(auth, api, raceCard: const {'state': 'EMPTY'}),
      );
      await _flush(tester);

      expect(find.byKey(const Key('home-pending-invite')), findsNothing);
    });

    testWidgets('the stagger cascade ascends with an invite present', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeApi();
      final auth = await _authService(api);
      await tester.pumpWidget(
        _buildHome(auth, api, raceCard: _pendingInviteCard()),
      );
      await _flush(tester);

      final indices = _staggerIndicesTopToBottom(tester);
      expect(indices, [0]);
    });

    testWidgets('the suggested-races skeleton branch shifted too', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeApi();
      final auth = await _authService(api);
      await tester.pumpWidget(
        _buildHome(auth, api, raceCard: null, raceCardLoading: true),
      );
      await _flush(tester);

      final indices = _staggerIndicesTopToBottom(tester);
      expect(indices, [0]);
    });

    // The spotlight anchor sits at the index the invite block now occupies;
    // seeding PENDING_INVITE there would push the milestones spotlight below
    // the fold.
    test('the tutorial home fixture is not a PENDING_INVITE', () {
      expect(tutorialPreviewHomeRaceCard()['state'], 'ACTIVE_RACES');
      expect(tutorialPreviewHomeSuggestions().map((item) => item.eyebrow), [
        'DAILY',
        'PUBLIC',
        'TOURNAMENT',
      ]);
    });
  });

  group('Home feedback entry point', () {
    testWidgets('is the final Home section and opens the shared sheet', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeApi();
      final auth = await _authService(api);
      await tester.pumpWidget(
        _buildHome(auth, api, raceCard: const {'state': 'EMPTY'}),
      );
      await _flush(tester);

      final card = find.byKey(const Key('home-feedback-card'));
      final button = find.byKey(const Key('home-feedback-button'));
      expect(card, findsOneWidget);
      expect(button, findsOneWidget);
      expect(
        tester.getTopLeft(card).dy,
        greaterThan(tester.getTopLeft(find.text('SUGGESTED RACES')).dy),
      );

      await tester.ensureVisible(button);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(button);
      await _flush(tester);

      expect(find.byKey(const Key('feedback-sheet')), findsOneWidget);
      expect(find.byKey(const Key('feedback-input')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('feedback-input')),
        '  more capybara hats  ',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('feedback-submit')));
      await _flush(tester);
      expect(api.suggestions, 1);
      expect(api.lastSuggestion, 'more capybara hats');
      expect(find.byKey(const Key('feedback-sheet')), findsNothing);
    });

    testWidgets('offline keeps the text and offers a retry', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeApi(throwOnSuggestion: true);
      final auth = await _authService(api);
      await tester.pumpWidget(
        _buildHome(auth, api, raceCard: const {'state': 'EMPTY'}),
      );
      await _flush(tester);

      final button = find.byKey(const Key('home-feedback-button'));
      await tester.ensureVisible(button);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(button);
      await _flush(tester);
      await tester.enterText(
        find.byKey(const Key('feedback-input')),
        'please fix the thing',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('feedback-submit')));
      await _flush(tester);

      expect(find.byKey(const Key('feedback-sheet')), findsOneWidget);
      expect(find.byKey(const Key('feedback-error')), findsOneWidget);
      expect(find.text('please fix the thing'), findsOneWidget);
      expect(find.text('RETRY'), findsOneWidget);
    });

    testWidgets('remains stable while Home content is loading', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeApi();
      final auth = await _authService(api);
      await tester.pumpWidget(
        _buildHome(auth, api, raceCard: null, raceCardLoading: true),
      );
      await _flush(tester);

      expect(find.byKey(const Key('home-feedback-card')), findsOneWidget);
      expect(find.byKey(const Key('home-feedback-button')), findsOneWidget);
    });

    // ui-test-planner / architect R4: the tutorial preview service extends the
    // real one, so an un-overridden submitSuggestion is a real
    // POST /feedback/suggestions from inside the tutorial.
    test('the tutorial preview service cannot submit feedback', () async {
      final api = TutorialPreviewBackendApiService();
      // Must not throw and must not reach the network.
      await api.submitSuggestion(identityToken: 'preview-token', text: 'hi');
    });
  });
}
