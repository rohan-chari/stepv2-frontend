import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/admin_onboarding_funnel.dart';

/// The admin onboarding funnel renders the demo-race stages the backend added
/// to `ONBOARDING_FUNNEL_STAGES`.
///
/// The screen carries its own hardcoded stage list, so a backend that starts
/// reporting new stages renders nothing until this list is extended — and,
/// symmetrically, this build must survive a backend that is OLDER than it and
/// reports none of them.

Widget host(Map<String, dynamic>? funnel) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: OnboardingFunnelSection(funnel: funnel),
    ),
  ),
);

/// The count rendered on the row labelled [label].
int countFor(WidgetTester tester, String label) {
  final row = find.ancestor(
    of: find.text(label),
    matching: find.byType(Row),
  );
  final texts = tester
      .widgetList<Text>(find.descendant(of: row.first, matching: find.byType(Text)))
      .map((t) => t.data)
      .toList();
  // label, count, trailing
  return int.parse(texts[texts.indexOf(label) + 1]!);
}

Map<String, dynamic> funnelWith(Map<String, int> stages) => {
  'windowDays': 7,
  'byPlatform': {'ios': stages},
};

void main() {
  const newKeys = <String>[
    'tutorial_opened',
    'demo_box_opened',
    'demo_powerup_used',
    'demo_won',
    'tutorial_completed',
  ];

  group('stage list', () {
    test('carries the five demo-race stages', () {
      for (final key in newKeys) {
        expect(
          OnboardingFunnelSection.stageKeys,
          contains(key),
          reason: '$key is reported by the backend but never rendered',
        );
      }
    });

    test('stage order matches the backend ONBOARDING_FUNNEL_STAGES order', () {
      const expected = <String>[
        'onboarding_started',
        'health_cta_tapped',
        'health_granted',
        'health_escaped',
        'health_probe_inconclusive',
        'daily_intro_viewed',
        'tutorial_opened',
        'tutorial_skipped',
        'demo_box_opened',
        'demo_powerup_used',
        'demo_won',
        'tutorial_completed',
        'home_reached',
      ];
      expect(OnboardingFunnelSection.stageKeys, expected);
    });

    test('every stage has a label — the two lists are index-aligned', () {
      expect(
        OnboardingFunnelSection.stageLabels.length,
        OnboardingFunnelSection.stageKeys.length,
        reason: 'stageLabels[i] is read by index; a mismatch throws at render',
      );
    });

    test('tutorial_skipped remains represented for exit analytics', () {
      expect(
        OnboardingFunnelSection.stageKeys,
        contains('tutorial_skipped'),
      );
    });
  });

  testWidgets('the demo stages render as spine rows, chained on retention', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      host(
        funnelWith({
          'onboarding_started': 100,
          'health_cta_tapped': 90,
          'health_granted': 80,
          'health_escaped': 6,
          'health_probe_inconclusive': 2,
          'daily_intro_viewed': 70,
          'tutorial_opened': 60,
          'demo_box_opened': 50,
          'demo_powerup_used': 44,
          'demo_won': 40,
          'tutorial_completed': 38,
          'home_reached': 36,
        }),
      ),
    );
    await tester.pump();

    expect(find.text('ONBOARDING FUNNEL'), findsOneWidget);
    for (final label in OnboardingFunnelSection.stageLabels) {
      expect(find.text(label), findsOneWidget, reason: 'missing row: $label');
    }

    // The demo stages carry step-over-step retention (a spine row), not the
    // "% of start" a muted branch row shows.
    // demo_box_opened / tutorial_opened = 50/60 = 83%.
    expect(find.text('83%'), findsWidgets);
    // demo_powerup_used / demo_box_opened = 44/50 = 88%.
    expect(find.text('88%'), findsWidgets);
    // demo_won / demo_powerup_used = 40/44 = 91%.
    expect(find.text('91%'), findsWidgets);

    // The two health branches stay muted "% of start" rows.
    expect(find.text('6% of start'), findsOneWidget);
    expect(find.text('2% of start'), findsOneWidget);
  });

  testWidgets('an OLDER backend without the demo stages renders them as 0, '
      'never crashes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Exactly the seven stages the previous backend reported.
    await tester.pumpWidget(
      host(
        funnelWith({
          'onboarding_started': 100,
          'health_cta_tapped': 90,
          'health_granted': 80,
          'health_escaped': 6,
          'health_probe_inconclusive': 2,
          'daily_intro_viewed': 70,
          'home_reached': 36,
        }),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('ONBOARDING FUNNEL'), findsOneWidget);
    for (final label in OnboardingFunnelSection.stageLabels) {
      expect(find.text(label), findsOneWidget);
    }
    // The five unreported stages read zero rather than blanking the card.
    expect(countFor(tester, 'Tutorial opened'), 0);
    expect(countFor(tester, 'Box opened'), 0);
    expect(countFor(tester, 'Powerup used'), 0);
    expect(countFor(tester, 'Race won'), 0);
    expect(countFor(tester, 'Tutorial done'), 0);
  });

  testWidgets('a null / empty funnel still renders nothing at all', (
    tester,
  ) async {
    await tester.pumpWidget(host(null));
    await tester.pump();
    expect(find.text('ONBOARDING FUNNEL'), findsNothing);

    await tester.pumpWidget(host(const {'byPlatform': <String, dynamic>{}}));
    await tester.pump();
    expect(find.text('ONBOARDING FUNNEL'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a malformed stage value degrades to 0 rather than throwing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      host({
        'windowDays': 7,
        'byPlatform': {
          'ios': {
            'onboarding_started': 10,
            'demo_box_opened': 'not-a-number',
            'demo_won': null,
          },
        },
      }),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(countFor(tester, 'Box opened'), 0);
    expect(countFor(tester, 'Race won'), 0);
  });
}
