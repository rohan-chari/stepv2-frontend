import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'unified_shop_test.dart' show pumpShop, AvailabilityBilling;
import 'billing_components_test.dart' show FakeBilling;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.steptracker/meta_app_events');
  final events = <String>[];
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
    events.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'logEvent') {
            events.add((call.arguments as Map)['event'] as String);
          }
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  testWidgets(
    'Coins shortcut records its destination once per route visit',
    (tester) async {
      addTearDown(tester.view.reset);
      final billing = AvailabilityBilling()
        ..membership = true
        ..packs = true;
      await pumpShop(tester, billing: billing, focus: ShopFocus.coins);
      expect(events, ['shopViewed', 'coinOffersViewed']);
      billing.update(billing.state);
      await tester.pump();
      expect(events, ['shopViewed', 'coinOffersViewed']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'real Shop visit logs once and explicit membership open logs its view',
    (tester) async {
      addTearDown(tester.view.reset);
      final billing = AvailabilityBilling()
        ..membership = true
        ..packs = true;
      await pumpShop(tester, billing: billing);
      expect(events, ['shopViewed']);
      billing.update(billing.state);
      await tester.pump();
      expect(events, ['shopViewed']);
      await tester.ensureVisible(
        find.byKey(const Key('shop-membership-toggle')),
      );
      await tester.tap(find.byKey(const Key('shop-membership-toggle')));
      await tester.pump();
      expect(events, ['shopViewed', 'membershipViewed']);
      final subscribe = find.byKey(const Key('start-bara-trial'));
      await tester.ensureVisible(subscribe);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(subscribe);
      await tester.pump();
      expect(events, ['shopViewed', 'membershipViewed', 'purchaseIntent']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'billing preview never emits acquisition events',
    (tester) async {
      addTearDown(tester.view.reset);
      await pumpShop(tester, billing: FakeBilling());
      await tester.tap(find.byKey(const Key('shop-membership-toggle')));
      await tester.pump();
      expect(events, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'coin purchase intent is separate from a confirmed purchase event',
    (tester) async {
      addTearDown(tester.view.reset);
      final billing = AvailabilityBilling()
        ..membership = true
        ..packs = true;
      await pumpShop(tester, billing: billing);
      final buy = find.byKey(const Key('buy-coins-coins_500'));
      await tester.ensureVisible(buy);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(buy);
      await tester.pump();
      expect(events, ['shopViewed', 'purchaseIntent']);
      expect(billing.purchased?.id, 'coins_500');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
