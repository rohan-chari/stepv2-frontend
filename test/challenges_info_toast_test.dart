import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/challenges_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/info_toast.dart';

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('showInfoToast uses bulletin board styling', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () =>
                    showInfoToast(context, 'Add some friends first'),
                child: const Text('Show info'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show info'));
    await tester.pump();

    final bannerFinder = find.byWidgetPredicate((widget) {
      if (widget is! Container || widget.decoration is! BoxDecoration) {
        return false;
      }

      final decoration = widget.decoration! as BoxDecoration;
      return decoration.color == AppColors.woodDark;
    });

    expect(bannerFinder, findsOneWidget);

    final banner = tester.widget<Container>(bannerFinder);
    final decoration = banner.decoration! as BoxDecoration;
    final border = decoration.border! as Border;

    expect(border.top.color, AppColors.woodShadow);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'ChallengesTab redirects to Friends with info toast when no friends exist',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      var openFriendsCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChallengesTab(
              authService: authService,
              currentChallenge: {
                'challenge': {
                  'title': 'Summit Sprint',
                  'description': 'Outwalk your friend this week.',
                },
                'instances': const [],
              },
              friendsSteps: const [],
              onChallengeChanged: () {},
              onOpenFriendsTab: () {
                openFriendsCalls += 1;
              },
            ),
          ),
        ),
      );

      expect(find.text('CHALLENGE A FRIEND'), findsOneWidget);

      await tester.tap(find.text('CHALLENGE A FRIEND'));
      await tester.pump();

      expect(openFriendsCalls, 1);
      expect(
        find.text('Add some friends first on the Friends tab.'),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}
