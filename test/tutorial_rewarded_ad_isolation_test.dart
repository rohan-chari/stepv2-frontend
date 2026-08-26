import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/screens/get_coins_screen.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:step_tracker/tutorial/tutorial_real_screens.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart';

class _CountingPreviewApi extends TutorialPreviewBackendApiService {
  int getCoinsStatusCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchGetCoinsStatus({
    required String identityToken,
    required String localDate,
  }) async {
    getCoinsStatusCalls++;
    return const {'claimedToday': false};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'tutorial real Home opens only the offline unsupported Get Coins path',
    (tester) async {
      final auth = TutorialPreviewAuthService();
      addTearDown(auth.dispose);
      final api = _CountingPreviewApi();

      await tester.pumpWidget(
        MaterialApp(
          home: TutorialRealHost(
            page: TutorialMockPage.home,
            keys: const {},
            authService: auth,
            api: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(GetCoinsScreen), findsOneWidget);
      expect(api.getCoinsStatusCalls, 1);
      expect(find.textContaining('WATCH AD'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
