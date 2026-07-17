import 'tournament.dart';

/// Visual state of a single player slot in a bracket matchup.
enum BracketSlotState {
  /// An unfilled leaf slot in a PENDING lobby (waiting for a racer).
  open,

  /// A future-round slot whose occupant isn't decided yet.
  tbd,

  /// Occupied and in play (or a PENDING preview placement).
  filled,

  /// Won this matchup and advanced.
  winner,

  /// Lost this matchup (dimmed / struck through).
  eliminated,

  /// The crowned champion (final node only).
  champion,
}

/// One player's cell inside a matchup box. Immutable; carries just enough to
/// render an on-theme mini-card (name, avatar via the participant map, step
/// count) without reaching back into the raw payload.
class BracketSlot {
  const BracketSlot({
    required this.state,
    this.userId,
    this.displayName,
    this.steps = 0,
    this.forfeited = false,
    this.stealthed = false,
    this.isMe = false,
    this.participant,
  });

  final BracketSlotState state;
  final String? userId;
  final String? displayName;
  final int steps;
  final bool forfeited;

  /// The player's score is masked/hidden (detour/stealth); render `???`.
  final bool stealthed;
  final bool isMe;

  /// The participant map (avatar / animal / equippedAccessories), when known.
  final Map<String, dynamic>? participant;

  static const BracketSlot open = BracketSlot(state: BracketSlotState.open);
  static const BracketSlot tbd = BracketSlot(state: BracketSlotState.tbd);

  bool get isFilled =>
      state == BracketSlotState.filled ||
      state == BracketSlotState.winner ||
      state == BracketSlotState.eliminated ||
      state == BracketSlotState.champion;
}

/// A single matchup box (two stacked slots) at a bracket position.
class BracketMatchup {
  const BracketMatchup({
    required this.round,
    required this.matchIndex,
    required this.top,
    required this.bottom,
    this.raceId,
    this.isMine = false,
    this.completed = false,
    this.tie = false,
    this.liveForMe = false,
  });

  /// 1-based round number (1 = leftmost / leaf round).
  final int round;

  /// 0-based index within the round, top-to-bottom.
  final int matchIndex;

  final BracketSlot top;
  final BracketSlot bottom;

  /// The underlying race id (matchup race), when one exists.
  final String? raceId;

  /// The viewer is one of the two players in this matchup.
  final bool isMine;

  final bool completed;
  final bool tie;

  /// My matchup AND it's live (has a race to tap into right now).
  final bool liveForMe;

  List<BracketSlot> get slots => [top, bottom];
}

/// A normalized, render-ready bracket derived from a tournament payload. Pure —
/// no widgets — so the layout/logic is unit-testable. Reads every field
/// defensively (missing → safe placeholder) per the #1 rule.
class BracketModel {
  const BracketModel({
    required this.bracketSize,
    required this.totalRounds,
    required this.rounds,
    required this.champion,
    required this.status,
  });

  final int bracketSize;
  final int totalRounds;

  /// rounds[r] holds the matchups of round r+1, top-to-bottom.
  final List<List<BracketMatchup>> rounds;

  /// The champion cap node (state == champion once crowned, else tbd).
  final BracketSlot champion;

  final TournamentStatus? status;

  bool get isEmpty => bracketSize <= 0 || rounds.isEmpty;

  /// Matchup count for a given 1-based round (bracketSize / 2^round).
  static int matchupsInRound(int bracketSize, int round) {
    var n = bracketSize;
    for (var i = 0; i < round; i++) {
      n = n ~/ 2;
    }
    return n < 0 ? 0 : n;
  }
}

/// Builds a [BracketModel] from a tournament payload for the given viewer.
///
/// - ACTIVE / COMPLETED: renders the real bracket from `rounds`/`matchups`,
///   filling any gap (future rounds, missing matchups) with TBD placeholders so
///   the full skeleton always draws.
/// - PENDING: renders the skeleton with a **client-side preview** — ACCEPTED
///   participants fill the leftmost leaf slots in join order (earliest
///   `joinedAt` first); later rounds are TBD. The backend seeds for real at
///   start, so these positions are a preview only (surfaced honestly in the UI).
BracketModel buildTournamentBracket(
  Map<String, dynamic> t,
  String? myUserId,
) {
  final size = Tournament.bracketSize(t);
  final totalRounds = Tournament.totalRounds(t);
  final status = Tournament.status(t);

  if (size <= 0 || totalRounds <= 0) {
    return BracketModel(
      bracketSize: size,
      totalRounds: totalRounds,
      rounds: const [],
      champion: BracketSlot.tbd,
      status: status,
    );
  }

  final isPending = status == TournamentStatus.pending || status == null;
  final rounds = isPending
      ? _pendingRounds(t, size, totalRounds, myUserId)
      : _payloadRounds(t, size, totalRounds, myUserId);

  return BracketModel(
    bracketSize: size,
    totalRounds: totalRounds,
    rounds: rounds,
    champion: _championSlot(t, myUserId),
    status: status,
  );
}

// -- PENDING preview --------------------------------------------------------

List<List<BracketMatchup>> _pendingRounds(
  Map<String, dynamic> t,
  int size,
  int totalRounds,
  String? myUserId,
) {
  final accepted = _acceptedInJoinOrder(t);
  final rounds = <List<BracketMatchup>>[];

  // Round 1 (leaves): fill in join order, top-to-bottom, matchup by matchup.
  final leafCount = BracketModel.matchupsInRound(size, 1);
  final leaves = <BracketMatchup>[];
  for (var i = 0; i < leafCount; i++) {
    final topIdx = 2 * i;
    final botIdx = 2 * i + 1;
    leaves.add(
      BracketMatchup(
        round: 1,
        matchIndex: i,
        top: topIdx < accepted.length
            ? _slotFromParticipant(t, accepted[topIdx], myUserId)
            : BracketSlot.open,
        bottom: botIdx < accepted.length
            ? _slotFromParticipant(t, accepted[botIdx], myUserId)
            : BracketSlot.open,
      ),
    );
  }
  rounds.add(leaves);

  // Later rounds: all TBD until the bracket starts and seeds are drawn.
  for (var r = 2; r <= totalRounds; r++) {
    final count = BracketModel.matchupsInRound(size, r);
    rounds.add([
      for (var i = 0; i < count; i++)
        BracketMatchup(
          round: r,
          matchIndex: i,
          top: BracketSlot.tbd,
          bottom: BracketSlot.tbd,
        ),
    ]);
  }
  return rounds;
}

/// ACCEPTED participants sorted by `joinedAt` ascending (stable: entries with a
/// missing/unparseable time keep their payload order, sorted after timed ones).
List<Map<String, dynamic>> _acceptedInJoinOrder(Map<String, dynamic> t) {
  final accepted = Tournament.participants(t)
      .where((p) => p['status'] == 'ACCEPTED')
      .toList();
  final indexed = <(int, DateTime?, Map<String, dynamic>)>[];
  for (var i = 0; i < accepted.length; i++) {
    final raw = accepted[i]['joinedAt'];
    final at = raw is String ? DateTime.tryParse(raw) : null;
    indexed.add((i, at, accepted[i]));
  }
  indexed.sort((a, b) {
    final at = a.$2;
    final bt = b.$2;
    if (at != null && bt != null) {
      final c = at.compareTo(bt);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    }
    if (at != null) return -1; // timed entries first
    if (bt != null) return 1;
    return a.$1.compareTo(b.$1); // both untimed → stable by index
  });
  return indexed.map((e) => e.$3).toList(growable: false);
}

BracketSlot _slotFromParticipant(
  Map<String, dynamic> t,
  Map<String, dynamic> p,
  String? myUserId,
) {
  final userId = p['userId'] as String?;
  return BracketSlot(
    state: BracketSlotState.filled,
    userId: userId,
    displayName: Tournament.displayName(t, p),
    isMe: userId != null && userId == myUserId,
    participant: p,
  );
}

// -- ACTIVE / COMPLETED from payload ---------------------------------------

List<List<BracketMatchup>> _payloadRounds(
  Map<String, dynamic> t,
  int size,
  int totalRounds,
  String? myUserId,
) {
  // Index payload rounds by their 1-based round number for defensive lookup.
  final byRound = <int, Map<String, dynamic>>{};
  for (final r in Tournament.rounds(t)) {
    final n = (r['round'] as num?)?.toInt();
    if (n != null) byRound[n] = r;
  }

  final out = <List<BracketMatchup>>[];
  for (var r = 1; r <= totalRounds; r++) {
    final count = BracketModel.matchupsInRound(size, r);
    final payloadRound = byRound[r];
    final payloadMatchups = payloadRound == null
        ? const <Map<String, dynamic>>[]
        : Tournament.matchups(payloadRound);
    // Index matchups by matchIndex for gap-safe lookup.
    final byIndex = <int, Map<String, dynamic>>{};
    for (final m in payloadMatchups) {
      final idx = (m['matchIndex'] as num?)?.toInt();
      if (idx != null) byIndex[idx] = m;
    }

    final matchups = <BracketMatchup>[];
    for (var i = 0; i < count; i++) {
      final m = byIndex[i];
      matchups.add(
        m == null
            ? BracketMatchup(
                round: r,
                matchIndex: i,
                top: BracketSlot.tbd,
                bottom: BracketSlot.tbd,
              )
            : _matchupFromPayload(t, m, r, i, myUserId),
      );
    }
    out.add(matchups);
  }
  return out;
}

BracketMatchup _matchupFromPayload(
  Map<String, dynamic> t,
  Map<String, dynamic> m,
  int round,
  int matchIndex,
  String? myUserId,
) {
  final players = Tournament.matchupPlayers(m);
  final completed = Tournament.matchupIsCompleted(m);
  final winnerId = Tournament.matchupWinnerId(m);
  final tie = Tournament.matchupIsTie(m);
  final raceId = m['raceId'] as String?;

  final top = players.isNotEmpty
      ? _slotFromMatchupPlayer(t, players[0], completed, winnerId, myUserId)
      : BracketSlot.tbd;
  final bottom = players.length > 1
      ? _slotFromMatchupPlayer(t, players[1], completed, winnerId, myUserId)
      : (players.isEmpty ? BracketSlot.tbd : BracketSlot.open);

  final mine = players.any((p) => p['userId'] == myUserId);
  final live =
      mine && !completed && raceId != null && raceId.isNotEmpty;

  return BracketMatchup(
    round: round,
    matchIndex: matchIndex,
    raceId: raceId,
    top: top,
    bottom: bottom,
    isMine: mine,
    completed: completed,
    tie: tie,
    liveForMe: live,
  );
}

BracketSlot _slotFromMatchupPlayer(
  Map<String, dynamic> t,
  Map<String, dynamic> player,
  bool completed,
  String? winnerId,
  String? myUserId,
) {
  final userId = player['userId'] as String?;
  final BracketSlotState state;
  if (completed && winnerId != null) {
    state = userId == winnerId
        ? BracketSlotState.winner
        : BracketSlotState.eliminated;
  } else {
    state = BracketSlotState.filled;
  }
  return BracketSlot(
    state: state,
    userId: userId,
    displayName: Tournament.displayName(t, player),
    steps: Tournament.playerSteps(player),
    forfeited: Tournament.playerForfeited(player),
    stealthed: Tournament.playerStealthed(player),
    isMe: userId != null && userId == myUserId,
    participant: Tournament.participantById(t, userId),
  );
}

// -- Champion ---------------------------------------------------------------

BracketSlot _championSlot(Map<String, dynamic> t, String? myUserId) {
  final champId = Tournament.championUserId(t);
  if (champId == null) return BracketSlot.tbd;
  final p = Tournament.participantById(t, champId);
  return BracketSlot(
    state: BracketSlotState.champion,
    userId: champId,
    displayName: p != null ? Tournament.displayName(t, p) : null,
    isMe: champId == myUserId,
    participant: p,
  );
}
