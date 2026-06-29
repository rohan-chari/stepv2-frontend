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
}
