import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/arcade_page.dart';

class _FakeShopApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    return const {'coins': 420, 'items': <Map<String, dynamic>>[]};
  }
}

class _FakeFriendsApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    return const {
      'friends': <Map<String, dynamic>>[],
      'pending': {
        'incoming': <Map<String, dynamic>>[],
        'outgoing': <Map<String, dynamic>>[],
      },
    };
  }
}

class _EmptyPublicRacesApi extends BackendApiService {
  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async {
    return const [];
  }
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 420,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _openRoute(
  WidgetTester tester, {
  required WidgetBuilder builder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: builder)),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('OPEN'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ShopTab pushed route has material text chrome and a back button',
    (WidgetTester tester) async {
      final authService = await _authService();

      await _openRoute(
        tester,
        builder: (_) => ShopTab(
          authService: authService,
          backendApiService: _FakeShopApi(),
        ),
      );

      expect(
        find.ancestor(of: find.text('SHOP'), matching: find.byType(Material)),
        findsWidgets,
      );
      expect(
        DefaultTextStyle.of(tester.element(find.text('SHOP'))).style.decoration,
        isNot(TextDecoration.underline),
      );
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('SHOP'), findsNothing);
    },
  );

  testWidgets(
    'FriendsTab pushed route has material text chrome and a back button',
    (WidgetTester tester) async {
      final authService = await _authService();

      await _openRoute(
        tester,
        builder: (_) => FriendsTab(
          authService: authService,
          onFriendsChanged: () {},
          backendApiService: _FakeFriendsApi(),
        ),
      );

      expect(
        find.ancestor(
          of: find.text('FRIENDS'),
          matching: find.byType(Material),
        ),
        findsWidgets,
      );
      expect(
        DefaultTextStyle.of(
          tester.element(find.text('FRIENDS').first),
        ).style.decoration,
        isNot(TextDecoration.underline),
      );
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('FRIENDS'), findsNothing);
    },
  );

  testWidgets('PublicRacesScreen uses the compact light route header', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();

    await _openRoute(
      tester,
      builder: (_) => PublicRacesScreen(
        authService: authService,
        backendApiService: _EmptyPublicRacesApi(),
      ),
    );

    final background = tester.widget<ArcadePageBackground>(
      find.byType(ArcadePageBackground),
    );
    expect(background.headerColor, AppColors.roofLight);
    expect(background.headerHeight, 56);
  });
}
