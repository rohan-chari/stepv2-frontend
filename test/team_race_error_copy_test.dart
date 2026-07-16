import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/team_race.dart';

// Issue 3c / 4: friendly copy for the new respond/join + buy-in error codes.
// The homepage handlers and edit-race screen map ApiException.code through
// teamRaceErrorCopy so a frozen-or-newer backend never shows a raw English
// error string. Every mapped code must be non-empty, and an unknown/null code
// must still return the safe generic fallback.
void main() {
  group('Issue 3c — new respond/join error codes', () {
    test('RACE_NOT_FOUND reads as a gone/cancelled race', () {
      final copy = teamRaceErrorCopy('RACE_NOT_FOUND');
      expect(copy, isNotEmpty);
      expect(copy.toLowerCase(), contains('gone'));
    });

    test('RACE_NOT_ACCEPTING reads as not taking racers', () {
      final copy = teamRaceErrorCopy('RACE_NOT_ACCEPTING');
      expect(copy, isNotEmpty);
      expect(copy.toLowerCase(), contains("isn't"));
    });

    test('NOT_INVITED reads as needing an invite', () {
      final copy = teamRaceErrorCopy('NOT_INVITED');
      expect(copy, isNotEmpty);
      expect(copy.toLowerCase(), contains('invite'));
    });

    test('ALREADY_RESPONDED reads as already in the race', () {
      final copy = teamRaceErrorCopy('ALREADY_RESPONDED');
      expect(copy, isNotEmpty);
      expect(copy.toLowerCase(), contains('already'));
    });

    test('PAID_RACE_LOCKED mentions the race is locked', () {
      final copy = teamRaceErrorCopy('PAID_RACE_LOCKED');
      expect(copy, isNotEmpty);
      expect(copy.toLowerCase(), contains('locked'));
    });

    test('INSUFFICIENT_COINS mentions coins', () {
      final copy = teamRaceErrorCopy('INSUFFICIENT_COINS');
      expect(copy, isNotEmpty);
      expect(copy.toLowerCase(), contains('coins'));
    });
  });

  group('Issue 4 — buy-in edit error code', () {
    test('BUYIN_UNAFFORDABLE has a safe generic fallback for empty messages',
        () {
      final copy = teamRaceErrorCopy('BUYIN_UNAFFORDABLE');
      expect(copy, isNotEmpty);
      expect(copy.toLowerCase(), contains('buy-in'));
    });
  });

  group('generic fallback preserved', () {
    test('an unknown code still returns non-empty generic copy', () {
      expect(teamRaceErrorCopy('TOTALLY_NEW_CODE'), isNotEmpty);
      expect(teamRaceErrorCopy(null), isNotEmpty);
    });

    test('the existing codes are untouched', () {
      expect(teamRaceErrorCopy('TEAM_FULL').toLowerCase(), contains('full'));
      expect(
        teamRaceErrorCopy('RACE_ALREADY_STARTED').toLowerCase(),
        contains('started'),
      );
    });
  });
}
