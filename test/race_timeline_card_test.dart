import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/widgets/race_timeline_card.dart';

// Race timeline options — spec §9 test 22 (architect S3): the TIMELINE card is
// ONE widget shared by the create and edit screens, so it is tested once, here,
// on the real widget rather than twice through two screens.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Known widget-test hang otherwise (memory: flutter-widget-test-packageinfo-hang).
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.7',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  final start = DateTime(2026, 8, 18, 8);
  final end = DateTime(2026, 8, 22, 17);

  Future<void> pump(WidgetTester tester, Widget card) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: card))),
    );
    await tester.pump();
  }

  testWidgets('renders TIMELINE with 1 DAY / 1 WEEK / 2 WEEKS / CUSTOM', (
    tester,
  ) async {
    await pump(
      tester,
      RaceTimelineCard(selectedDays: 7, customChipEnabled: true),
    );

    expect(find.text('TIMELINE'), findsOneWidget);
    expect(find.text('DURATION'), findsNothing);
    expect(find.text('1 DAY'), findsOneWidget);
    expect(find.text('1 WEEK'), findsOneWidget);
    expect(find.text('2 WEEKS'), findsOneWidget);
    expect(find.text('CUSTOM'), findsOneWidget);

    // The keys existing tests already drive stay put for 1/7/14 (spec §4.1).
    for (final days in [1, 7, 14]) {
      expect(find.byKey(Key('duration-option-$days')), findsOneWidget);
    }
    // 3d is retired from the picker.
    expect(find.byKey(const Key('duration-option-3')), findsNothing);
    expect(find.text('3d'), findsNothing);
  });

  testWidgets('the CUSTOM chip is hidden when the feature flag is off', (
    tester,
  ) async {
    await pump(
      tester,
      RaceTimelineCard(selectedDays: 7, customChipEnabled: false),
    );

    expect(find.byKey(const Key('duration-option-custom')), findsNothing);
    expect(find.text('CUSTOM'), findsNothing);
    // The presets are unaffected.
    expect(find.byKey(const Key('duration-option-7')), findsOneWidget);
  });

  testWidgets('preset and custom taps report through their own callbacks', (
    tester,
  ) async {
    int? preset;
    var customTaps = 0;
    await pump(
      tester,
      RaceTimelineCard(
        selectedDays: 7,
        customChipEnabled: true,
        onPresetSelected: (days) => preset = days,
        onCustomSelected: () => customTaps++,
      ),
    );

    await tester.tap(find.byKey(const Key('duration-option-14')));
    expect(preset, 14);
    expect(customTaps, 0);

    await tester.tap(find.byKey(const Key('duration-option-custom')));
    expect(customTaps, 1);
    expect(preset, 14);
  });

  testWidgets('the STARTS/ENDS rows only exist while CUSTOM is selected', (
    tester,
  ) async {
    await pump(
      tester,
      RaceTimelineCard(selectedDays: 7, customChipEnabled: true),
    );
    expect(find.byKey(const Key('timeline-starts-row')), findsNothing);
    expect(find.byKey(const Key('timeline-ends-row')), findsNothing);

    await pump(
      tester,
      RaceTimelineCard(
        selectedDays: 7,
        customChipEnabled: true,
        customSelected: true,
        customEndAt: end,
      ),
    );
    expect(find.byKey(const Key('timeline-starts-row')), findsOneWidget);
    expect(find.byKey(const Key('timeline-ends-row')), findsOneWidget);
    expect(find.text('STARTS'), findsOneWidget);
    expect(find.text('ENDS'), findsOneWidget);
  });

  testWidgets('an unscheduled start reads "When everyone\'s in" (architect R2)', (
    tester,
  ) async {
    await pump(
      tester,
      RaceTimelineCard(
        selectedDays: 7,
        customChipEnabled: true,
        customSelected: true,
        customEndAt: end,
      ),
    );

    expect(find.text("When everyone's in"), findsOneWidget);
    // The wrong label the architect struck must not come back.
    expect(find.text('Now (start manually)'), findsNothing);
  });

  testWidgets('a picked window renders both instants', (tester) async {
    await pump(
      tester,
      RaceTimelineCard(
        selectedDays: 4,
        customChipEnabled: true,
        customSelected: true,
        customStartAt: start,
        customEndAt: end,
      ),
    );

    expect(find.text(formatRaceTimelineInstant(start)), findsOneWidget);
    expect(find.text(formatRaceTimelineInstant(end)), findsOneWidget);
    expect(find.text("When everyone's in"), findsNothing);
  });

  testWidgets('STARTS and ENDS never write each other', (tester) async {
    var startTaps = 0;
    var endTaps = 0;
    await pump(
      tester,
      RaceTimelineCard(
        selectedDays: 4,
        customChipEnabled: true,
        customSelected: true,
        customStartAt: start,
        customEndAt: end,
        onPickStart: () => startTaps++,
        onPickEnd: () => endTaps++,
      ),
    );

    await tester.tap(find.byKey(const Key('timeline-starts-row')));
    expect(startTaps, 1);
    expect(endTaps, 0);

    await tester.tap(find.byKey(const Key('timeline-ends-row')));
    expect(startTaps, 1);
    expect(endTaps, 1);
  });

  testWidgets('the derived length label describes the window', (tester) async {
    await pump(
      tester,
      RaceTimelineCard(
        selectedDays: 4,
        customChipEnabled: true,
        customSelected: true,
        customStartAt: start,
        customEndAt: end,
      ),
    );

    final label = tester
        .widget<Text>(find.byKey(const Key('timeline-window-label')))
        .data!;
    expect(label, '4 DAYS 9 HOURS');
  });

  testWidgets('an invalid window shows the reason in place of the length', (
    tester,
  ) async {
    await pump(
      tester,
      RaceTimelineCard(
        selectedDays: 1,
        customChipEnabled: true,
        customSelected: true,
        customStartAt: start,
        customEndAt: start.add(const Duration(hours: 3)),
        windowError: 'A race has to run at least 1 day',
      ),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const Key('timeline-window-label')))
          .data,
      'A race has to run at least 1 day',
    );
  });

  testWidgets('a selected window with the chip gone renders LOCKED, not live', (
    tester,
  ) async {
    // Kill switch off on a race that already has a window: the presets stay
    // live (clearing is exempt from the server's 403), the pickers do not.
    await pump(
      tester,
      RaceTimelineCard(
        selectedDays: 7,
        customChipEnabled: false,
        customSelected: true,
        customStartAt: start,
        customEndAt: end,
      ),
    );

    expect(find.byKey(const Key('duration-option-7')), findsOneWidget);
    expect(find.byKey(const Key('duration-option-custom')), findsNothing);
    expect(find.byKey(const Key('timeline-starts-row')), findsNothing);
    expect(find.byKey(const Key('timeline-ends-row')), findsNothing);
    expect(find.byKey(const Key('timeline-locked-window')), findsOneWidget);
    expect(find.text(formatRaceTimelineInstant(end)), findsOneWidget);
    expect(find.byKey(const Key('timeline-locked-note')), findsOneWidget);
  });

  testWidgets('read-only mode offers no chips and shows the stamped end', (
    tester,
  ) async {
    await pump(
      tester,
      RaceTimelineCard(
        selectedDays: 7,
        customChipEnabled: true,
        readOnly: true,
        readOnlyEndsAt: end,
      ),
    );

    expect(find.text('TIMELINE'), findsOneWidget);
    for (final days in [1, 7, 14]) {
      expect(find.byKey(Key('duration-option-$days')), findsNothing);
    }
    expect(find.byKey(const Key('duration-option-custom')), findsNothing);
    expect(find.byKey(const Key('timeline-starts-row')), findsNothing);
    expect(find.byKey(const Key('timeline-ends-row')), findsNothing);
    expect(
      find.byKey(const Key('timeline-readonly-end')),
      findsOneWidget,
    );
    expect(
      find.textContaining(formatRaceTimelineInstant(end)),
      findsOneWidget,
    );
  });

  testWidgets('the tutorial key lands on the OUTERMOST node (§10.1 risk 3)', (
    tester,
  ) async {
    final key = GlobalKey();
    await pump(
      tester,
      RaceTimelineCard(
        outerKey: key,
        selectedDays: 7,
        customChipEnabled: true,
      ),
    );

    // The spotlight measures this rect; it must cover the whole card, not just
    // the chip row — a mis-aim here is silent (no compile error, no crash).
    final keyed = tester.getRect(find.byKey(key));
    final card = tester.getRect(find.byType(RaceTimelineCard));
    expect(keyed, card);
    expect(
      keyed.height,
      greaterThan(tester.getRect(find.byKey(const Key('duration-option-7'))).height),
    );
  });
}
