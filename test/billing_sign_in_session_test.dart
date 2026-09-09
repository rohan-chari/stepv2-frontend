import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/main.dart';
import 'package:step_tracker/screens/display_name_screen.dart';
import 'package:step_tracker/services/live_billing_controller.dart';
import 'package:step_tracker/services/notification_service.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'package:step_tracker/widgets/coin_pack_offers.dart';

import 'live_billing_test.dart' show TestAuth, TestApi, TestStore;

class _SignedOutAuth extends TestAuth {
  _SignedOutAuth() {
    id = '';
  }
  @override
  String? get authToken => id.isEmpty ? null : 'token-$id';
  @override
  bool get onboardingV2Enabled => false;
  @override
  Future<bool> restoreSession() async => false;
  @override
  Future<bool> signInWithApple() async {
    id = 'a';
    notifyListeners();
    return true;
  }
}

void main() {
  testWidgets('fresh sign in makes coin packs available without restarting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = _SignedOutAuth();
    final api = TestApi();
    final controller = LiveBillingController(
      auth: auth,
      api: api,
      store: TestStore(),
      platform: 'ios',
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      BillingScope(
        controller: controller,
        child: MaterialApp(
          navigatorKey: navigator,
          home: SessionGate(
            authService: auth,
            notificationService: NotificationService(
              isIosForTesting: false,
              isAndroidForTesting: false,
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.isAvailable, isFalse);
    await tester.tap(find.text('Sign in with Apple'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(DisplayNameScreen), findsOneWidget);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: CoinPackOffers()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('COINS'), findsWidgets);
    expect(find.byKey(const Key('buy-coins-coins_500')), findsOneWidget);
    expect(api.syncTokens, contains('token-a'));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    auth.dispose();
  });
}
