import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/deep_link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseShareToken', () {
    test('extracts the token from an https universal link (/r/<token>)', () {
      expect(
        DeepLinkService.parseShareToken(
          Uri.parse('https://steptracker-api.org/r/abc123def456'),
        ),
        'abc123def456',
      );
    });

    test('works for the staging host too (host-agnostic)', () {
      expect(
        DeepLinkService.parseShareToken(
          Uri.parse('https://api.staging.steptracker-api.org/r/tok'),
        ),
        'tok',
      );
    });

    test('extracts the token from a bara://join/<token> custom-scheme link', () {
      expect(
        DeepLinkService.parseShareToken(Uri.parse('bara://join/tok-xyz')),
        'tok-xyz',
      );
    });

    test('extracts the token from a bara://race/<token> custom-scheme link', () {
      expect(
        DeepLinkService.parseShareToken(Uri.parse('bara://race/tok-xyz')),
        'tok-xyz',
      );
    });

    test('returns null for an unrelated https path', () {
      expect(
        DeepLinkService.parseShareToken(
          Uri.parse('https://steptracker-api.org/privacy'),
        ),
        isNull,
      );
    });

    test('returns null for an /r/ link with no token', () {
      expect(
        DeepLinkService.parseShareToken(
          Uri.parse('https://steptracker-api.org/r/'),
        ),
        isNull,
      );
    });

    test('returns null for a custom-scheme link with an unknown action', () {
      expect(
        DeepLinkService.parseShareToken(Uri.parse('bara://settings/foo')),
        isNull,
      );
    });

    test('rejects a token with illegal characters', () {
      expect(
        DeepLinkService.parseShareToken(
          Uri.parse('https://steptracker-api.org/r/bad token!'),
        ),
        isNull,
      );
    });

    test('returns null for a referral code (owned by parseReferralCode)', () {
      // A BARA-prefixed code rides the same /r/ path but must NOT be treated as
      // a race share token (we'd try to "join a race" that doesn't exist).
      expect(
        DeepLinkService.parseShareToken(
          Uri.parse('https://steptracker-api.org/r/BARA-7F3K'),
        ),
        isNull,
      );
    });
  });

  group('parseReferralCode', () {
    test('extracts + uppercases a referral code from an https /r/ link', () {
      expect(
        DeepLinkService.parseReferralCode(
          Uri.parse('https://steptracker-api.org/r/bara-7f3k'),
        ),
        'BARA-7F3K',
      );
    });

    test('extracts a referral code from a bara://join/<code> link', () {
      expect(
        DeepLinkService.parseReferralCode(Uri.parse('bara://join/BARA-7F3K')),
        'BARA-7F3K',
      );
    });

    test('returns null for a race share token (no BARA- prefix)', () {
      expect(
        DeepLinkService.parseReferralCode(
          Uri.parse('https://steptracker-api.org/r/abc123def456'),
        ),
        isNull,
      );
    });

    test('returns null for a malformed referral code', () {
      expect(
        DeepLinkService.parseReferralCode(
          Uri.parse('https://steptracker-api.org/r/BARA-'),
        ),
        isNull,
      );
    });
  });

  group('handleLink', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists a valid token to AuthService and notifies pendingToken', () async {
      final authService = AuthService();
      final service = DeepLinkService(authService: authService);

      await service.handleLink(Uri.parse('https://steptracker-api.org/r/tok-1'));

      expect(authService.pendingShareToken, 'tok-1');
      expect(service.pendingToken.value, 'tok-1');
    });

    test('ignores a non-share link (no token persisted)', () async {
      final authService = AuthService();
      final service = DeepLinkService(authService: authService);

      await service.handleLink(Uri.parse('https://steptracker-api.org/support'));

      expect(authService.pendingShareToken, isNull);
      expect(service.pendingToken.value, isNull);
    });

    test('persists a referral code (and does NOT push pendingToken)', () async {
      final authService = AuthService();
      final service = DeepLinkService(authService: authService);

      await service.handleLink(
        Uri.parse('https://steptracker-api.org/r/BARA-7F3K'),
      );

      expect(authService.pendingReferralCode, 'BARA-7F3K');
      // No race to auto-join, so the share-token notifier stays null.
      expect(authService.pendingShareToken, isNull);
      expect(service.pendingToken.value, isNull);
    });
  });
}
