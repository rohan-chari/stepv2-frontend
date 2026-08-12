import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Batch 2026-07-27 item 4 — the audit turned up a second site with the same
/// defect as `PillButton`'s "EXTRA SPIN": a label that silently ellipsizes
/// rather than shrinking.
///
/// The home race row's action button is not a `PillButton`, so the `FittedBox`
/// fix never reached it. Its box is a fixed 78pt, which means "CHALLENGE" — the
/// longest label it is ever handed — truncates at EVERY screen width, not just
/// narrow ones. A fixed box makes this screen-independent, which is why no
/// responsive test would have caught it.

class _FakeApi extends BackendApiService {}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

HomeRaceSuggestion _suggestion() => HomeRaceSuggestion.tryParse({
  'kind': 'PUBLIC_RACE',
  'id': 'race-1',
  'name': 'Weekend Dash',
  'status': 'PENDING',
  'maxDurationDays': 3,
  'endsAt': null,
  'startedAt': null,
  'participantCount': 3,
  'maxParticipants': 10,
  'buyInAmount': 0,
  'payoutPreset': null,
  'powerupsEnabled': true,
  'prizePool': null,
  'isTeamRace': false,
  'teamSize': null,
  'teamAName': null,
  'teamBName': null,
  'teams': null,
  'joinAction': 'JOIN',
})!;

Future<void> _pumpHome(WidgetTester tester, {required double width}) async {
  await tester.binding.setSurfaceSize(Size(width, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HomeTab(
          key: UniqueKey(),
          stepData: StepData(steps: 2400, date: DateTime(2026, 7, 27)),
          isLoading: false,
          error: null,
          healthAuthorized: true,
          notificationsState: true,
          displayName: 'Trail Walker',
          authService: auth,
          backendApiService: _FakeApi(),
          onRefresh: () async {},
          onEnableHealth: () {},
          onEnableNotifications: () {},
          onDisplayNameChanged: () {},
          friendsSteps: const [],
          suggestedRacesState: Loadable.success([_suggestion()]),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 320pt is the iPhone SE 1st gen; 375pt the SE 2/3 and the 13 mini. The box
  // is fixed, so both must pass for the same reason.
  for (final width in [320.0, 375.0]) {
    testWidgets('JOIN is not truncated on the Home suggestion at ${width}pt', (
      tester,
    ) async {
      await _pumpHome(tester, width: width);

      expect(find.text('JOIN'), findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(find.text('JOIN'));
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: 'JOIN ellipsized inside the suggestion action button',
      );
    });
  }
}
