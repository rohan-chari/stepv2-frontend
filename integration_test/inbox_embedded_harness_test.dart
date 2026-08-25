import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:step_tracker/screens/inbox_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _HarnessApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchInboxAlerts({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => {
    'alerts': [
      {
        'id': 'harness-alert',
        'type': 'RACE_COMPLETED',
        'title': 'Trail complete',
        'body': 'Your race is ready to review.',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'readAt': null,
        'destination': {'route': 'races'},
      },
    ],
    'nextCursor': null,
    'unreadCount': 1,
  };

  @override
  Future<Map<String, dynamic>> fetchFeedbackThreads({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => const {'threads': <Map<String, dynamic>>[], 'nextCursor': null};
}

class _HarnessAuth extends AuthService {
  @override
  String? get authToken => 'integration-harness-token';

  @override
  String? get userId => 'integration-harness-user';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('embedded Inbox harness renders compact dispatch board', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InboxScreen(
          authService: _HarnessAuth(),
          backendApiService: _HarnessApi(),
          hostMode: InboxHostMode.embedded,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('INBOX'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inbox-row-alert-harness-alert')),
      findsOneWidget,
    );
    expect(find.text('The things that need your attention.'), findsOneWidget);
  });
}
