import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/main.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/notification_service.dart';

Future<AuthService> _authWith(Object? renameFlag) async {
  SharedPreferences.setMockInitialValues(const {
    'auth_identity_token': 'identity-token',
    'auth_user_identifier': 'provider-user',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Legacy Name',
  });
  final auth = AuthService();
  await auth.restoreSession();
  await auth.syncFromBackendUser({
    'id': 'user-1',
    'displayName': 'Legacy Name',
    'displayNameRequiresRename': renameFlag,
  });
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('literal rename flag gates above an authenticated deep link', (
    tester,
  ) async {
    final auth = await _authWith(true);
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          authService: auth,
          notificationService: NotificationService(
            isIosForTesting: false,
            isAndroidForTesting: false,
          ),
          authenticatedChild: const Text('deep-link destination'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('forced-display-name-rename-gate')),
      findsOneWidget,
    );
    expect(find.text('deep-link destination'), findsNothing);
  });

  testWidgets('missing and malformed rename flags fail open', (tester) async {
    for (final flag in <Object?>[null, 'true', 1]) {
      final auth = await _authWith(flag);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionGate(
            authService: auth,
            notificationService: NotificationService(
              isIosForTesting: false,
              isAndroidForTesting: false,
            ),
            authenticatedChild: const Text('authenticated shell'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('authenticated shell'), findsOneWidget);
      expect(
        find.byKey(const Key('forced-display-name-rename-gate')),
        findsNothing,
      );
    }
  });
}
