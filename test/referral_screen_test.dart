import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/referral_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

enum _Mode { withReferrals, empty, error }

class _FakeReferralApi extends BackendApiService {
  _FakeReferralApi(this.mode);
  final _Mode mode;

  @override
  Future<Map<String, dynamic>> fetchReferralStatus({
    required String identityToken,
  }) async {
    if (mode == _Mode.error) {
      throw const ApiException('Not found', statusCode: 404);
    }
    if (mode == _Mode.empty) {
      return {
        'code': 'BARA-7F3K',
        'url': 'https://steptracker-api.org/r/BARA-7F3K',
        'referredCount': 0,
        'completedCount': 0,
        'coinsEarned': 0,
        'friends': const [],
      };
    }
    return {
      'code': 'BARA-7F3K',
      'url': 'https://steptracker-api.org/r/BARA-7F3K',
      'referredCount': 2,
      'completedCount': 1,
      'coinsEarned': 300,
      'friends': const [
        {
          'displayName': 'Alice',
          'profilePhotoUrl': null,
          'stage': 'completed',
        },
        {'displayName': 'Bob', 'profilePhotoUrl': null, 'stage': 'joined'},
      ],
    };
  }
}

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

Widget _build(AuthService auth, BackendApiService api) {
  return MaterialApp(
    home: ReferralScreen(authService: auth, backendApiService: api),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders dashboard stats, code, and friend stage badges', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeReferralApi(_Mode.withReferrals)));
    await tester.pump(); // resolve the fetch future

    expect(find.text('INVITE FRIENDS'), findsOneWidget);
    expect(find.text('Your code: BARA-7F3K'), findsOneWidget);
    expect(find.text('SHARE YOUR INVITE'), findsOneWidget);
    // Stats: 2 invited, 1 completed, 300 earned.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    // Friends + their stage badges.
    expect(find.text('@Alice'), findsOneWidget);
    expect(find.text('@Bob'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('JOINED'), findsOneWidget);
  });

  testWidgets('empty state invites the user to share', (tester) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeReferralApi(_Mode.empty)));
    await tester.pump();

    expect(find.text('SHARE YOUR INVITE'), findsOneWidget);
    expect(
      find.textContaining('No invites yet'),
      findsOneWidget,
    );
  });

  testWidgets('older backend (404) shows a friendly error with retry', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeReferralApi(_Mode.error)));
    await tester.pump();

    expect(find.textContaining("Couldn't load"), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);
  });
}
