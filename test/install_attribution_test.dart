import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/install_attribution_service.dart';

void main() {
  group('InstallAttributionService.extractReferralCode', () {
    test('parses an Android Play Install Referrer query string', () {
      expect(
        InstallAttributionService.extractReferralCode(
          'referrer=BARA-7F3K&utm_source=share',
        ),
        'BARA-7F3K',
      );
    });

    test('parses an Android referrer that is just referrer=<code>', () {
      expect(
        InstallAttributionService.extractReferralCode('referrer=bara-7f3k'),
        'BARA-7F3K',
      );
    });

    test('parses a full invite URL (iOS clipboard handoff)', () {
      expect(
        InstallAttributionService.extractReferralCode(
          'https://steptracker-api.org/r/BARA-7F3K',
        ),
        'BARA-7F3K',
      );
    });

    test('parses referral query from a combined iOS race URL', () {
      expect(
        InstallAttributionService.extractReferralCode(
          'https://steptracker-api.org/r/raceToken123?ref=BARA-7F3K',
        ),
        'BARA-7F3K',
      );
    });

    test('parses ref beside raceToken in decoded Play payload', () {
      expect(
        InstallAttributionService.extractReferralCode(
          'raceToken=raceToken123&ref=BARA-7F3K',
        ),
        'BARA-7F3K',
      );
    });

    test('parses ref from an encoded nested Play payload', () {
      expect(
        InstallAttributionService.extractReferralCode(
          'referrer=raceToken%3DraceToken123%26ref%3DBARA-7F3K',
        ),
        'BARA-7F3K',
      );
    });

    test('parses a bare code', () {
      expect(
        InstallAttributionService.extractReferralCode('bara-7f3k'),
        'BARA-7F3K',
      );
    });

    test('returns null for a non-referral referrer (organic install)', () {
      expect(
        InstallAttributionService.extractReferralCode(
          'utm_source=google-play&utm_medium=organic',
        ),
        isNull,
      );
    });

    test('returns null for a race share URL (not a referral)', () {
      expect(
        InstallAttributionService.extractReferralCode(
          'https://steptracker-api.org/r/abc123racetoken',
        ),
        isNull,
      );
    });

    test('returns null for empty / null / junk', () {
      expect(InstallAttributionService.extractReferralCode(null), isNull);
      expect(InstallAttributionService.extractReferralCode(''), isNull);
      expect(InstallAttributionService.extractReferralCode('   '), isNull);
      expect(InstallAttributionService.extractReferralCode('BARA-'), isNull);
    });
  });

  group('InstallAttributionService.extractRaceShareToken', () {
    test('preserves a race destination from a combined install URL', () {
      expect(
        InstallAttributionService.extractRaceShareToken(
          'https://steptracker-api.org/r/raceToken123?ref=BARA-7F3K',
        ),
        'raceToken123',
      );
    });

    test('reads a nested Play Install Referrer race URL', () {
      expect(
        InstallAttributionService.extractRaceShareToken(
          'referrer=https%3A%2F%2Fsteptracker-api.org%2Fr%2FraceToken123%3Fref%3DBARA-7F3K',
        ),
        'raceToken123',
      );
    });

    test('reads raceToken beside ref in decoded Play payload', () {
      expect(
        InstallAttributionService.extractRaceShareToken(
          'raceToken=raceToken123&ref=BARA-7F3K',
        ),
        'raceToken123',
      );
    });

    test('reads raceToken from an encoded nested Play payload', () {
      expect(
        InstallAttributionService.extractRaceShareToken(
          'referrer=raceToken%3DraceToken123%26ref%3DBARA-7F3K',
        ),
        'raceToken123',
      );
    });
  });
}
