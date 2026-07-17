import '../styles.dart';

/// Lifecycle of a bracket (contract §5 `TournamentStatus`).
enum TournamentStatus { pending, active, completed, cancelled }

/// Parses a wire status string into a [TournamentStatus].
///
/// Returns null for anything absent/unknown — a newer-or-older backend must
/// never crash this build (the #1 rule). Callers treat null as "unknown state"
/// and degrade to a neutral view rather than assuming PENDING.
TournamentStatus? parseTournamentStatus(dynamic value) {
  if (value is String) {
    switch (value) {
      case 'PENDING':
        return TournamentStatus.pending;
      case 'ACTIVE':
        return TournamentStatus.active;
      case 'COMPLETED':
        return TournamentStatus.completed;
      case 'CANCELLED':
        return TournamentStatus.cancelled;
    }
  }
  return null;
}

/// The buy-in ladder maximum per bracket size (D4). A 4-bracket must never pay
/// ~1,000; only a 16-bracket approaches it. Pot caps are 400 / 800 / 992.
/// Mirrors the backend `TOURNAMENT_BUYIN_MAX`; the create screen clamps against
/// it and re-clamps when the bracket size changes.
const Map<int, int> kTournamentBuyInMax = {4: 100, 8: 100, 16: 62};

/// The minimum non-zero buy-in (0 is always allowed = free). Matches the
/// contract's "0, or 10..max" window.
const int kTournamentBuyInMin = 10;

/// The legal bracket sizes (D1 — powers of two, full-only).
const List<int> kTournamentBracketSizes = [4, 8, 16];

/// The legal matchup durations in days (D2).
const List<int> kTournamentDurations = [1, 2, 3];

/// Number of rounds for a bracket size (log2). Defensive default of 0 for an
/// unexpected size so the UI simply draws nothing rather than crashing.
int tournamentRoundsForSize(int bracketSize) {
  switch (bracketSize) {
    case 4:
      return 2;
    case 8:
      return 3;
    case 16:
      return 4;
    default:
      return 0;
  }
}

/// The max buy-in allowed for a bracket size, falling back to the smallest
/// window (100) for an unknown size so the picker never offers an illegal cap.
int tournamentBuyInMaxForSize(int bracketSize) =>
    kTournamentBuyInMax[bracketSize] ?? 100;

/// Client-side buy-in ladder validity check, mirroring `validateTournamentBuyIn`
/// so the create screen can gate submit and re-clamp on bracket-size change.
/// 0 (free) is always valid; otherwise it must sit in [10, max].
bool isValidTournamentBuyIn(int amount, int bracketSize) {
  if (amount == 0) return true;
  final max = tournamentBuyInMaxForSize(bracketSize);
  return amount >= kTournamentBuyInMin && amount <= max;
}

/// Clamps a buy-in to the legal window for [bracketSize]. A value that would
/// fall between 0 and the min snaps to 0 (free) — mirrors the create-screen
/// re-clamp when the bracket size drops (a stale 100 can't survive a switch to
/// 16, which caps at 62).
int clampTournamentBuyIn(int amount, int bracketSize) {
  if (amount <= 0) return 0;
  final max = tournamentBuyInMaxForSize(bracketSize);
  if (amount < kTournamentBuyInMin) return 0;
  if (amount > max) return max;
  return amount;
}

/// Defensive read/format helpers over the tournament JSON maps (contract §6.1,
/// §6.3, §6.4). Everything treats fields as optional/nullable so a payload from
/// a different backend version renders cleanly instead of crashing (#1 rule).
///
/// No `Tournament` model class by design — raw `Map` + these static readers, in
/// the [TeamRace] mold.
abstract final class Tournament {
  // -- Scalar readers ------------------------------------------------------

  static String? id(Map<String, dynamic> t) => t['id'] as String?;

  static String name(Map<String, dynamic> t) {
    final raw = t['name'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return 'Tournament';
  }

  static TournamentStatus? status(Map<String, dynamic> t) =>
      parseTournamentStatus(t['status']);

  static bool isPending(Map<String, dynamic> t) =>
      status(t) == TournamentStatus.pending;
  static bool isActive(Map<String, dynamic> t) =>
      status(t) == TournamentStatus.active;
  static bool isCompleted(Map<String, dynamic> t) =>
      status(t) == TournamentStatus.completed;
  static bool isCancelled(Map<String, dynamic> t) =>
      status(t) == TournamentStatus.cancelled;

  /// Bracket size (4/8/16); 0 when absent so grids draw empty rather than crash.
  static int bracketSize(Map<String, dynamic> t) =>
      (t['bracketSize'] as num?)?.toInt() ?? 0;

  static int matchupDurationDays(Map<String, dynamic> t) =>
      (t['matchupDurationDays'] as num?)?.toInt() ?? 1;

  static int buyInAmount(Map<String, dynamic> t) =>
      (t['buyInAmount'] as num?)?.toInt() ?? 0;

  static int potCoins(Map<String, dynamic> t) =>
      (t['potCoins'] as num?)?.toInt() ?? 0;

  static bool powerupsEnabled(Map<String, dynamic> t) =>
      t['powerupsEnabled'] == true;

  static int? powerupStepInterval(Map<String, dynamic> t) =>
      (t['powerupStepInterval'] as num?)?.toInt();

  static bool isPublic(Map<String, dynamic> t) => t['isPublic'] == true;

  static String? shareToken(Map<String, dynamic> t) => t['shareToken'] as String?;

  /// 0 = not started; 1..totalRounds while active.
  static int currentRound(Map<String, dynamic> t) =>
      (t['currentRound'] as num?)?.toInt() ?? 0;

  /// Total rounds — prefers the server value, falls back to log2(bracketSize).
  static int totalRounds(Map<String, dynamic> t) {
    final raw = (t['totalRounds'] as num?)?.toInt();
    if (raw != null && raw > 0) return raw;
    return tournamentRoundsForSize(bracketSize(t));
  }

  static String? creatorId(Map<String, dynamic> t) => t['creatorId'] as String?;

  static String? championUserId(Map<String, dynamic> t) =>
      t['championUserId'] as String?;

  /// ACCEPTED count (filled slots). Reads the summary `acceptedCount`, else
  /// counts ACCEPTED participants, else 0.
  static int acceptedCount(Map<String, dynamic> t) {
    final raw = (t['acceptedCount'] as num?)?.toInt();
    if (raw != null) return raw;
    return participants(t).where((p) => p['status'] == 'ACCEPTED').length;
  }

  /// Slots still open in the lobby (never negative).
  static int openSlots(Map<String, dynamic> t) =>
      (bracketSize(t) - acceptedCount(t)).clamp(0, bracketSize(t));

  static bool isFull(Map<String, dynamic> t) =>
      bracketSize(t) > 0 && acceptedCount(t) >= bracketSize(t);

  /// The viewer's own participation status string (ACCEPTED/INVITED/DECLINED/…),
  /// or null when absent.
  static String? myStatus(Map<String, dynamic> t) => t['myStatus'] as String?;

  static bool amIn(Map<String, dynamic> t) => myStatus(t) == 'ACCEPTED';
  static bool amInvited(Map<String, dynamic> t) => myStatus(t) == 'INVITED';

  /// Round I was eliminated in (summary bucket), or null if still alive/champ.
  static int? myEliminatedInRound(Map<String, dynamic> t) =>
      (t['myEliminatedInRound'] as num?)?.toInt();

  /// The raceId of my live matchup right now (summary bucket), null if none.
  static String? myCurrentMatchRaceId(Map<String, dynamic> t) =>
      t['myCurrentMatchRaceId'] as String?;

  // -- Featured (seeded) ---------------------------------------------------

  /// A featured/seeded bracket has a `seedId` (creatorId is null). Read
  /// defensively — either field being present marks it featured.
  static bool isFeatured(Map<String, dynamic> t) =>
      (t['seedId'] as String?) != null || (t['seedKind'] as String?) != null;

  static String? seedKind(Map<String, dynamic> t) => t['seedKind'] as String?;

  /// The minted champion prize for a featured bracket (0 when absent / paid).
  static int championPrizeCoins(Map<String, dynamic> t) =>
      (t['championPrizeCoins'] as num?)?.toInt() ?? 0;

  /// The coins the champion walks away with: the pot for a paid user bracket,
  /// or the minted prize for a featured one. 0 for a free user bracket.
  static int championWinnings(Map<String, dynamic> t) {
    final pot = potCoins(t);
    if (pot > 0) return pot;
    return championPrizeCoins(t);
  }

  /// Whether the champion takes any coins at all (drives "…for the crown" copy).
  static bool hasPrize(Map<String, dynamic> t) => championWinnings(t) > 0;

  // -- Collections ---------------------------------------------------------

  /// The participant list (full payload only); empty on summaries.
  static List<Map<String, dynamic>> participants(Map<String, dynamic> t) {
    final raw = t['participants'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(
        growable: false,
      );
    }
    return const [];
  }

  /// The rounds list (full payload only); empty on summaries / while PENDING.
  static List<Map<String, dynamic>> rounds(Map<String, dynamic> t) {
    final raw = t['rounds'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(
        growable: false,
      );
    }
    return const [];
  }

  /// The matchups within a round map.
  static List<Map<String, dynamic>> matchups(Map<String, dynamic> round) {
    final raw = round['matchups'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(
        growable: false,
      );
    }
    return const [];
  }

  /// The players within a matchup map (may be empty for future rounds).
  static List<Map<String, dynamic>> matchupPlayers(Map<String, dynamic> matchup) {
    final raw = matchup['players'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(
        growable: false,
      );
    }
    return const [];
  }

  /// Locates a participant map by userId, or null.
  static Map<String, dynamic>? participantById(
    Map<String, dynamic> t,
    String? userId,
  ) {
    if (userId == null) return null;
    for (final p in participants(t)) {
      if (p['userId'] == userId) return p;
    }
    return null;
  }

  /// Display name for a participant/player, resolving via the participants list
  /// when a matchup player carries only a userId. Falls back to "Racer".
  static String displayName(
    Map<String, dynamic> t,
    Map<String, dynamic> player,
  ) {
    final direct = player['displayName'];
    if (direct is String && direct.trim().isNotEmpty) return direct.trim();
    final byId = participantById(t, player['userId'] as String?);
    final name = byId?['displayName'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return 'Racer';
  }

  // -- Derived helpers -----------------------------------------------------

  /// Alive (not-yet-eliminated) ACCEPTED participants. The champion counts as
  /// alive until crowned. Used for the "N still standing" copy.
  static int aliveCount(Map<String, dynamic> t) {
    var alive = 0;
    for (final p in participants(t)) {
      if (p['status'] != 'ACCEPTED') continue;
      if (p['eliminatedInRound'] == null) alive++;
    }
    return alive;
  }

  /// The champion participant map, or null while unresolved.
  static Map<String, dynamic>? champion(Map<String, dynamic> t) =>
      participantById(t, championUserId(t));

  static bool isChampion(Map<String, dynamic> t, String? userId) =>
      userId != null && championUserId(t) == userId;

  /// D12 featured repeat-entry guard (client-side pre-disable): am I still in a
  /// PENDING/ACTIVE bracket minted from [seedKind] (not yet eliminated)? Reads
  /// my `GET /races` tournaments bucket defensively — if [seedKind] is null or
  /// the fields are missing, returns false so the JOIN tap still hits the
  /// backend (which enforces the guard authoritatively with ALREADY_IN_FEATURED).
  static bool aliveInSeed(
    List<Map<String, dynamic>> myTournaments,
    String? seedKind,
  ) {
    if (seedKind == null || seedKind.isEmpty) return false;
    for (final t in myTournaments) {
      if (Tournament.seedKind(t) != seedKind) continue;
      if (Tournament.myStatus(t) == 'DECLINED') continue;
      final st = Tournament.status(t);
      if (st != TournamentStatus.pending && st != TournamentStatus.active) {
        continue;
      }
      if (Tournament.myEliminatedInRound(t) == null) return true;
    }
    return false;
  }

  /// The matchup [userId] is currently in, searching the current round first,
  /// then any round. Returns null if the user isn't in any drawn matchup.
  static Map<String, dynamic>? myMatchup(
    Map<String, dynamic> t,
    String? userId,
  ) {
    if (userId == null) return null;
    final cur = currentRound(t);
    Map<String, dynamic>? found;
    for (final round in rounds(t)) {
      final roundNo = (round['round'] as num?)?.toInt();
      for (final m in matchups(round)) {
        final inIt = matchupPlayers(
          m,
        ).any((p) => p['userId'] == userId);
        if (!inIt) continue;
        // Prefer the current round's matchup (my live one).
        if (roundNo == cur) return m;
        found ??= m;
      }
    }
    return found;
  }

  /// The winner userId of a matchup, or null (unsettled / placeholder).
  static String? matchupWinnerId(Map<String, dynamic> matchup) =>
      matchup['winnerUserId'] as String?;

  static bool matchupIsTie(Map<String, dynamic> matchup) =>
      matchup['tie'] == true;

  static bool matchupIsCompleted(Map<String, dynamic> matchup) =>
      matchup['status'] == 'COMPLETED';

  static int playerSteps(Map<String, dynamic> player) =>
      (player['totalSteps'] as num?)?.toInt() ?? 0;

  static bool playerForfeited(Map<String, dynamic> player) =>
      player['forfeited'] == true;

  // -- Copy / labels -------------------------------------------------------

  /// Server-authoritative round label when present; otherwise computed from the
  /// bracket size + 1-based round number (16 → ROUND OF 16/QF/SF/FINAL, etc.).
  static String roundLabel(
    Map<String, dynamic> round, {
    int? bracketSize,
    int? roundNumber,
  }) {
    final raw = round['label'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim().toUpperCase();
    final size = bracketSize ?? 0;
    final no = roundNumber ?? (round['round'] as num?)?.toInt() ?? 0;
    return roundLabelFor(size, no);
  }

  /// Pure round-label computation (also used by summary tickets that have only
  /// a round number). Falls back to "ROUND N" for an unexpected size.
  static String roundLabelFor(int bracketSize, int roundNumber) {
    final total = tournamentRoundsForSize(bracketSize);
    if (total <= 0 || roundNumber <= 0) return 'ROUND $roundNumber';
    // Rounds counted from the end: last = FINAL, second-last = SEMIFINALS, …
    final fromEnd = total - roundNumber; // 0 = final
    switch (fromEnd) {
      case 0:
        return 'FINAL';
      case 1:
        return 'SEMIFINALS';
      case 2:
        return 'QUARTERFINALS';
      case 3:
        return 'ROUND OF 16';
      default:
        return 'ROUND $roundNumber';
    }
  }

  /// "8 RACERS · 3 ROUNDS" subcopy for pickers/cards.
  static String sizeSubcopy(int bracketSize) {
    final rounds = tournamentRoundsForSize(bracketSize);
    return '$bracketSize RACERS · $rounds ROUND${rounds == 1 ? '' : 'S'}';
  }

  /// "1-DAY KNOCKOUTS" / "2-DAY KNOCKOUTS" duration subcopy.
  static String durationSubcopy(int days) =>
      '$days-DAY KNOCKOUT${days == 1 ? '' : 'S'}';

  /// The champion-prize plaque copy — "WINNER TAKES 400" for a pot,
  /// "CHAMPION WINS 150" for a featured minted prize, "WINNER TAKES THE CROWN"
  /// for a free user bracket.
  static String prizePlaque(Map<String, dynamic> t) {
    if (isFeatured(t)) {
      final prize = championPrizeCoins(t);
      if (prize > 0) return 'CHAMPION WINS $prize';
      return 'WINNER TAKES THE CROWN';
    }
    final pot = potCoins(t);
    if (pot > 0) return 'WINNER TAKES $pot';
    return 'WINNER TAKES THE CROWN';
  }

  /// A short "5 OF 8 RACERS" fill label for lobbies/cards.
  static String fillLabel(Map<String, dynamic> t) =>
      '${acceptedCount(t)} OF ${bracketSize(t)} RACERS';

  /// The races-tab ticket status line: "ROUND 2 OF 3 · YOU'RE ALIVE" /
  /// "KNOCKED OUT" / "5/8 FILLED" / "CHAMPION!" depending on state.
  static String ticketStatusLine(Map<String, dynamic> t) {
    switch (status(t)) {
      case TournamentStatus.pending:
        return '${acceptedCount(t)}/${bracketSize(t)} FILLED';
      case TournamentStatus.active:
        final round = currentRound(t);
        final total = totalRounds(t);
        final elim = myEliminatedInRound(t);
        if (elim != null) return 'KNOCKED OUT · ROUND $round OF $total';
        return "ROUND $round OF $total · YOU'RE ALIVE";
      case TournamentStatus.completed:
        return 'FINISHED';
      case TournamentStatus.cancelled:
        return 'CANCELLED';
      case null:
        return '';
    }
  }
}

/// Chrome colors for the wooden-bracket / lobby world. Tournaments lean on the
/// app's gold "trophy" accent so they read distinctly from team races (which
/// own the green/gold two-team split) while staying inside the parchment/wood
/// palette.
abstract final class TournamentColors {
  static const gold = AppColors.pillGold;
  static const goldDark = AppColors.pillGoldDark;
  static const goldShadow = AppColors.pillGoldShadow;
  static const plank = AppColors.parchmentDark;
  static const plankBorder = AppColors.parchmentBorder;
  static const win = AppColors.roofLight;
  static const eliminated = AppColors.textMid;
}

/// Maps backend tournament error codes (§6.9) to copy in the app's playful
/// voice. Unknown/absent codes fall back to a safe generic so a newer backend
/// never surfaces a raw code. Sibling of [teamRaceErrorCopy].
String tournamentErrorCopy(String? code, {String? friendName}) {
  switch (code) {
    case 'UPDATE_REQUIRED':
      return 'Update the app to join tournaments.';
    case 'FEATURE_DISABLED':
      return 'Tournaments are taking a quick nap. Try again later!';
    case 'TOURNAMENT_NOT_FOUND':
      return "That tournament is gone — it may have been called off.";
    case 'TOURNAMENT_FULL':
      return 'That bracket just filled up — try another!';
    case 'ALREADY_IN_FEATURED':
      return "Finish your current bracket first, then jump into the next one!";
    case 'ALREADY_JOINED':
      return "You're already in this bracket!";
    case 'TOURNAMENT_NOT_PENDING':
      return 'This bracket already started — no changes now.';
    case 'BRACKET_NOT_FULL':
      return 'Fill every slot before you start the bracket.';
    case 'NO_LIVE_MATCHUP':
      return "You don't have a live matchup to forfeit.";
    case 'INSUFFICIENT_COINS':
      return "You don't have enough coins for the buy-in.";
    case 'NOT_CREATOR':
      return 'Only the creator can do that.';
    case 'NOT_INVITED':
      return 'You need an invite to join this bracket.';
    case 'NOT_PUBLIC':
      return "This bracket is private — you'll need an invite or a link.";
    case 'PARTICIPANT_NOT_FOUND':
      return "That racer isn't in the lobby.";
    case 'ALREADY_RESPONDED':
      return "You've already answered this invite.";
    case 'CREATOR_CANNOT_LEAVE':
      return 'Cancel the tournament instead of leaving it.';
    case 'INVITEE_NEEDS_UPDATE':
      final who = (friendName != null && friendName.trim().isNotEmpty)
          ? friendName.trim()
          : 'Your friend';
      return '$who needs to update the app to join tournaments.';
    case 'TOURNAMENT_RACE_LOCKED':
      return 'This matchup is run by the tournament — manage it from the bracket.';
    case 'VALIDATION':
      return "Those tournament settings don't look right. Give them another look.";
    default:
      return 'Something went sideways. Give it another try!';
  }
}
