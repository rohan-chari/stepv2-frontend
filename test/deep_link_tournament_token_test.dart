import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/deep_link_service.dart';

// Spec §9: tournament share links ride a `/t/<token>` universal link and a
// `bara://tournament/<token>` custom-scheme link, parsed apart from race
// `/r/<token>` links so the two never clobber each other.
void main() {
  group('parseTournamentShareToken', () {
    test('extracts from an https /t/<token> universal link', () {
      expect(
        DeepLinkService.parseTournamentShareToken(
          Uri.parse('https://steptracker-api.org/t/abc123'),
        ),
        'abc123',
      );
    });

    test('host-agnostic (staging)', () {
      expect(
        DeepLinkService.parseTournamentShareToken(
          Uri.parse('https://api.staging.steptracker-api.org/t/tok-99'),
        ),
        'tok-99',
      );
    });

    test('extracts from bara://tournament/<token>', () {
      expect(
        DeepLinkService.parseTournamentShareToken(
          Uri.parse('bara://tournament/tok_xyz'),
        ),
        'tok_xyz',
      );
    });

    test('tolerates bara:///t/<token>', () {
      expect(
        DeepLinkService.parseTournamentShareToken(
          Uri.parse('bara:///t/deep'),
        ),
        'deep',
      );
    });

    test('a race /r/<token> link is NOT a tournament token', () {
      expect(
        DeepLinkService.parseTournamentShareToken(
          Uri.parse('https://steptracker-api.org/r/raceTok'),
        ),
        isNull,
      );
    });

    test('a tournament /t/<token> link is NOT a race share token', () {
      expect(
        DeepLinkService.parseShareToken(
          Uri.parse('https://steptracker-api.org/t/abc123'),
        ),
        isNull,
      );
    });

    test('garbage / non-matching links return null', () {
      expect(
        DeepLinkService.parseTournamentShareToken(
          Uri.parse('https://steptracker-api.org/x/abc'),
        ),
        isNull,
      );
      expect(
        DeepLinkService.parseTournamentShareToken(Uri.parse('bara://join/abc')),
        isNull,
      );
    });
  });
}
