import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FriendsApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async => const {
    'friends': [
      {
        'id': 'runner-42',
        'displayName': 'Maya Chen',
        'profilePhotoUrl': null,
        'friendshipId': 'friendship-42',
      },
    ],
    'pending': {'incoming': [], 'outgoing': []},
  };

  @override
  Future<Map<String, dynamic>> fetchPublicProfile({
    required String identityToken,
    required String userId,
  }) async => const {
    'contract': 'public-profile-v1',
    'user': {
      'id': 'runner-42',
      'displayName': 'Maya Chen',
      'profilePhotoUrl': null,
      'equippedAnimal': null,
      'equippedAccessories': <Map<String, dynamic>>[],
    },
    'stats': {
      'racePodiums': {'first': 1, 'second': 0, 'third': 0},
      'avgStepsPerDay': 5000,
    },
  };
}

class _Auth extends AuthService {
  @override
  String? get authToken => 'token';
}

void main() {
  testWidgets('real FriendsTab identity opens the shared dossier',
      (tester) async {
    final auth = _Auth()..applyBackendUser(const {
      'id': 'viewer-1',
      'displayName': 'Rohan',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendsTab(
            authService: auth,
            backendApiService: _FriendsApi(),
            onFriendsChanged: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('friends-profile-runner-42')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('friends-profile-runner-42')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Maya'), findsWidgets);
    expect(find.text('AVG STEPS / DAY'), findsOneWidget);
  });
}
