import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FriendsApi extends BackendApiService {
  _FriendsApi({required this.results, this.legacyOnFirstSearch = false});

  final List<Map<String, dynamic>> results;
  final bool legacyOnFirstSearch;
  final List<String> queries = [];

  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async => {
    'friends': const <Map<String, dynamic>>[],
    'pending': {
      'incoming': const <Map<String, dynamic>>[],
      'outgoing': const <Map<String, dynamic>>[],
    },
  };

  @override
  Future<List<Map<String, dynamic>>> searchUsers({
    required String identityToken,
    required String query,
  }) async {
    queries.add(query);
    if (legacyOnFirstSearch && queries.length == 1) {
      throw const LegacyFriendSearchRequired();
    }
    return results;
  }
}

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

Future<void> _pump(WidgetTester tester, _FriendsApi api) async {
  await tester.binding.setSurfaceSize(const Size(430, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: FriendsTab(
        authService: await _auth(),
        backendApiService: api,
        onFriendsChanged: () {},
      ),
    ),
  );
  await tester.pump();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 301));
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

  testWidgets('new search rows show real name above race handle defensively', (
    tester,
  ) async {
    final api = _FriendsApi(
      results: const [
        {
          'id': 'real-and-handle',
          'discoverableName': 'Nathan Chari',
          'displayName': 'NathanRuns',
          'profilePhotoUrl': null,
        },
        {'id': 'handle-only', 'displayName': 'CapySprint'},
        {'id': 'real-only', 'discoverableName': 'Maya Chen'},
        {'id': 404, 'displayName': 9, 'discoverableName': null},
      ],
    );
    await _pump(tester, api);

    expect(
      find.widgetWithText(TextField, 'Search names or race names'),
      findsOneWidget,
    );
    await _search(tester, 'Nathan');

    expect(find.text('Nathan Chari'), findsOneWidget);
    expect(find.text('@NathanRuns'), findsOneWidget);
    expect(find.text('@CapySprint'), findsOneWidget);
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.text('Runner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('404 clears the private query and requires a new legacy query', (
    tester,
  ) async {
    final api = _FriendsApi(
      legacyOnFirstSearch: true,
      results: const [
        {'id': 'legacy', 'displayName': 'RaceHandle'},
      ],
    );
    await _pump(tester, api);

    await _search(tester, 'Private Name');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
    expect(find.widgetWithText(TextField, 'Search race names'), findsOneWidget);
    expect(api.queries, ['Private Name']);

    await _search(tester, 'RaceHandle');
    expect(api.queries, ['Private Name', 'RaceHandle']);
    expect(find.text('@RaceHandle'), findsOneWidget);
  });
}
