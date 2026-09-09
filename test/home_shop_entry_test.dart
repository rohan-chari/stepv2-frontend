import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

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
  for (final preview in [false, true]) {
    testWidgets('Home has Shop and no membership button (tutorial: $preview)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTab(
              stepData: StepData(steps: 2400, date: DateTime(2026, 9, 9)),
              isLoading: false,
              error: null,
              healthAuthorized: true,
              notificationsState: true,
              displayName: 'Walker',
              authService: AuthService(),
              backendApiService: BackendApiService(),
              onRefresh: () async {},
              onEnableHealth: () {},
              onEnableNotifications: () {},
              onDisplayNameChanged: () {},
              friendsSteps: const [],
              isTutorialPreview: preview,
              onOpenShop: () => opens++,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Membership'), findsNothing);
      expect(find.textContaining('Bara+'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('home-shop-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('home-shop-button')));
      expect(opens, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
