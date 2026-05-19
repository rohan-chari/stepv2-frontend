import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _EmptyPublicRacesApi extends BackendApiService {
  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async {
    return const [];
  }
}

class _NonEmptyPublicRacesApi extends BackendApiService {
  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async {
    return [
      {
        'id': 'race-1',
        'name': 'Gold Sprint',
        'targetSteps': 50000,
        'participantCount': 1,
        'maxParticipants': 10,
        'buyInAmount': 0,
        'creator': {'displayName': 'RaceMaker'},
        'powerupsEnabled': false,
      },
    ];
  }
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 420,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty public races shows placeholder with icon, heading, and CTA',
      (WidgetTester tester) async {
    final authService = await _authService();
    final api = _EmptyPublicRacesApi();

    await tester.pumpWidget(
      MaterialApp(
        home: PublicRacesScreen(
          authService: authService,
          backendApiService: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Heading
    expect(find.text('NO PUBLIC RACES'), findsOneWidget);

    // CTA button
    expect(find.text('CREATE A RACE'), findsOneWidget);

    // An icon from the allowed set
    final allowedIcons = {
      Icons.flag_outlined,
      Icons.directions_run_outlined,
      Icons.emoji_events_outlined,
    };
    final iconWidgets = tester.widgetList<Icon>(find.byType(Icon));
    expect(
      iconWidgets.any((i) => allowedIcons.contains(i.icon)),
      isTrue,
      reason: 'Expected one of the suggested empty-state icons',
    );
  });

  testWidgets('tapping Create a Race CTA navigates to CreateRaceScreen',
      (WidgetTester tester) async {
    final authService = await _authService();
    final api = _EmptyPublicRacesApi();

    await tester.pumpWidget(
      MaterialApp(
        home: PublicRacesScreen(
          authService: authService,
          backendApiService: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CreateRaceScreen), findsNothing);

    await tester.tap(find.text('CREATE A RACE'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateRaceScreen), findsOneWidget);
  });

  testWidgets('non-empty public races does not render placeholder',
      (WidgetTester tester) async {
    final authService = await _authService();
    final api = _NonEmptyPublicRacesApi();

    await tester.pumpWidget(
      MaterialApp(
        home: PublicRacesScreen(
          authService: authService,
          backendApiService: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NO PUBLIC RACES'), findsNothing);
    expect(find.text('CREATE A RACE'), findsNothing);
    expect(find.text('Gold Sprint'.toUpperCase()), findsOneWidget);
  });
}
