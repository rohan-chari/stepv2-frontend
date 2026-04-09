import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

Future<AuthService> _createAuthService({
  String? profilePhotoUrl,
  String? profilePhotoPromptDismissedAt,
}) async {
  final initialValues = <String, Object>{
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_step_goal': 8000,
    ...?profilePhotoUrl == null
        ? null
        : {'auth_profile_photo_url': profilePhotoUrl},
    ...?profilePhotoPromptDismissedAt == null
        ? null
        : {
            'auth_profile_photo_prompt_dismissed_at':
                profilePhotoPromptDismissedAt,
          },
  };
  SharedPreferences.setMockInitialValues(initialValues);

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Widget _buildHome(
  AuthService authService, {
  Future<void> Function()? onAddProfilePhoto,
  Future<bool> Function()? onDismissProfilePhotoPrompt,
}) {
  return MaterialApp(
    home: Scaffold(
      body: HomeTab(
        stepData: StepData(steps: 2400, date: DateTime(2026, 4, 8)),
        isLoading: false,
        error: null,
        stepGoal: 8000,
        healthAuthorized: true,
        notificationsState: true,
        displayName: 'Trail Walker',
        authService: authService,
        onRefresh: () async {},
        onEnableHealth: () {},
        onEnableNotifications: () {},
        onSetStepGoal: () {},
        onDisplayNameChanged: () {},
        currentChallenge: null,
        friendsSteps: const [],
        onChallengeChanged: () {},
        onAddProfilePhoto: onAddProfilePhoto,
        onDismissProfilePhotoPrompt: onDismissProfilePhotoPrompt,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'HomeTab shows the profile photo prompt when display name exists and no photo is set',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(_buildHome(authService));

      expect(find.text('ADD A PROFILE PHOTO?'), findsOneWidget);
      expect(find.text('ADD PHOTO'), findsOneWidget);
      expect(find.text('NO THANKS'), findsOneWidget);
      expect(
        find.text(
          'Make it easier for friends to spot you in races, challenges, and leaderboards.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('HomeTab hides the profile photo prompt after dismissal', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService(
      profilePhotoPromptDismissedAt: '2026-04-08T12:00:00.000Z',
    );

    await tester.pumpWidget(_buildHome(authService));

    expect(find.text('ADD A PROFILE PHOTO?'), findsNothing);
    expect(find.text('ADD PHOTO'), findsNothing);
    expect(find.text('NO THANKS'), findsNothing);
  });

  testWidgets('HomeTab wires add photo and no thanks actions', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    var addCalls = 0;
    var dismissCalls = 0;

    await tester.pumpWidget(
      _buildHome(
        authService,
        onAddProfilePhoto: () async {
          addCalls += 1;
        },
        onDismissProfilePhotoPrompt: () async {
          dismissCalls += 1;
          return true;
        },
      ),
    );

    await tester.tap(find.text('ADD PHOTO'));
    await tester.pump();
    await tester.tap(find.text('NO THANKS'));
    await tester.pump();

    expect(addCalls, 1);
    expect(dismissCalls, 1);
  });

  testWidgets(
    'HomeTab keeps the profile photo prompt confirmation in place for 3 seconds after dismissal',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(
        _buildHome(
          authService,
          onDismissProfilePhotoPrompt: () async {
            await authService.updateProfilePhotoPromptDismissedAt(
              '2026-04-08T12:00:00.000Z',
            );
            return true;
          },
        ),
      );

      await tester.tap(find.text('NO THANKS'));
      await tester.pump();

      expect(find.text('ADD A PROFILE PHOTO?'), findsNothing);
      expect(find.text('ADD PHOTO'), findsNothing);
      expect(find.text('NO THANKS'), findsNothing);
      expect(
        find.byKey(const Key('profile-photo-dismissed-confirmation')),
        findsOneWidget,
      );
      expect(find.text('You can add one anytime in Profile.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('You can add one anytime in Profile.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('You can add one anytime in Profile.'), findsNothing);
      expect(
        find.byKey(const Key('profile-photo-dismissed-confirmation')),
        findsNothing,
      );
    },
  );
}
