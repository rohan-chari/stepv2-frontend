import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/public_profile_sheet.dart';

class _ProfileApi extends BackendApiService {
  int profileReads = 0;
  int friendsReads = 0;
  int sends = 0;
  bool requestSent = false;

  @override
  Future<Map<String, dynamic>> fetchPublicProfile({
    required String identityToken,
    required String userId,
  }) async {
    profileReads++;
    return const {
      'user': {'id': 'target-1', 'displayName': 'Trail Runner'},
      'stats': {
        'racePodiums': {'first': 2, 'second': 1, 'third': 3},
        'avgStepsPerDay': 4567,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    friendsReads++;
    return {
      'friends': <Map<String, dynamic>>[],
      'pending': {
        'incoming': <Map<String, dynamic>>[],
        'outgoing': requestSent
            ? [
                {
                  'friendshipId': 'friendship-1',
                  'user': {'id': 'target-1'},
                },
              ]
            : <Map<String, dynamic>>[],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> sendFriendRequest({
    required String identityToken,
    required String addresseeId,
  }) async {
    sends++;
    requestSent = true;
    return const {
      'friendship': {'id': 'friendship-1', 'status': 'PENDING'},
    };
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_session_token': 'token',
    'auth_backend_user_id': 'viewer-1',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens the direct dossier and renders defensive profile data', (
    tester,
  ) async {
    final auth = await _auth();
    final api = _ProfileApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPublicProfileSheet(
                context: context,
                authService: auth,
                backendApiService: api,
                userId: 'target-1',
                fallbackName: 'Fallback',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('public-profile-sheet')), findsOneWidget);
    expect(find.text('@Trail Runner'), findsOneWidget);
    expect(find.text('4567'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('public-profile-action-add')),
      findsOneWidget,
    );
    expect(api.profileReads, 1);
    expect(api.friendsReads, 1);
  });

  testWidgets('add transitions in place and preserves returned friendship id', (
    tester,
  ) async {
    final auth = await _auth();
    final api = _ProfileApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showPublicProfileSheet(
              context: context,
              authService: auth,
              backendApiService: api,
              userId: 'target-1',
              fallbackName: 'Target',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const ValueKey('public-profile-action-add')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(api.sends, 1);
    expect(find.text('REQUESTED'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('public-profile-action-cancel')),
      findsOneWidget,
    );
  });
}
