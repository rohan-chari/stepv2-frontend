import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _HeaderTestBackendApiService extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Header Test Race',
      'status': 'PENDING',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 0,
      'payouts': {'first': 0, 'second': 0, 'third': 0},
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 0, 'heldCoins': 0};
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 0,
    'auth_held_coins': 0,
  });

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'RaceDetailScreen main scroll view clips its overscrolling content '
    'so it cannot render over the fixed header',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _HeaderTestBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-header-1',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Find the main page SingleChildScrollView (the vertical one inside the
      // RefreshIndicator — the race-day hero contributes its own horizontal
      // course scroller).
      final scrollFinder = find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.scrollDirection == Axis.vertical,
        ),
      );
      expect(scrollFinder, findsOneWidget);

      final scrollView = tester.widget<SingleChildScrollView>(scrollFinder);
      expect(
        scrollView.clipBehavior,
        isNot(Clip.none),
        reason:
            'The main scroll view must clip its content so overscrolled '
            'content does not render over the fixed header above it.',
      );
    },
  );

  testWidgets(
    'RaceDetailScreen header has an opaque background color so scrolled '
    'content cannot be seen through it',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _HeaderTestBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-header-2',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The header contains the back-arrow icon. Find the nearest Container
      // ancestor of that icon -- that is the header Container.
      final backArrow = find.byIcon(Icons.arrow_back);
      expect(backArrow, findsOneWidget);

      final headerContainerFinder = find
          .ancestor(of: backArrow, matching: find.byType(Container))
          .first;
      expect(headerContainerFinder, findsOneWidget);

      final headerContainer = tester.widget<Container>(headerContainerFinder);

      // Read the background color from either `color` or `decoration`.
      Color? bgColor = headerContainer.color;
      final decoration = headerContainer.decoration;
      if (bgColor == null && decoration is BoxDecoration) {
        bgColor = decoration.color;
      }

      expect(
        bgColor,
        isNotNull,
        reason: 'Header Container must have a background color set.',
      );
      expect(
        (bgColor!.a * 255.0).round().clamp(0, 255),
        equals(0xFF),
        reason:
            'Header Container background must be fully opaque so scrolled '
            'content cannot show through it.',
      );
    },
  );
}
