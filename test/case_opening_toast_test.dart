import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';
import 'package:step_tracker/services/backend_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('failed mystery box open shows an error toast, not a SnackBar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CaseOpeningScreen(
                    openMysteryBox: () async =>
                        throw const ApiException('boom'),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // Push the route, run initState's roll, reject the future, slide the toast.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('error-toast-shell')), findsOneWidget);
    expect(find.text('Failed to open mystery box'), findsOneWidget);

    // Flush the auto-dismiss timer so no Timer is left pending at teardown.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
