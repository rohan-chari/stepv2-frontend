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
  });
}
