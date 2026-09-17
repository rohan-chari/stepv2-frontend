import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/premium_item_frame.dart';

void main() {
  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'premium item frame keeps the Gold marker readable in ${themeMode == ThemeMode.dark ? 'dark' : 'light'} mode',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppThemeData.light(),
            darkTheme: AppThemeData.night(),
            themeMode: themeMode,
            home: const Scaffold(
              body: PremiumItemFrame(child: SizedBox(width: 120, height: 80)),
            ),
          ),
        );

        expect(find.text('Bara Gold'), findsOneWidget);
        expect(find.byType(PremiumItemFrame), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
