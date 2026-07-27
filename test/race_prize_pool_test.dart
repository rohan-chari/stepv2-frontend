import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/race_prize_pool.dart';

// Structural guard (spec §9 "Structural: the Dart duration table equals the
// backend fixtures"). The create screen previews a pool for a race that does
// not exist yet, so the duration bands are mirrored client-side. If the two
// tables ever drift, the preview lies about real coins — so the owner's
// fixtures are asserted here as executable spec.

void main() {
  group('prizePoolDurationPoints mirrors the backend bands', () {
    test('band boundaries', () {
      expect(prizePoolDurationPoints(1), 1);
      expect(prizePoolDurationPoints(2), 2);
      expect(prizePoolDurationPoints(3), 2);
      expect(prizePoolDurationPoints(4), 4);
      expect(prizePoolDurationPoints(7), 4);
      expect(prizePoolDurationPoints(8), 8);
      expect(prizePoolDurationPoints(14), 8);
      expect(prizePoolDurationPoints(30), 8);
    });

    test('clamps below the first band', () {
      expect(prizePoolDurationPoints(0), 1);
      expect(prizePoolDurationPoints(-3), 1);
    });

    test('monotonic non-decreasing across the legal 1..30 range', () {
      var previous = prizePoolDurationPoints(1);
      for (var days = 2; days <= 30; days++) {
        final points = prizePoolDurationPoints(days);
        expect(
          points,
          greaterThanOrEqualTo(previous),
          reason:
              'a $days-day race must not pay fewer points than a '
              '${days - 1}-day race',
        );
        previous = points;
      }
    });

    test('5 days (sent by frozen clients) falls to the lower band', () {
      expect(prizePoolDurationPoints(5), 4);
    });
  });

  group('computePrizePool reproduces the owner fixtures (spec §1)', () {
    test('4 players / 3 days = 160', () {
      expect(computePrizePool(playerCount: 4, durationDays: 3), 160);
    });

    test('20 players / 14 days = 3,200', () {
      expect(computePrizePool(playerCount: 20, durationDays: 14), 3200);
    });

    // Batch 2026-07-27 item 7: the ceiling is the largest pool the formula can
    // produce at the legal field cap (validateMaxParticipants tops out at 100),
    // so a user-created race is never clamped.
    test('100 players / 14 days = 16,000 (the full field, uncapped)', () {
      expect(computePrizePool(playerCount: 100, durationDays: 14), 16000);
    });

    test('2 players / 1 day = 40', () {
      expect(computePrizePool(playerCount: 2, durationDays: 1), 40);
    });

    test('10 players / 7 days = 800', () {
      expect(computePrizePool(playerCount: 10, durationDays: 7), 800);
    });

    test('a solo field mints nothing', () {
      expect(computePrizePool(playerCount: 1, durationDays: 7), 0);
      expect(computePrizePool(playerCount: 0, durationDays: 7), 0);
    });

    test('clamps to the race maximum', () {
      // Seeded challenges are the only field that can exceed 100 players, and
      // they still clamp — 300 x 4 points x 20 = 24,000 -> 16,000.
      expect(computePrizePool(playerCount: 300, durationDays: 7), 16000);
      expect(kPrizePoolMaxCoins, 16000);
      expect(kPrizeCoinUnit, 20);
    });

    test('tournament fixtures use the tighter bracket ceiling (spec §4.4)', () {
      // 4-bracket / 2d rounds -> 2 rounds x 2 days = 4 total days -> 4 points.
      expect(
        computePrizePool(
          playerCount: 4,
          durationDays: 4,
          max: kTournamentPrizePoolMaxCoins,
        ),
        320,
      );
      // 8-bracket / 2d rounds -> 3 rounds x 2 = 6 days -> 4 points.
      expect(
        computePrizePool(
          playerCount: 8,
          durationDays: 6,
          max: kTournamentPrizePoolMaxCoins,
        ),
        640,
      );
      // 16-bracket / 3d rounds -> 4 rounds x 3 = 12 days -> 8 points -> capped.
      expect(
        computePrizePool(
          playerCount: 16,
          durationDays: 12,
          max: kTournamentPrizePoolMaxCoins,
        ),
        1000,
      );
      expect(kTournamentPrizePoolMaxCoins, 1000);
    });
  });

  group('RacePrizePool.fromRace reads the contract defensively', () {
    test('parses the full §5.1 object', () {
      final pool = RacePrizePool.fromRace({
        'prizePool': {
          'coins': 160,
          'projected': true,
          'atMax': false,
          'playerCount': 4,
          'durationDays': 3,
          'durationPoints': 2,
          'coinUnit': 20,
          'maxCoins': 3200,
          'funded': true,
        },
      });
      expect(pool, isNotNull);
      expect(pool!.coins, 160);
      expect(pool.projected, isTrue);
      expect(pool.atMax, isFalse);
      expect(pool.playerCount, 4);
      expect(pool.durationDays, 3);
      expect(pool.durationPoints, 2);
      expect(pool.coinUnit, 20);
      expect(pool.maxCoins, 3200);
      expect(pool.funded, isTrue);
    });

    test('an older backend that omits prizePool yields null', () {
      expect(RacePrizePool.fromRace({'buyInAmount': 100}), isNull);
      expect(RacePrizePool.fromRace(null), isNull);
      // Explicit null (legacy buy-in race on a new backend) is also null.
      expect(RacePrizePool.fromRace({'prizePool': null}), isNull);
      // A garbage shape must never throw.
      expect(RacePrizePool.fromRace({'prizePool': 'nope'}), isNull);
    });

    test('missing keys and doubles default safely instead of crashing', () {
      final pool = RacePrizePool.fromRace({
        'prizePool': {'coins': 400.0},
      });
      expect(pool, isNotNull);
      expect(pool!.coins, 400);
      expect(pool.projected, isTrue); // safest pre-settlement assumption
      expect(pool.atMax, isFalse);
      expect(pool.coinUnit, kPrizeCoinUnit);
      expect(pool.maxCoins, kPrizePoolMaxCoins);
      expect(pool.funded, isTrue);
      expect(pool.playerCount, 0);
    });
  });

  group('formatPrizeCoins', () {
    test('groups thousands', () {
      expect(formatPrizeCoins(160), '160');
      expect(formatPrizeCoins(3200), '3,200');
      expect(formatPrizeCoins(16000), '16,000');
      expect(formatPrizeCoins(0), '0');
    });
  });
}
