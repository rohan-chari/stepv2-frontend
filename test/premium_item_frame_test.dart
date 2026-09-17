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

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'centered Bara Gold treatment keeps the label above the frame in ${themeMode == ThemeMode.dark ? 'dark' : 'light'} mode',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppThemeData.light(),
            darkTheme: AppThemeData.night(),
            themeMode: themeMode,
            home: Scaffold(
              body: PremiumItemFrame(
                centeredLabel: true,
                frameKey: const Key('premium-frame'),
                labelKey: const Key('premium-label'),
                child: const SizedBox(width: 120, height: 80),
              ),
            ),
          ),
        );

        final frame = find.byKey(const Key('premium-frame'));
        final label = find.byKey(const Key('premium-label'));
        final decoration =
            tester.widget<DecoratedBox>(frame).decoration as BoxDecoration;
        final border = decoration.border! as Border;
        expect(border.top.width, 2);
        expect(border.top.color, isNotNull);
        expect(decoration.borderRadius, BorderRadius.circular(14));
        expect(
          tester.getCenter(label).dx,
          closeTo(tester.getCenter(frame).dx, .01),
        );
        expect(
          tester.getRect(label).bottom,
          lessThanOrEqualTo(tester.getTopLeft(frame).dy + 2),
        );
        expect(find.text('Bara Gold'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
