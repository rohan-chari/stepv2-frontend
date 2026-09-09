import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/preview/billing_preview_app.dart';
import 'package:step_tracker/preview/preview_billing_controller.dart';
import 'unified_shop_test.dart' show pumpShop;
import 'billing_components_test.dart' show FakeBilling;

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'token',
      'auth_user_identifier': 'apple',
      'auth_session_token': 'session',
      'auth_backend_user_id': 'user',
      'auth_coins': 100,
    });
  });
  testWidgets(
    'shop owns three bottom destinations with no global inventory or preview',
    (tester) async {
      addTearDown(tester.view.reset);
      await pumpShop(tester, billing: FakeBilling());
      final navigation = find.byKey(const Key('shop-bottom-navigation'));
      expect(navigation, findsOneWidget);
      for (final name in ['FEATURED', 'POWERUPS', 'CHARACTERS']) {
        expect(
          find.descendant(of: navigation, matching: find.text(name)),
          findsOneWidget,
        );
      }
      expect(find.text('ACCESSORIES'), findsNothing);
      expect(find.text('INVENTORY'), findsNothing);
      expect(find.byKey(const Key('shop-character-preview')), findsNothing);
      expect(tester.getTopLeft(navigation).dy, greaterThan(650));
      await tester.tap(find.text('POWERUPS'));
      await tester.pump();
      expect(find.text('BUY'), findsOneWidget);
      expect(find.text('OWNED'), findsOneWidget);
      expect(find.text('FEATURED'), findsOneWidget);
    },
  );
  testWidgets(
    'offline Shop pushes above host navigation and Back restores host',
    (tester) async {
      final controller = PreviewBillingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(BillingPreviewApp(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('preview-nav-shop')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('shop-bottom-navigation')), findsOneWidget);
      expect(find.byKey(const Key('preview-nav-shop')), findsNothing);
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('preview-nav-shop')), findsOneWidget);
      expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
