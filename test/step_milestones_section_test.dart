import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/step_milestones_section.dart';

String _todayLocalDate() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
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

Widget _wrap(ThemeData theme, AuthService auth, BackendApiService api) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      body: SingleChildScrollView(
        child: StepMilestonesSection(
          authService: auth,
          backendApiService: api,
          initialData: _batch(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the four milestones as discrete cards', (tester) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_wrap(AppThemeData.light(), auth, BackendApiService()));

    // Each tile shows its compact threshold label — four distinct cards.
    expect(find.text('5k'), findsOneWidget);
    expect(find.text('10k'), findsOneWidget);
    expect(find.text('15k'), findsOneWidget);
    expect(find.text('20k'), findsOneWidget);
    // The claimed tile shows a check; the claimable tile shows TAP!.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('TAP!'), findsOneWidget);
  });

  testWidgets('collected color stays green in light mode', (tester) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_wrap(AppThemeData.light(), auth, BackendApiService()));

    final check = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
    // Light: milestoneCollected => success => grassDark(light) 0xFF23783D.
    expect(check.color, const Color(0xFF23783D));
  });

  testWidgets('collected color flips to slate-blue (pillTerra) in dark mode', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_wrap(AppThemeData.night(), auth, BackendApiService()));

    final check = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
    // Dark: milestoneCollected => pillTerra(night) 0xFF527486, NOT the muddy
    // grassDark(night) 0xFF29483B it used before this change.
    expect(check.color, const Color(0xFF527486));
    expect(check.color, isNot(const Color(0xFF29483B)));
  });
}
