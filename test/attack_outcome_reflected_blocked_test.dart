import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/attack_outcome_modal.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

// ---------------------------------------------------------------------------
// Reflected-then-blocked reveal: the target's Mirror bounces the attack back
// and the attacker's own Compression Socks block the bounce. The backend sends
// BOTH discriminators on one result:
//   { blocked: true, blockedBy: "COMPRESSION_SOCKS", outcome: "BLOCKED",
//     reflected: true, reflectedBy: "MIRROR" }
// New clients render the combined "BOUNCED & BLOCKED!" modal with the
// Mirror → Socks story; frozen old clients switch on `outcome` and show the
// plain blocked modal (verified by the pre-existing tests, unchanged).
// ---------------------------------------------------------------------------

const Map<String, dynamic> _combinedResult = {
  'blocked': true,
  'blockedBy': 'COMPRESSION_SOCKS',
  'outcome': 'BLOCKED',
  'reflected': true,
  'reflectedBy': 'MIRROR',
};

Future<void> _pumpModal(WidgetTester tester, Map<String, dynamic> result) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AttackOutcomeModal(result: result, onDismiss: () {}),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('both flags on one result classify as reflectedBlocked', () {
    expect(
      attackOutcomeFromResult(_combinedResult),
      AttackOutcome.reflectedBlocked,
    );
    // Even without the outcome string (defensive read), the pair of legacy
    // flags is enough.
    expect(
      attackOutcomeFromResult(const {'blocked': true, 'reflected': true}),
      AttackOutcome.reflectedBlocked,
    );
    // Single flags keep their existing meaning.
    expect(
      attackOutcomeFromResult(const {'blocked': true}),
      AttackOutcome.blocked,
    );
    expect(
      attackOutcomeFromResult(const {'reflected': true}),
      AttackOutcome.reflected,
    );
  });

  testWidgets('renders the combined BOUNCED & BLOCKED reveal', (tester) async {
    await _pumpModal(tester, _combinedResult);

    expect(find.text('BOUNCED & BLOCKED!'), findsOneWidget);
    expect(
      find.text(
        'Their Mirror bounced your attack back — but your Compression Socks blocked it!',
      ),
      findsOneWidget,
    );
    // The two-beat icon story: Mirror → Compression Socks.
    final icons = tester
        .widgetList<PowerupIcon>(find.byType(PowerupIcon))
        .map((i) => i.type)
        .toList();
    expect(icons, ['MIRROR', 'COMPRESSION_SOCKS']);
    // Name line shows the shield that saved the attacker.
    expect(find.text('Compression Socks'), findsOneWidget);
  });

  testWidgets('plain blocked result still renders the single-icon modal', (
    tester,
  ) async {
    await _pumpModal(tester, const {
      'blocked': true,
      'blockedBy': 'COMPRESSION_SOCKS',
      'outcome': 'BLOCKED',
    });

    expect(find.text('BLOCKED!'), findsOneWidget);
    expect(find.byType(PowerupIcon), findsOneWidget);
  });
}
