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
  testWidgets('shop has three ordered sections without bottom categories', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpShop(tester, billing: FakeBilling());
    expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
    final featured = find.byKey(const Key('shop-section-featured'));
    final powerups = find.byKey(const Key('shop-section-powerups'));
    final characters = find.byKey(const Key('shop-section-characters'));
    expect(
      tester.getTopLeft(featured).dy,
      lessThan(tester.getTopLeft(powerups).dy),
    );
    expect(
      tester.getTopLeft(powerups).dy,
      lessThan(tester.getTopLeft(characters).dy),
    );
    expect(find.text('ACCESSORIES'), findsNothing);
    expect(find.text('INVENTORY'), findsNothing);
    expect(find.byKey(const Key('shop-character-preview')), findsNothing);
    await tester.ensureVisible(powerups);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('BUY'), findsOneWidget);
    expect(find.text('OWNED'), findsOneWidget);
    expect(find.text('Featured'), findsOneWidget);
  });
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
      expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
      expect(find.byKey(const Key('shop-section-featured')), findsOneWidget);
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
