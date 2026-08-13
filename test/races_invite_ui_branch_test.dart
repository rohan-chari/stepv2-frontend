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

Map<String, dynamic> _races() => {
  'active': const <Map<String, dynamic>>[],
  'completed': const <Map<String, dynamic>>[],
  'pending': [
    {
      'id': 'invite',
      'name': 'Hidden Invitation',
      'status': 'PENDING',
      'myStatus': 'INVITED',
      'creator': {'displayName': 'Host'},
    },
    {
      'id': 'waiting',
      'name': 'Waiting Race',
      'status': 'PENDING',
      'myStatus': 'ACCEPTED',
      'creator': {'displayName': 'Host'},
    },
  ],
};

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RacesTab(
        authService: await _auth(),
        racesData: _races(),
        friendsSteps: const [],
        onRacesChanged: () async {},
      ),
    ),
  );
  await tester.pump();
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

  testWidgets('Races tab always retains its inline invitations', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('ACTIVE'), findsWidgets);
    expect(find.text('PENDING'), findsWidgets);
    expect(find.text('INVITES'), findsWidgets);
    expect(find.byKey(const Key('invites-strip-header')), findsOneWidget);
    expect(find.text('Hidden Invitation'), findsOneWidget);
  });

  testWidgets('inline invitation treatment has no feature-flag branch', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('INVITES'), findsWidgets);
    expect(find.text('PENDING'), findsWidgets);
    expect(find.byKey(const Key('invites-strip-header')), findsOneWidget);
    expect(find.text('Hidden Invitation'), findsOneWidget);
  });

  testWidgets('malformed list rows are skipped instead of throwing', (
    tester,
  ) async {
    final data = _races();
    data['active'] = [
      null,
      'bad',
      {8: 'bad key'},
    ];
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RacesTab(
          authService: await _auth(),
          racesData: data,
          friendsSteps: const [],
          onRacesChanged: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
