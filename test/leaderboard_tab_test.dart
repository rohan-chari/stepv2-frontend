import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/leaderboard_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/home_course_track.dart'
    show AnimatedCapybaraWithAccessories;

class _FakeBackendApiService extends BackendApiService {
  final List<({String type, String period})> leaderboardCalls = [];

  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async {
    leaderboardCalls.add((type: type, period: period));

    switch (type) {
      case 'races':
        return {
          'top100': [
            {
              'rank': 1,
              'userId': 'race-1',
              'displayName': 'AtlasRun',
              'firsts': 1,
              'seconds': 1,
              'thirds': 0,
            },
            {
              'rank': 2,
              'userId': 'user-1',
              'displayName': 'Trail Walker',
              'firsts': 1,
              'seconds': 0,
              'thirds': 2,
            },
          ],
          'currentUser': {
            'rank': 2,
            'displayName': 'Trail Walker',
            'firsts': 1,
            'seconds': 0,
            'thirds': 2,
            'inTop100': true,
          },
        };
      case 'steps':
      default:
        return {
          'top100': [
            {
              'rank': 1,
              'userId': 'other-user',
              'displayName': 'AceWinner',
              'totalSteps': 12000,
              'equippedAccessories': [
                {'slot': 'HEAD', 'assetKey': 'top-hat'},
              ],
            },
            {
              'rank': 2,
              'userId': 'user-1',
              'displayName': 'Trail Walker',
              'totalSteps': 11000,
              'equippedAccessories': [
                {'slot': 'BODY', 'assetKey': 'hoodie'},
              ],
            },
            {
              'rank': 3,
              'userId': 'third-user',
              'displayName': 'BronzeWalker',
              'totalSteps': 10000,
              'equippedAccessories': [
                {'slot': 'FEET', 'assetKey': 'boots'},
              ],
            },
          ],
          'currentUser': {
            'rank': 2,
            'displayName': 'Trail Walker',
            'totalSteps': 11000,
            'inTop100': true,
          },
        };
    }
  }
}

class _LargeStepsApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async => const {
    'top100': [
      {'rank': 1, 'userId': 'one', 'displayName': 'One', 'totalSteps': 2400000},
      {'rank': 2, 'userId': 'two', 'displayName': 'Two', 'totalSteps': 999999},
      {
        'rank': 3,
        'userId': 'three',
        'displayName': 'Three',
        'totalSteps': 99949,
      },
      {
        'rank': 4,
        'userId': 'user-1',
        'displayName': 'Trail Walker',
        'totalSteps': 1983700,
      },
      {
        'rank': 5,
        'userId': 'five',
        'displayName': 'Five',
        'totalSteps': 100000,
      },
      {'rank': 6, 'userId': 'six', 'displayName': 'Six', 'totalSteps': 999499},
      {
        'rank': 7,
        'userId': 'seven',
        'displayName': 'Seven',
        'totalSteps': 99950,
      },
    ],
    'currentUser': {
      'rank': 4,
      'displayName': 'Trail Walker',
      'totalSteps': 1983700,
      'inTop100': true,
    },
  };
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_step_goal': 8000,
  });

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Widget _buildLeaderboard({
  required AuthService authService,
  required BackendApiService backendApiService,
}) {
  return MaterialApp(
    home: Scaffold(
      body: LeaderboardTab(
        authService: authService,
        backendApiService: backendApiService,
        stepData: StepData(steps: 6543, date: DateTime(2026, 4, 7)),
        displayName: 'Trail Walker',
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LeaderboardTab defaults to steps with the period filter visible',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FakeBackendApiService();

      await tester.pumpWidget(
        _buildLeaderboard(
          authService: authService,
          backendApiService: backendApiService,
        ),
      );
      await tester.pump();

      expect(backendApiService.leaderboardCalls, [
        (type: 'steps', period: 'today'),
      ]);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('BOARDS'), findsOneWidget);
      expect(find.text('12.0K'), findsOneWidget);
    },
  );

  testWidgets(
    'LeaderboardTab shows styled race podium badges and hides the period filter',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FakeBackendApiService();

      await tester.pumpWidget(
        _buildLeaderboard(
          authService: authService,
          backendApiService: backendApiService,
        ),
      );
      await tester.pump();

      expect(find.text('RACES'), findsNothing);
      expect(find.text('TODAY'), findsOneWidget);
      expect(
        find.byKey(const Key('leaderboard-race-podiums-AtlasRun')),
        findsNothing,
      );
    },
  );

  testWidgets('LeaderboardTab keeps podium ranks on pedestals only', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();

    await tester.pumpWidget(
      _buildLeaderboard(
        authService: authService,
        backendApiService: _FakeBackendApiService(),
      ),
    );
    await tester.pump();

    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsNothing);
    expect(find.text('3'), findsNothing);
    expect(find.text('1ST'), findsOneWidget);
    expect(find.text('2ND'), findsOneWidget);
    expect(find.text('3RD'), findsOneWidget);
  });

  testWidgets('LeaderboardTab podium capybaras wear equipped accessories', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();

    await tester.pumpWidget(
      _buildLeaderboard(
        authService: authService,
        backendApiService: _FakeBackendApiService(),
      ),
    );
    await tester.pump();

    final capybaras = tester
        .widgetList<AnimatedCapybaraWithAccessories>(
          find.byType(AnimatedCapybaraWithAccessories),
        )
        .toList();
    expect(capybaras, hasLength(3));
    expect(
      capybaras.map((capybara) => capybara.accessories.single['assetKey']),
      containsAll(['top-hat', 'hoodie', 'boots']),
    );
  });

  testWidgets('LeaderboardTab does not render a crown above first place', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();

    await tester.pumpWidget(
      _buildLeaderboard(
        authService: authService,
        backendApiService: _FakeBackendApiService(),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_CrownPainter',
      ),
      findsNothing,
    );
  });

  testWidgets('large step totals stay compact and my dark row is readable', (
    tester,
  ) async {
    final authService = await _createAuthService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.night(),
        home: Scaffold(
          body: LeaderboardTab(
            authService: authService,
            backendApiService: _LargeStepsApi(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('2.4M'), findsOneWidget);
    expect(find.text('1.0M'), findsOneWidget);
    expect(find.text('99.9K'), findsOneWidget);
    expect(find.text('100K'), findsNWidgets(2));
    expect(find.text('999K'), findsOneWidget);
    expect(find.text('2.0M'), findsOneWidget);

    final me = tester.widget<Text>(find.text('@Trail Walker'));
    final myValue = tester.widget<Text>(find.text('2.0M'));
    final colors = AppColors.of(tester.element(find.text('@Trail Walker')));
    expect(me.style?.color, colors.textLight);
    expect(myValue.style?.color, colors.textLight);
  });
}
