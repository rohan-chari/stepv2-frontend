import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/preview/preview_billing_api.dart';
import 'package:step_tracker/preview/preview_billing_controller.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'support/shop_navigation.dart';

void main() {
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    ),
  );
  testWidgets(
    'offline wardrobe examples retain earned and unavailable ownership through reset',
    (tester) async {
      final controller = PreviewBillingController();
      addTearDown(controller.dispose);
      final api = PreviewBillingApi(controller)..seedWardrobeExamples();
      await tester.pumpWidget(
        BillingScope.disabled(
          child: MaterialApp(
            home: ShopTab(authService: controller.auth, backendApiService: api),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await selectShopCategory(tester, 'ACCESSORIES');
      await tester.scrollUntilVisible(
        find.text('Other owned items'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Other owned items'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('wardrobe-item-baseball_cap')),
        -180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('wardrobe-item-baseball_cap')));
      await tester.pump();
      expect(find.text('Trying on'), findsNothing);
      expect(find.textContaining('Buy ·'), findsNothing);
      expect(find.text('Unavailable'), findsWidgets);
      await tester.ensureVisible(
        find.byKey(const Key('wardrobe-item-sunglasses')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('wardrobe-item-sunglasses')));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Reset'),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(find.text('Saved outfit'), findsOneWidget);
      expect(
        controller.ownedCosmetics,
        containsAll(['baseball_cap', 'sunglasses', 'gold_chain']),
      );
      expect(
        tester
            .widget<PillButton>(
              find.ancestor(
                of: find.text('Save outfit'),
                matching: find.byType(PillButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
