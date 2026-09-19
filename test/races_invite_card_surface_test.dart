import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '3.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('race invite uses one normal race-card surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = await _auth();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RacesTab(
          authService: auth,
          racesData: const {
            'active': <Map<String, dynamic>>[],
            'completed': <Map<String, dynamic>>[],
            'pending': [
              {
                'id': 'invite-1',
                'name': 'Race Invite',
                'status': 'PENDING',
                'myStatus': 'INVITED',
                'maxDurationDays': 7,
                'participantCount': 6,
                'creator': {'displayName': 'Host'},
              },
            ],
          },
          friendsSteps: const [],
          onRacesChanged: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('race-card-surface-invite-1')), findsOneWidget);
    expect(find.text('Race Invite'), findsOneWidget);

    // The INVITES shelf should not add a second decorated card around the row.
    final surface = find.byKey(const Key('race-card-surface-invite-1'));
    final decoratedAncestors = find.ancestor(
      of: surface,
      matching: find.byType(DecoratedBox),
    );
    // The card's own Container decoration is rendered by its surface; there
    // should be no extra invite-shelf DecoratedSliver wrapper above it.
    expect(
      decoratedAncestors.evaluate().where((element) {
        final widget = element.widget;
        return widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).boxShadow?.isNotEmpty == true;
      }).length,
      lessThanOrEqualTo(1),
    );
  });
}
