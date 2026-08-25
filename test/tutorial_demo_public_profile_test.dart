import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/demo/demo_race_api_service.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:step_tracker/widgets/public_profile_sheet.dart';

class _DemoAuth extends AuthService {
  _DemoAuth() {
    applyBackendUser(const {'id': 'demo-user'});
  }

  @override
  String? get authToken => 'demo-token';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tutorial fake dossier reads and mutates entirely offline', (
    tester,
  ) async {
    final auth = TutorialPreviewAuthService();
    final api = TutorialPreviewBackendApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublicProfilePanel(
            authService: auth,
            backendApiService: api,
            userId: 'tutorial-dana',
            fallbackName: 'Dana Fox',
            initialRelationship: PublicProfileRelationship.incoming,
            friendshipId: 'fs-in-1',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.byKey(const ValueKey('public-profile-action-accept')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('public-profile-action-accept')),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('FRIENDS'), findsOneWidget);
  });

  testWidgets('demo fake dossier reads and mutates entirely offline', (
    tester,
  ) async {
    final engine = DemoRaceEngine(
      myUserId: 'demo-user',
      myDisplayName: 'Demo User',
    );
    final auth = _DemoAuth();
    final api = DemoRaceApiService(engine);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublicProfilePanel(
            authService: auth,
          backendApiService: api,
          userId: 'demo-rival',
          fallbackName: 'Demo Rival',
          initialRelationship: PublicProfileRelationship.none,
        ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.byKey(const ValueKey('public-profile-action-add')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('public-profile-action-add')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('REQUESTED'), findsOneWidget);
  });
}
