import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _PendingRaceApi extends BackendApiService {
  _PendingRaceApi({required this.automatic});

  final bool automatic;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => {
    'id': raceId,
    'name': automatic ? 'Weekend Sprint' : 'Custom Race',
    'status': 'PENDING',
    'isPublic': true,
    if (automatic) 'creationSource': 'QUICK_CREATE',
    if (automatic) 'startPolicy': 'ON_MINIMUM_PARTICIPANTS',
    'targetSteps': 20000,
    'maxDurationDays': 2,
    'buyInAmount': 0,
    'payoutPreset': 'TOP3_70_20_10',
    'potCoins': 0,
    'myStatus': 'ACCEPTED',
    'isCreator': true,
    'participants': const [
      {'userId': 'user-1', 'displayName': 'Walker', 'status': 'ACCEPTED'},
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 100, 'heldCoins': 0};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'identity',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(
  WidgetTester tester, {
  required bool automatic,
  bool demoMode = false,
  bool showPrompt = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        backendApiService: _PendingRaceApi(automatic: automatic),
        raceId: '550e8400-e29b-41d4-a716-446655440000',
        demoMode: demoMode,
        showPostCreateSharePrompt: showPrompt,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'quick pending detail replaces manual start and shows share nudge',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, automatic: true, showPrompt: true);

      expect(find.byKey(const Key('quick-race-share-prompt')), findsOneWidget);
      expect(
        find.byKey(const Key('quick-race-auto-start-pending')),
        findsOneWidget,
      );
      expect(find.text('WAITING FOR ANOTHER WALKER'), findsOneWidget);
      expect(find.text('START RACE'), findsNothing);
      expect(find.textContaining('Need at least 2'), findsNothing);
      expect(find.byKey(const Key('quick-race-inline-share')), findsOneWidget);
    },
  );

  testWidgets('manual and demo pending races retain their guarded behavior', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, automatic: false);
    expect(
      find.byKey(const Key('quick-race-auto-start-pending')),
      findsNothing,
    );
    expect(find.text('START RACE'), findsOneWidget);

    await _pump(tester, automatic: true, demoMode: true, showPrompt: true);
    expect(find.byKey(const Key('quick-race-share-prompt')), findsNothing);
    expect(
      find.byKey(const Key('quick-race-auto-start-pending')),
      findsNothing,
    );
  });
}
