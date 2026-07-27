import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/widgets/notification_ask_dialog.dart';
import 'package:step_tracker/widgets/race_alert_opt_in_card.dart';

/// Batch 2026-07-27 item 19 — the race alert opt-in is an OVERLAY now.
///
/// It used to be an inline card wedged into the race-detail scroll view, which
/// pushed the race itself down the page. It is now presented over race detail,
/// after the first frame, and it reuses [NotificationAskDialog] rather than
/// adding a third notification-prompt surface.
///
/// The dismissal contract is the load-bearing part: the prompt is ONE-SHOT per
/// device, persisted under the same `race_alert_card_dismissed_v1` key, on
/// "Not now" AND on any enable attempt — granted or denied. An overlay that
/// reappeared on every race-detail open would be far worse than the card it
/// replaces.

Widget _host(Future<bool> Function()? onEnable, {String? storageKey}) =>
    MaterialApp(
      home: Scaffold(
        body: RaceAlertOptInCard(
          onEnable: onEnable,
          storageKey: storageKey ?? 'race_alert_card_dismissed_v1',
        ),
      ),
    );

/// The overlay is scheduled post-frame, so it takes a settle to appear.
Future<void> _pumpHost(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the prompt is an overlay, not an inline card in the page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpHost(tester, _host(() async => true));

    // Presented over the page: a route of its own.
    expect(find.byType(NotificationAskDialog), findsOneWidget);
    // …and the widget itself occupies no space in the host's layout.
    final box = tester.getSize(find.byType(RaceAlertOptInCard));
    expect(box, Size.zero);
  });

  testWidgets('the copy drops the system-prompt disclaimer and renames the CTA', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpHost(tester, _host(() async => true));

    expect(find.text('ENABLE NOTIFICATIONS'), findsOneWidget);
    expect(find.text('ENABLE RACE ALERTS'), findsNothing);

    final copy = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? '').toLowerCase())
        .join(' ');
    expect(copy.contains('won’t ask the system'), isFalse);
    expect(copy.contains('until you tap below'), isFalse);
  });

  testWidgets('omitted callback shows no overlay at all', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpHost(tester, _host(null));

    expect(find.byType(NotificationAskDialog), findsNothing);
    expect(find.text('ENABLE NOTIFICATIONS'), findsNothing);
  });

  testWidgets('Not now persists the dismissal and never asks again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    Future<bool> enable() async {
      calls += 1;
      return true;
    }

    await _pumpHost(tester, _host(enable));
    expect(find.byType(NotificationAskDialog), findsOneWidget);

    await tester.tap(find.text('NOT NOW'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationAskDialog), findsNothing);
    // The system was never asked.
    expect(calls, 0);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('race_alert_card_dismissed_v1'), isTrue);

    // A second race-detail open is silent.
    await _pumpHost(tester, _host(enable));
    expect(find.byType(NotificationAskDialog), findsNothing);
  });

  testWidgets('the system callback runs only after an explicit enable tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    await _pumpHost(
      tester,
      _host(() async {
        calls += 1;
        return false;
      }),
    );

    expect(calls, 0);
    await tester.tap(find.text('ENABLE NOTIFICATIONS'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('a DENIED permission does not nag again inside the race', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    Future<bool> deny() async => false;

    await _pumpHost(tester, _host(deny));
    await tester.tap(find.text('ENABLE NOTIFICATIONS'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('race_alert_card_dismissed_v1'), isTrue);

    await _pumpHost(tester, _host(deny));
    expect(find.byType(NotificationAskDialog), findsNothing);
  });

  testWidgets('a GRANTED permission also closes the one-shot', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Future<bool> grant() async => true;

    await _pumpHost(tester, _host(grant));
    await tester.tap(find.text('ENABLE NOTIFICATIONS'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('race_alert_card_dismissed_v1'), isTrue);

    await _pumpHost(tester, _host(grant));
    expect(find.byType(NotificationAskDialog), findsNothing);
  });

  testWidgets('a previously dismissed device never sees the overlay', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'race_alert_card_dismissed_v1': true,
    });
    await _pumpHost(tester, _host(() async => true));

    expect(find.byType(NotificationAskDialog), findsNothing);
  });

  testWidgets('a custom storageKey still gates the overlay', (tester) async {
    SharedPreferences.setMockInitialValues({'other_key_v1': true});
    await _pumpHost(tester, _host(() async => true, storageKey: 'other_key_v1'));

    expect(find.byType(NotificationAskDialog), findsNothing);
  });

  testWidgets('a barrier dismissal counts as a decline and is remembered', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    await _pumpHost(
      tester,
      _host(() async {
        calls += 1;
        return true;
      }),
    );

    // Tap outside the dialog.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(calls, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('race_alert_card_dismissed_v1'), isTrue);
  });
}
