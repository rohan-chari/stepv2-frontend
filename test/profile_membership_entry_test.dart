import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'billing_components_test.dart' show FakeBilling;
import 'unified_shop_test.dart' show shopAuth, ShopApi;

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets(
    'Profile omits the membership shortcut without an empty action row',
    (tester) async {
      final auth = await shopAuth();
      await tester.pumpWidget(
        BillingScope(
          controller: FakeBilling(),
          child: MaterialApp(
            home: ProfileTab(
              authService: auth,
              displayName: 'Walker',
              onSettingsChanged: () {},
              backendApiService: ShopApi(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('billing-profile-membership')), findsNothing);
      expect(find.text('Membership'), findsNothing);
      expect(find.text('@Walker'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
