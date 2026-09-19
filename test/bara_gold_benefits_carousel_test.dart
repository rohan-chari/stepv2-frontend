import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/bara_gold_benefits.dart';
import 'package:step_tracker/widgets/bara_gold_benefits_carousel.dart';

Future<void> _pumpCarousel(
  WidgetTester tester, {
  bool reduceMotion = false,
  bool accessibleNavigation = false,
  bool enabled = true,
  double width = 358,
  double scale = 1,
  bool night = false,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(extensions: [night ? AppPalette.night : AppPalette.light]),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduceMotion,
            accessibleNavigation: accessibleNavigation,
          ),
          child: TickerMode(
            enabled: enabled,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: Builder(
                    builder: (context) => SizedBox(
                      height: BaraGoldBenefitsCarousel.rowHeight(context, width),
                      child: const BaraGoldBenefitsCarousel(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder get _pager => find.byKey(const Key('bara-gold-benefits-pager'));
Finder _visible(String text) => find.text(text).hitTestable();

Future<void> _advance(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one benefit at a time, auto advances and wraps seamlessly', (
    tester,
  ) async {
    await _pumpCarousel(tester);
    for (var index = 0; index < 9; index++) {
      final benefit = BaraGoldBenefit.values[index % 4];
      expect(_visible(benefit.title), findsOneWidget);
      for (final other in BaraGoldBenefit.values.where((item) => item != benefit)) {
        expect(_visible(other.title), findsNothing);
      }
      await _advance(tester);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual swipe wraps and resets the reading interval', (
    tester,
  ) async {
    await _pumpCarousel(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.drag(_pager, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(_visible('Exclusive characters'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(_visible('Exclusive characters'), findsOneWidget);
    await tester.drag(_pager, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(_visible('Ad-free experience'), findsOneWidget);
    await tester.drag(_pager, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(_visible('Free rerolls'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final setting in ['motion', 'accessibility', 'ticker']) {
    testWidgets('$setting disables autoplay without hiding benefits', (
      tester,
    ) async {
      await _pumpCarousel(
        tester,
        reduceMotion: setting == 'motion',
        accessibleNavigation: setting == 'accessibility',
        enabled: setting != 'ticker',
      );
      await tester.pump(const Duration(seconds: 12));
      expect(_visible('Ad-free experience'), findsOneWidget);
      // A muted TickerMode intentionally freezes ballistic animations too.
      // The motion/accessibility settings still permit an explicit swipe.
      if (setting != 'ticker') {
        await tester.drag(_pager, const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(_visible('Exclusive characters'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('backgrounding pauses autoplay and foregrounding resumes it', (
    tester,
  ) async {
    await _pumpCarousel(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 12));
    expect(_visible('Ad-free experience'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _advance(tester);
    expect(_visible('Exclusive characters'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opening a modal pauses autoplay until it is dismissed', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pumpCarousel(tester, navigatorKey: navigatorKey);
    showModalBottomSheet<void>(
      context: tester.element(_pager),
      builder: (_) => const SizedBox(height: 100, child: Text('Membership')),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 12));
    final pager = tester.widget<PageView>(_pager);
    expect(pager.controller!.page, 1);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await _advance(tester);
    expect(_visible('Exclusive characters'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final night in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'readable single row at ${scale}x in ${night ? 'night' : 'day'}',
        (tester) async {
          await _pumpCarousel(
            tester,
            reduceMotion: true,
            width: 268,
            scale: scale,
            night: night,
          );
          final panel = find.byKey(const Key('bara-gold-benefits'));
          final height = tester.getSize(panel).height;
          expect(height, greaterThanOrEqualTo(56));
          for (final benefit in BaraGoldBenefit.values) {
            final title = _visible(benefit.title);
            final detail = _visible(benefit.teaser);
            expect(title, findsOneWidget);
            expect(detail, findsOneWidget);
            final panelRect = tester.getRect(panel);
            for (final finder in [title, detail]) {
              final rect = tester.getRect(finder);
              expect(rect.left, greaterThanOrEqualTo(panelRect.left));
              expect(rect.right, lessThanOrEqualTo(panelRect.right));
              expect(rect.top, greaterThanOrEqualTo(panelRect.top));
              expect(rect.bottom, lessThanOrEqualTo(panelRect.bottom));
            }
            expect(tester.takeException(), isNull);
            await tester.drag(_pager, const Offset(-240, 0));
            await tester.pumpAndSettle();
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
