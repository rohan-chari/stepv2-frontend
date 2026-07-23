import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/attack_outcome_modal.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';
import 'package:step_tracker/widgets/powerup_reveal_modal.dart';

/// §7/§9 powerups5 — the Decoy REDIRECTED attack outcome and the Coin Flip /
/// Mystery Potion reveals, all read DEFENSIVELY (a missing roll field on an
/// older backend must degrade, never crash).

Future<void> _pumpAttackModal(
  WidgetTester tester,
  Map<String, dynamic> result,
) async {
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('REDIRECTED attack outcome (Decoy)', () {
    test('classifies REDIRECTED from the outcome discriminator', () {
      expect(
        attackOutcomeFromResult(const {
          'redirected': true,
          'redirectedBy': 'DECOY',
          'redirectedToUserId': 'user-9',
          'outcome': 'REDIRECTED',
        }),
        AttackOutcome.redirected,
      );
    });

    test('classifies REDIRECTED from the legacy redirected flag alone', () {
      expect(
        attackOutcomeFromResult(const {'redirected': true}),
        AttackOutcome.redirected,
      );
    });

    test('existing outcomes still classify correctly', () {
      expect(
        attackOutcomeFromResult(const {'outcome': 'BLOCKED'}),
        AttackOutcome.blocked,
      );
      expect(
        attackOutcomeFromResult(const {'outcome': 'REFLECTED'}),
        AttackOutcome.reflected,
      );
      expect(attackOutcomeFromResult(const {}), AttackOutcome.applied);
      expect(attackOutcomeFromResult(null), AttackOutcome.applied);
    });

    testWidgets('renders the REDIRECTED reveal with the Decoy icon',
        (tester) async {
      await _pumpAttackModal(tester, const {
        'redirected': true,
        'redirectedBy': 'DECOY',
        'redirectedToUserId': 'user-9',
        'outcome': 'REDIRECTED',
      });

      expect(find.text('REDIRECTED!'), findsOneWidget);
      expect(find.text('Decoy'), findsOneWidget);
      final icon = tester.widget<PowerupIcon>(find.byType(PowerupIcon));
      expect(icon.type, 'DECOY');
    });

    testWidgets('defaults the interceptor to Decoy when redirectedBy is absent',
        (tester) async {
      await _pumpAttackModal(tester, const {'outcome': 'REDIRECTED'});
      expect(find.text('REDIRECTED!'), findsOneWidget);
      final icon = tester.widget<PowerupIcon>(find.byType(PowerupIcon));
      expect(icon.type, 'DECOY');
    });
  });

  group('Coin Flip reveal (defensive)', () {
    test('parses WIN and LOSE', () {
      expect(CoinFlipReveal.fromResult(const {'flip': 'WIN'})?.won, isTrue);
      expect(CoinFlipReveal.fromResult(const {'flip': 'LOSE'})?.won, isFalse);
    });

    test('a missing or unknown flip field yields null (degrade to toast)', () {
      // The old-backend case: item consumed but no roll returned.
      expect(CoinFlipReveal.fromResult(const {}), isNull);
      expect(CoinFlipReveal.fromResult(null), isNull);
      expect(CoinFlipReveal.fromResult(const {'flip': 'MAYBE'}), isNull);
      expect(CoinFlipReveal.fromResult(const {'flip': 42}), isNull);
    });

    testWidgets('a WIN renders the HEADS reveal without crashing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PowerupRevealModal(
              iconType: 'COIN_FLIP',
              title: 'HEADS!',
              subtitle: 'Doubled',
              accent: Colors.amber,
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('HEADS!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Mystery Potion reveal (defensive)', () {
    test('parses a rolled powerup type', () {
      final reveal =
          MysteryPotionReveal.fromResult(const {'rolled': 'PROTEIN_SHAKE'});
      expect(reveal, isNotNull);
      expect(reveal!.isCoinRefund, isFalse);
      expect(reveal.iconType, 'PROTEIN_SHAKE');
      expect(reveal.subtitle(), contains('Protein Shake'));
    });

    test('parses a COIN_REFUND with a coin amount', () {
      final reveal = MysteryPotionReveal.fromResult(
        const {'rolled': 'COIN_REFUND', 'coins': 80},
      );
      expect(reveal, isNotNull);
      expect(reveal!.isCoinRefund, isTrue);
      expect(reveal.coins, 80);
      expect(reveal.iconType, 'MYSTERY_POTION');
      expect(reveal.subtitle(), contains('80'));
    });

    test('a missing rolled field yields null (degrade to toast)', () {
      expect(MysteryPotionReveal.fromResult(const {}), isNull);
      expect(MysteryPotionReveal.fromResult(null), isNull);
      expect(MysteryPotionReveal.fromResult(const {'rolled': ''}), isNull);
    });
  });
}
