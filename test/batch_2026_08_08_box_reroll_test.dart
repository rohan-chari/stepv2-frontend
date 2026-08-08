// Feature batch 2026-08-08 — Item 11: rewarded-ad mystery-box reroll.
//
// Covers the gating (flag on/off, demo, already-rerolled), the re-spin to the
// new result, and the ui-test-planner's risks 4 and 5: the button must NOT
// leak onto the OPEN ALL flow, the hand-forked daily-reward reel, or the demo.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';
import 'package:step_tracker/screens/multi_case_opening_screen.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:step_tracker/widgets/pill_button.dart';

Map<String, dynamic> _openResult({String type = 'PROTEIN_SHAKE'}) => {
  'result': {
    'id': 'pu-1',
    'type': type,
    'rarity': 'COMMON',
    'autoActivated': false,
  },
};

Finder get _rerollButton => find.byKey(const Key('case-reroll-button'));

/// Drives the reel from open to reveal. The strip is swipe-OR-TAP gated; the
/// spinning icon never settles, so pump fixed durations (same shape as
/// test/case_opening_toast_test.dart).
Future<void> _spinToReveal(WidgetTester tester) async {
  await tester.tap(find.text('SWIPE OR TAP'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 4100));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _pumpCase(
  WidgetTester tester, {
  Future<Map<String, dynamic>?> Function(String)? onReroll,
  bool demoMode = false,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: CaseOpeningScreen(
        openMysteryBox: () async => _openResult(),
        onReroll: onReroll,
        demoMode: demoMode,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.steps',
      version: '2.2.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('gating', () {
    testWidgets('no button before the reveal', (tester) async {
      await _pumpCase(tester, onReroll: (_) async => null);
      expect(_rerollButton, findsNothing);
    });

    testWidgets('button appears after the reveal when wired', (tester) async {
      await _pumpCase(tester, onReroll: (_) async => null);
      await _spinToReveal(tester);

      expect(find.text('UNBOXED'), findsOneWidget);
      expect(_rerollButton, findsOneWidget);
      expect(find.text('REROLL · WATCH AD'), findsOneWidget);
    });

    testWidgets('flag off (onReroll null) → no button ever', (tester) async {
      await _pumpCase(tester);
      await _spinToReveal(tester);

      expect(find.text('UNBOXED'), findsOneWidget);
      expect(_rerollButton, findsNothing);
    });

    testWidgets('demo mode hides it even when wired', (tester) async {
      await _pumpCase(tester, onReroll: (_) async => null, demoMode: true);
      await _spinToReveal(tester);

      expect(find.text('UNBOXED'), findsOneWidget);
      expect(_rerollButton, findsNothing);
    });
  });

  group('rerolling', () {
    testWidgets('a successful reroll re-spins to the NEW result', (
      tester,
    ) async {
      var calls = 0;
      String? rerolledId;
      await _pumpCase(
        tester,
        onReroll: (id) async {
          calls++;
          rerolledId = id;
          return {'id': id, 'type': 'ENERGY_GEL', 'rarity': 'RARE'};
        },
      );
      await _spinToReveal(tester);
      expect(find.text('UNBOXED'), findsOneWidget);

      await tester.tap(_rerollButton);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(calls, 1);
      expect(rerolledId, 'pu-1');

      // The reel re-arms so the user watches their reroll land.
      expect(find.text('UNBOXED'), findsNothing);
      expect(find.text('SWIPE OR TAP'), findsOneWidget);

      await _spinToReveal(tester);

      // Landed again, on the NEW powerup — and no second server roll.
      expect(find.text('UNBOXED'), findsOneWidget);
      expect(calls, 1);
      // One reroll per box: the button is gone for good.
      expect(_rerollButton, findsNothing);
    });

    testWidgets('backing out of the ad keeps the original result', (
      tester,
    ) async {
      await _pumpCase(tester, onReroll: (_) async => null);
      await _spinToReveal(tester);
      await tester.tap(_rerollButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Still revealed, still offering the reroll (no credit was spent).
      expect(find.text('UNBOXED'), findsOneWidget);
      expect(_rerollButton, findsOneWidget);
      final button = tester.widget<PillButton>(_rerollButton);
      expect(button.loading, isFalse);
    });

    testWidgets('a throwing reroll does not wedge the spinner', (tester) async {
      await _pumpCase(
        tester,
        onReroll: (_) async => throw Exception('network'),
      );
      await _spinToReveal(tester);
      await tester.tap(_rerollButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.widget<PillButton>(_rerollButton).loading, isFalse);
    });
  });

  group('the button must not leak to other reels', () {
    // ui-test-planner risk 4.
    testWidgets('MultiCaseOpeningScreen (OPEN ALL) has no reroll', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiCaseOpeningScreen(
            boxCount: 2,
            openAll: () async => [
              {'powerupId': 'a', 'type': 'PROTEIN_SHAKE', 'rarity': 'COMMON'},
              {'powerupId': 'b', 'type': 'ENERGY_GEL', 'rarity': 'RARE'},
            ],
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(_rerollButton, findsNothing);
      expect(find.text('REROLL · WATCH AD'), findsNothing);
    });

    // Risk 4 again: the daily-reward reel is a hand-forked copy of the case
    // chrome. A structural guard is the honest test here — it must not import
    // or construct CaseOpeningScreen, so it cannot inherit the button.
    test('the daily-reward reel does not reuse CaseOpeningScreen', () {
      // Guarded at the source level rather than by pumping the whole daily
      // reward screen, which needs a backend + ad controller.
      const path = 'lib/screens/daily_reward_screen.dart';
      final source = _readSource(path);
      expect(
        source.contains('CaseOpeningScreen('),
        isFalse,
        reason:
            'daily_reward_screen is a hand-forked reel; if it ever starts '
            'constructing CaseOpeningScreen it would inherit the reroll '
            'button. Pass onReroll: null explicitly if that changes.',
      );
      expect(source.contains('onReroll'), isFalse);
    });
  });

  group('demo/tutorial fixtures must not advertise boxReroll', () {
    // ui-test-planner risk 5.
    test('the demo engine progress payload has no boxReroll', () {
      final engine = DemoRaceEngine(
        myUserId: 'me',
        myDisplayName: 'Rohan',
        myAccessories: const [],
      );
      final progress = engine.raceProgress(DateTime.now());
      final powerupData = progress['powerupData'] as Map<String, dynamic>;
      expect(powerupData.containsKey('boxReroll'), isFalse);
      expect(powerupData['boxReroll'], isNull);
    });

    test('the tutorial preview payloads have no boxReroll', () {
      final detail = tutorialPreviewRaceDetail();
      expect(detail.toString().contains('boxReroll'), isFalse);
    });
  });
}

String _readSource(String relativePath) {
  // ignore: avoid_slow_async_io
  final file = File(relativePath);
  return file.readAsStringSync();
}
