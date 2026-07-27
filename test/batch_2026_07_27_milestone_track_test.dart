import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/step_milestones_section.dart';

/// Batch 2026-07-27, item 15 — "Today's coins" goes back to the chronological
/// connected track (four nodes joined by three connectors) instead of the 2x2
/// grid of parchment tiles introduced in a4e4153. The claimed state keeps the
/// `milestoneCollected` token the dark-mode batch introduced; reverting it to
/// `success` would re-break night mode.

String _todayLocalDate() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Map<String, dynamic> _batch() => {
  'currentSteps': 12000,
  'totalCoinsClaimed': 20,
  'localDate': _todayLocalDate(),
  'milestones': const [
    {'threshold': 5000, 'coins': 20, 'claimed': true, 'claimable': false},
    {'threshold': 10000, 'coins': 30, 'claimed': false, 'claimable': true},
    {'threshold': 15000, 'coins': 30, 'claimed': false, 'claimable': false},
    {'threshold': 20000, 'coins': 30, 'claimed': false, 'claimable': false},
  ],
};

Future<void> _pump(WidgetTester tester, ThemeData theme) async {
  await tester.binding.setSurfaceSize(const Size(800, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: StepMilestonesSection(
            authService: auth,
            backendApiService: BackendApiService(),
            initialData: _batch(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders four nodes joined by three connectors', (tester) async {
    await _pump(tester, AppThemeData.light());

    for (final t in [5000, 10000, 15000, 20000]) {
      expect(
        find.byKey(Key('milestone-node-$t')),
        findsOneWidget,
        reason: 'node for $t',
      );
    }
    for (var i = 0; i < 3; i++) {
      expect(
        find.byKey(Key('milestone-connector-$i')),
        findsOneWidget,
        reason: 'connector $i',
      );
    }
    // The grid is gone: nodes sit on one horizontal run, all at the same y.
    final tops = [5000, 10000, 15000, 20000]
        .map((t) => tester.getTopLeft(find.byKey(Key('milestone-node-$t'))).dy)
        .toSet();
    expect(tops.length, 1, reason: 'all four nodes share one row');
  });

  testWidgets('nodes are circles, in chronological left-to-right order', (
    tester,
  ) async {
    await _pump(tester, AppThemeData.light());

    final xs = [5000, 10000, 15000, 20000]
        .map((t) => tester.getCenter(find.byKey(Key('milestone-node-$t'))).dx)
        .toList();
    expect(xs, orderedEquals(<double>[...xs]..sort()));

    final circle = tester.widget<Container>(
      find.byKey(const Key('milestone-node-5000')),
    );
    expect((circle.decoration as BoxDecoration).shape, BoxShape.circle);
  });

  testWidgets('the claimable node still prompts with TAP!', (tester) async {
    await _pump(tester, AppThemeData.light());
    expect(find.text('TAP!'), findsOneWidget);
    expect(find.text('10k'), findsOneWidget);
  });

  testWidgets('a claimed node uses milestoneCollected, never success', (
    tester,
  ) async {
    await _pump(tester, AppThemeData.night());

    final check = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
    expect(check.color, AppPalette.night.milestoneCollected);
    expect(check.color, isNot(AppPalette.night.success));

    // The filled connector behind a claimed node follows the same token.
    final connector = tester.widget<Container>(
      find.byKey(const Key('milestone-connector-0')),
    );
    expect(connector.color, AppPalette.night.milestoneCollected);
    expect(connector.color, isNot(AppPalette.night.success));
  });
}
