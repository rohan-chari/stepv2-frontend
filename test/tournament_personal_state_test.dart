import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/tournament.dart';

/// §4.2 — mapping a personal tournament into the Active/Pending/Completed
/// pills (or the pinned invites strip).
///
/// Classification follows the user's CURRENT ACTION, not merely the
/// tournament's top-level status: an eliminated player in a still-running
/// bracket has nothing to act on, and a live matchup is actionable even though
/// the bracket is only "ACTIVE" like every other round.
///
/// Every reader must be defensive — a payload from a different backend version
/// can be missing any of these fields and must never crash the list.
void main() {
  const me = 'user-1';

  Map<String, dynamic> t({
    String? status,
    String? myStatus = 'ACCEPTED',
    int? myEliminatedInRound,
    String? championUserId,
    Map<String, dynamic>? myCurrentMatch,
    String? myCurrentMatchRaceId,
    bool includeMatchKey = true,
  }) {
    return {
      'id': 't1',
      'name': 'Bracket',
      if (status != null) 'status': status,
      if (myStatus != null) 'myStatus': myStatus,
      'myEliminatedInRound': myEliminatedInRound,
      if (championUserId != null) 'championUserId': championUserId,
      if (myCurrentMatchRaceId != null)
        'myCurrentMatchRaceId': myCurrentMatchRaceId,
      if (includeMatchKey) 'myCurrentMatch': myCurrentMatch,
    };
  }

  group('§4.2 state mapping', () {
    test('INVITED to a pending tournament goes to the invites strip', () {
      expect(
        Tournament.personalListState(
          t(status: 'PENDING', myStatus: 'INVITED'),
          userId: me,
        ),
        TournamentListState.invite,
      );
    });

    test('INVITED to an already-ACTIVE tournament still goes to invites', () {
      // Rendered as expired/unavailable with Decline only — but it must not
      // vanish, or the user can never clear it.
      expect(
        Tournament.personalListState(
          t(status: 'ACTIVE', myStatus: 'INVITED'),
          userId: me,
        ),
        TournamentListState.invite,
      );
    });

    test('a live matchup is Active', () {
      expect(
        Tournament.personalListState(
          t(status: 'ACTIVE', myCurrentMatch: {'raceId': 'race-9'}),
          userId: me,
        ),
        TournamentListState.active,
      );
    });

    test('an accepted lobby participant is Pending', () {
      expect(
        Tournament.personalListState(t(status: 'PENDING'), userId: me),
        TournamentListState.pending,
      );
    });

    test('accepted, alive, between rounds is Pending', () {
      // Bracket is running but I have no live matchup right now.
      expect(
        Tournament.personalListState(t(status: 'ACTIVE'), userId: me),
        TournamentListState.pending,
      );
    });

    test('eliminated is Completed even while the bracket runs', () {
      expect(
        Tournament.personalListState(
          t(status: 'ACTIVE', myEliminatedInRound: 2),
          userId: me,
        ),
        TournamentListState.completed,
      );
    });

    test('champion is Completed', () {
      expect(
        Tournament.personalListState(
          t(status: 'COMPLETED', championUserId: me),
          userId: me,
        ),
        TournamentListState.completed,
      );
    });

    test('a completed tournament is Completed', () {
      expect(
        Tournament.personalListState(t(status: 'COMPLETED'), userId: me),
        TournamentListState.completed,
      );
    });

    test('a cancelled tournament is Completed (nothing left to act on)', () {
      expect(
        Tournament.personalListState(t(status: 'CANCELLED'), userId: me),
        TournamentListState.completed,
      );
    });

    test('a live matchup takes precedence over an eliminated flag', () {
      // Table order puts myCurrentMatch above Eliminated. If a backend ever
      // sends both, showing the ACTIONABLE state is the better failure mode.
      expect(
        Tournament.personalListState(
          t(
            status: 'ACTIVE',
            myEliminatedInRound: 1,
            myCurrentMatch: {'raceId': 'race-9'},
          ),
          userId: me,
        ),
        TournamentListState.active,
      );
    });
  });

  group('defensive defaults', () {
    test('accepted with no conclusive signal defaults to Pending', () {
      expect(
        Tournament.personalListState({'id': 't1'}, userId: me),
        TournamentListState.pending,
      );
    });

    test('an unknown status never crashes and defaults to Pending', () {
      expect(
        Tournament.personalListState(
          t(status: 'SOME_FUTURE_STATUS'),
          userId: me,
        ),
        TournamentListState.pending,
      );
    });

    test('an unknown myStatus is treated as a non-invite participant', () {
      expect(
        Tournament.personalListState(
          t(status: 'ACTIVE', myStatus: 'SOMETHING_NEW'),
          userId: me,
        ),
        TournamentListState.pending,
      );
    });

    test('a null userId still classifies without throwing', () {
      expect(
        Tournament.personalListState(t(status: 'PENDING'), userId: null),
        TournamentListState.pending,
      );
    });

    test('garbage field types never throw', () {
      expect(
        () => Tournament.personalListState(
          {
            'status': 42,
            'myStatus': <String>[],
            'myEliminatedInRound': 'nope',
            'myCurrentMatch': 'not-a-map',
          },
          userId: me,
        ),
        returnsNormally,
      );
    });
  });

  group('older backend (myCurrentMatch absent entirely)', () {
    test('a live matchup known only by raceId is still Active', () {
      // §5 retains myCurrentMatchRaceId for clients already reading it. Using
      // it as a fallback signal keeps a live matchup actionable against a
      // backend that has not shipped the additive object yet.
      expect(
        Tournament.personalListState(
          t(
            status: 'ACTIVE',
            myCurrentMatchRaceId: 'race-9',
            includeMatchKey: false,
          ),
          userId: me,
        ),
        TournamentListState.active,
      );
    });

    test('no matchup signal at all is Pending', () {
      expect(
        Tournament.personalListState(
          t(status: 'ACTIVE', includeMatchKey: false),
          userId: me,
        ),
        TournamentListState.pending,
      );
    });
  });

  group('myCurrentMatch readers', () {
    test('reads the additive inventory fields', () {
      final match = Tournament.myCurrentMatch(
        t(
          myCurrentMatch: {
            'raceId': 'race-9',
            'endsAt': '2026-07-20T22:00:00.000Z',
            'myPlacement': 2,
            'myPlacementHidden': false,
            'queuedBoxCount': 1,
            'mysteryBoxCount': 1,
            'slotItems': [
              {'id': 'p1', 'type': 'LEG_CRAMP', 'status': 'HELD'},
            ],
          },
        ),
      );
      expect(match, isNotNull);
      expect(Tournament.matchRaceId(match), 'race-9');
      expect(Tournament.matchPlacement(match), 2);
      expect(Tournament.matchPlacementHidden(match), isFalse);
      expect(Tournament.matchQueuedBoxCount(match), 1);
      expect(Tournament.matchMysteryBoxCount(match), 1);
      expect(Tournament.matchSlotItems(match).length, 1);
    });

    test('every field defaults safely when the object is absent', () {
      expect(Tournament.myCurrentMatch(t(includeMatchKey: false)), isNull);
      expect(Tournament.matchRaceId(null), isNull);
      expect(Tournament.matchPlacement(null), isNull);
      expect(Tournament.matchPlacementHidden(null), isFalse);
      expect(Tournament.matchQueuedBoxCount(null), 0);
      expect(Tournament.matchMysteryBoxCount(null), 0);
      expect(Tournament.matchSlotItems(null), isEmpty);
    });

    test('an empty/partial match object renders empty slots, never throws', () {
      final match = Tournament.myCurrentMatch(t(myCurrentMatch: {}));
      expect(match, isNotNull);
      expect(Tournament.matchRaceId(match), isNull);
      expect(Tournament.matchSlotItems(match), isEmpty);
      expect(Tournament.matchQueuedBoxCount(match), 0);
      expect(Tournament.matchPlacementHidden(match), isFalse);
    });

    test('malformed field types degrade rather than throw', () {
      final match = Tournament.myCurrentMatch({
        'myCurrentMatch': {
          'raceId': 42,
          'myPlacement': 'second',
          'myPlacementHidden': 'yes',
          'queuedBoxCount': 'one',
          'slotItems': 'not-a-list',
        },
      });
      expect(Tournament.matchRaceId(match), isNull);
      expect(Tournament.matchPlacement(match), isNull);
      expect(Tournament.matchPlacementHidden(match), isFalse);
      expect(Tournament.matchQueuedBoxCount(match), 0);
      expect(Tournament.matchSlotItems(match), isEmpty);
    });

    test('a non-map myCurrentMatch is treated as absent', () {
      expect(Tournament.myCurrentMatch({'myCurrentMatch': 'nope'}), isNull);
    });

    test('slot items keep only well-formed maps', () {
      final match = Tournament.myCurrentMatch({
        'myCurrentMatch': {
          'slotItems': [
            null,
            'junk',
            {'id': 'p1', 'type': 'LEG_CRAMP', 'status': 'HELD'},
          ],
        },
      });
      expect(Tournament.matchSlotItems(match).length, 1);
    });
  });

  group('navigation target', () {
    test('an active matchup resolves its raceId from the additive object', () {
      expect(
        Tournament.matchRaceId(
          Tournament.myCurrentMatch(
            t(myCurrentMatch: {'raceId': 'race-9'}),
          ),
        ),
        'race-9',
      );
    });

    test('liveMatchRaceId falls back to the legacy top-level field', () {
      expect(
        Tournament.liveMatchRaceId(
          t(myCurrentMatchRaceId: 'legacy-race', includeMatchKey: false),
        ),
        'legacy-race',
      );
    });

    test('liveMatchRaceId prefers the additive object when both exist', () {
      expect(
        Tournament.liveMatchRaceId(
          t(
            myCurrentMatch: {'raceId': 'new-race'},
            myCurrentMatchRaceId: 'legacy-race',
          ),
        ),
        'new-race',
      );
    });

    test('liveMatchRaceId is null when there is no live matchup', () {
      expect(Tournament.liveMatchRaceId(t(includeMatchKey: false)), isNull);
    });
  });
}
