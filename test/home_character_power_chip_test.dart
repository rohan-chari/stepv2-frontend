import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/character_power_chip.dart';

// Spec §9 / test 17 — a collapsed, tappable notice of the equipped character's
// power, shown to EVERY user (no CHARACTER cosmetic == capybara, D6) but ONLY
// while the server says character powers are on. `characterPowersEnabled` is a
// kill switch, so an absent or false field must hide the chip on its own.

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

Future<void> _pumpHome(
  WidgetTester tester, {
  required bool? characterPowersEnabled,
  String? equippedAnimal,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HomeTab(
          key: UniqueKey(),
          stepData: StepData(steps: 2400, date: DateTime(2026, 6, 5)),
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
          equippedAnimal: equippedAnimal,
          characterPowersEnabled: characterPowersEnabled ?? false,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('kill-switch gating on the home tab', () {
    testWidgets('hidden when characterPowersEnabled is absent/false',
        (tester) async {
      await _pumpHome(tester, characterPowersEnabled: null);
      expect(find.byType(CharacterPowerChip), findsNothing);

      await _pumpHome(tester, characterPowersEnabled: false);
      expect(find.byType(CharacterPowerChip), findsNothing);
    });

    testWidgets('shown, collapsed, when the server says powers are on',
        (tester) async {
      await _pumpHome(tester, characterPowersEnabled: true);
      expect(find.byType(CharacterPowerChip), findsOneWidget);
      // D6: a user with no CHARACTER cosmetic is a capybara, and still gets it.
      expect(find.text('HERD BONUS'), findsOneWidget);
      // Collapsed by default — the detail line is not rendered yet.
      expect(find.textContaining('capybara racing'), findsNothing);
    });
  });

  group('the chip itself', () {
    Future<void> pumpChip(WidgetTester tester, String? animal) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: CharacterPowerChip(animal: animal)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('null animal falls back to the capybara power', (tester) async {
      await pumpChip(tester, null);
      expect(find.text('HERD BONUS'), findsOneWidget);
    });

    testWidgets('an unknown animal falls back to the capybara power',
        (tester) async {
      await pumpChip(tester, 'axolotl');
      expect(find.text('HERD BONUS'), findsOneWidget);
    });

    testWidgets('corgi and turtle name their own powers', (tester) async {
      await pumpChip(tester, 'corgi_puppy');
      expect(find.text('ZOOMIES'), findsOneWidget);

      await pumpChip(tester, 'turtle');
      expect(find.text('SHELL'), findsOneWidget);
    });

    testWidgets('tapping expands the detail in place, tapping again collapses',
        (tester) async {
      await pumpChip(tester, null);
      expect(find.textContaining('capybara racing'), findsNothing);

      await tester.tap(find.byType(CharacterPowerChip));
      await tester.pumpAndSettle();
      expect(find.textContaining('capybara racing'), findsOneWidget);
      // Expanded in place — not a dialog/route.
      expect(find.byType(Dialog), findsNothing);

      await tester.tap(find.byType(CharacterPowerChip));
      await tester.pumpAndSettle();
      expect(find.textContaining('capybara racing'), findsNothing);
    });

    testWidgets('the copy stays qualitative — no tunable constants',
        (tester) async {
      await pumpChip(tester, null);
      await tester.tap(find.byType(CharacterPowerChip));
      await tester.pumpAndSettle();
      final detail = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      // The herd-bonus numbers come from env-tunable balance config; restating
      // them here would render stale the moment they're retuned.
      expect(RegExp(r'\d').hasMatch(detail), isFalse);
    });
  });
}
