import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/attack_outcome_modal.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

// ---------------------------------------------------------------------------
// PART B: Blocked / Reflected reveal MODAL on the attacker's client.
//
// The use-powerup result carries an `outcome` discriminator (additive):
//   Blocked:    { blocked: true,   blockedBy: "COMPRESSION_SOCKS", outcome: "BLOCKED" }
//   Reflected:  { reflected: true, reflectedBy: "MIRROR",          outcome: "REFLECTED" }
//   Normal:     { outcome: "APPLIED" }
//
// The modal must be read DEFENSIVELY: a missing `outcome` with legacy
// `blocked === true` (older backend) still yields the Blocked modal.
// ---------------------------------------------------------------------------

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

PowerupIcon _findIcon(WidgetTester tester) {
  return tester.widget<PowerupIcon>(find.byType(PowerupIcon));
}

void main() {
  testWidgets('AttackOutcomeModal renders BLOCKED with Compression Socks', (
    tester,
  ) async {
    await _pumpModal(tester, const {
      'blocked': true,
      'blockedBy': 'COMPRESSION_SOCKS',
      'outcome': 'BLOCKED',
    });

    expect(find.text('BLOCKED!'), findsOneWidget);
    expect(find.text('Compression Socks'), findsOneWidget);
    expect(_findIcon(tester).type, 'COMPRESSION_SOCKS');
  });

  testWidgets('AttackOutcomeModal renders REFLECTED with Mirror', (
    tester,
  ) async {
    await _pumpModal(tester, const {
      'reflected': true,
      'reflectedBy': 'MIRROR',
      'outcome': 'REFLECTED',
    });

    expect(find.text('REFLECTED!'), findsOneWidget);
    expect(find.text('Mirror'), findsOneWidget);
    expect(_findIcon(tester).type, 'MIRROR');
  });

  testWidgets(
    'AttackOutcomeModal treats missing outcome + blocked:true as BLOCKED (back-compat)',
    (tester) async {
      // Older backend: no `outcome` field, only the legacy `blocked` flag.
      await _pumpModal(tester, const {'blocked': true});

      expect(find.text('BLOCKED!'), findsOneWidget);
      // Defaults to Compression Socks when blockedBy is absent.
      expect(_findIcon(tester).type, 'COMPRESSION_SOCKS');
    },
  );

  testWidgets(
    'AttackOutcomeModal treats missing outcome + reflected:true as REFLECTED (back-compat)',
    (tester) async {
      await _pumpModal(tester, const {'reflected': true});

      expect(find.text('REFLECTED!'), findsOneWidget);
      expect(_findIcon(tester).type, 'MIRROR');
    },
  );

  test('attackOutcomeFromResult classifies outcomes defensively', () {
    expect(
      attackOutcomeFromResult(const {'outcome': 'BLOCKED'}),
      AttackOutcome.blocked,
    );
    expect(
      attackOutcomeFromResult(const {'outcome': 'REFLECTED'}),
      AttackOutcome.reflected,
    );
    expect(
      attackOutcomeFromResult(const {'outcome': 'APPLIED'}),
      AttackOutcome.applied,
    );
    // Missing outcome, legacy flags.
    expect(
      attackOutcomeFromResult(const {'blocked': true}),
      AttackOutcome.blocked,
    );
    expect(
      attackOutcomeFromResult(const {'reflected': true}),
      AttackOutcome.reflected,
    );
    // Nothing set / empty / null → applied (no special modal).
    expect(attackOutcomeFromResult(const {}), AttackOutcome.applied);
    expect(attackOutcomeFromResult(null), AttackOutcome.applied);
  });
}
