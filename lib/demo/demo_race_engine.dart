import 'dart:math' as math;

import '../models/race_prize_pool.dart';
import 'demo_race_script.dart';

/// The demo race simulation (spec §5.2).
///
/// Pure Dart: **no Flutter, no network, no clock of its own, and no RNG.**
/// Every number below is scripted, because a tutorial the user can lose teaches
/// them they are bad at the game — and determinism is what makes the whole
/// thing testable without flake.
///
/// The engine is the *producer* of every wire shape the real `RaceDetailScreen`
/// parses (§6.4). It never reads the network and it can never reach real race,
/// powerup or settlement logic.
class DemoRaceEngine {
  DemoRaceEngine({
    required this.myUserId,
    required this.myDisplayName,
    this.myAccessories = const [],
    DateTime? startedAt,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _startedAt = startedAt ?? (clock ?? DateTime.now)() {
    _steps = {
      rivalLeaderUserId: 24180,
      myUserId: 21640,
      'demo-jordan': 19050,
      'demo-priya': 15220,
    };
  }

  // -- Identity (§5.5b / G2) --------------------------------------------------
  // Injected, never hardcoded. `_myUserId` on the real screen resolves to
  // `authService.userId`, so the engine's roster MUST contain the real id or
  // standings never highlight "you" and `TeamRace.offensiveTargets` fails to
  // exclude the user from their own target picker.

  final String myUserId;
  final String myDisplayName;
  final List<Map<String, dynamic>> myAccessories;

  // -- Fixed identifiers ------------------------------------------------------

  static const String raceId = 'demo-race';
  static const String raceName = 'Demo Dash';
  static const String rivalLeaderUserId = 'demo-sam';

  /// Re-exported from demo_race_script.dart, which owns them because the coach
  /// copy interpolates them and this file already imports that one.
  ///
  /// The user ids above keep their original spellings — they are persisted in
  /// demo progress state, and renaming them would strand anyone mid-tutorial.
  static const String rivalLeaderName = demoRivalLeaderName;
  static const String rivalSecondName = demoRivalSecondName;
  static const String rivalThirdName = demoRivalThirdName;

  /// The Shortcut is no longer handed to the user pre-owned — it is what the
  /// THIRD box rolls. Rows keep their id when a box becomes a powerup, so this
  /// is the third box's id both before and after it is opened.
  static const String shortcutPowerupId = 'demo-pw-box-3';
  static const List<String> mysteryBoxIds = [
    'demo-pw-box-1',
    'demo-pw-box-2',
    shortcutPowerupId,
  ];

  /// What each box rolls, by **open order** (never by slot id).
  static const List<String> boxRollOrder = [
    'PROTEIN_SHAKE',
    'COMPRESSION_SOCKS',
    'SHORTCUT',
  ];

  // -- Clock (§5.5 / D1) ------------------------------------------------------

  static const Duration initialRemaining = Duration(minutes: 2);

  /// The clock never drops below this until the final beat, so a slow reader
  /// can't run the race out mid-lesson.
  static const Duration clockFloor = Duration(seconds: 20);

  /// How long the clock takes to run out once the floor lifts at beat 8.
  static const Duration finalCountdown = Duration(seconds: 6);

  /// The engine has no clock of its own; it reads one. Injectable so the
  /// widget tests can drive the countdown (and drive it *backwards*) without
  /// waiting on wall time.
  final DateTime Function() _clock;
  DateTime now() => _clock();

  final DateTime _startedAt;
  DateTime? _finalDeadline;
  Duration _lastRemaining = initialRemaining;

  /// Remaining race time at [now]. Decreases in real time, is floored at
  /// [clockFloor] until the final beat, and is **never re-pinned upward** — a
  /// backwards wall clock holds the value rather than raising it.
  Duration remainingAt(DateTime now) {
    Duration remaining;
    if (_completed) {
      remaining = Duration.zero;
    } else if (_finalDeadline != null) {
      final left = _finalDeadline!.difference(now);
      remaining = left.isNegative ? Duration.zero : left;
    } else {
      final elapsed = now.difference(_startedAt);
      remaining = initialRemaining - elapsed;
      if (remaining < clockFloor) remaining = clockFloor;
    }
    if (remaining > _lastRemaining) remaining = _lastRemaining;
    _lastRemaining = remaining;
    return remaining;
  }

  /// Lifts the floor and starts the run to 0:00 (beat 8).
  void startFinalCountdown(DateTime now) {
    _finalDeadline ??= now.add(finalCountdown);
    _notify();
  }

  // -- Simulation state -------------------------------------------------------

  late final Map<String, int> _steps;

  // Prologue (the create + invite beats). The demo opens on the REAL create
  // screen, because "make a race and get your friends in it" is the loop the
  // app lives or dies on — a user who only ever learns to open boxes in a race
  // somebody else made never starts one.
  bool _raceCreated = false;
  bool _friendsInvited = false;
  // 7, not 3: the create picker no longer offers a 3-day race, so a demo that
  // defaults to one advertises a length the user cannot choose.
  int _durationDays = 7;
  final List<String> _invitedUserIds = [];

  bool _introAcknowledged = false;
  int _boxesOpened = 0;
  bool _boostUsed = false;
  bool _shieldUsed = false;
  bool _shieldArmed = false;
  bool _attackResolved = false;
  bool _attackAcknowledged = false;
  bool _shortcutUsed = false;
  bool _completed = false;

  /// Slot rows, in render order. Row ids are stable across the whole demo: a
  /// box row *becomes* the powerup it rolled, exactly as the server's does.
  late final List<Map<String, dynamic>> _inventory = [
    for (final id in mysteryBoxIds) {'id': id, 'status': 'MYSTERY_BOX'},
  ];

  /// The reel owns the pending boundary: a roll is authoritative once
  /// requested, but the visible inventory stays a box until reveal.
  final Map<String, Map<String, dynamic>> _pendingRolls = {};

  final List<Map<String, dynamic>> _activity = [];

  /// Fired whenever the engine's state changes, so the host can rebuild.
  void Function()? onChanged;

  /// Fired with an activation event name for the three actions that are the
  /// point of the exercise (spec §5.9): `demo_box_opened`, `demo_powerup_used`
  /// and `demo_won`. The host records them through a REAL api service — an
  /// event emitted through the demo service would carry a fabricated raceId.
  void Function(String eventName)? onDemoEvent;

  void _notify() => onChanged?.call();

  bool get isCompleted => _completed;
  bool get shieldArmed => _shieldArmed;
  bool get attackResolved => _attackResolved;
  bool get raceCreated => _raceCreated;
  bool get friendsInvited => _friendsInvited;
  int get durationDays => _durationDays;
  int get openedBoxCount => _boxesOpened;
  List<String> get pendingBoxIds => List.unmodifiable(_pendingRolls.keys);

  /// The demo race's app-funded pool, computed with the SAME mirrored formula
  /// the create screen previews with, so the tutorial never shows the user two
  /// different numbers for one race.
  int get _demoPrizePool => computePrizePool(
    playerCount: participants.length,
    durationDays: _durationDays,
  );
  List<String> get invitedUserIds => List.unmodifiable(_invitedUserIds);

  /// The three rivals, in the shape `RaceInviteScreen` reads (`id` /
  /// `displayName` / `profilePhotoUrl`). They are presented as friends the user
  /// already has, so the prologue teaches the invite step without also having
  /// to teach friending.
  static const List<Map<String, dynamic>> demoFriends = [
    {
      'id': rivalLeaderUserId,
      'displayName': rivalLeaderName,
      'profilePhotoUrl': null,
    },
    {
      'id': 'demo-jordan',
      'displayName': rivalSecondName,
      'profilePhotoUrl': null,
    },
    {
      'id': 'demo-priya',
      'displayName': rivalThirdName,
      'profilePhotoUrl': null,
    },
  ];

  /// Beat 1 is satisfied: the user created the race. [durationDays] is whatever
  /// they picked and is echoed back in the coach copy — the demo race itself is
  /// always the scripted two minutes.
  void markRaceCreated({int? durationDays}) {
    if (_raceCreated) return;
    _raceCreated = true;
    if (durationDays != null) _durationDays = durationDays;
    _notify();
  }

  /// Beat 2 is satisfied: invites went out. Selecting nobody still advances —
  /// the lesson landed, and stranding a user on a screen they've decided to
  /// leave is worse than a slightly weaker demo.
  void markFriendsInvited(List<String> userIds) {
    if (_friendsInvited) return;
    _friendsInvited = true;
    _invitedUserIds
      ..clear()
      ..addAll(userIds);
    _notify();
  }

  /// Jumps straight to the race. Used by the tests that are about the race
  /// itself, and by any caller that has already run the prologue.
  void skipPrologue() {
    _raceCreated = true;
    _friendsInvited = true;
    _notify();
  }

  // -- Beats (state-driven, §5.7b) --------------------------------------------

  /// The live beat, derived from state rather than from a tap counter. The
  /// coach shows the first goal that is not yet satisfied, so a user who
  /// wanders — or who satisfies a later goal early — never dead-ends.
  DemoBeat get beat {
    if (_completed) return DemoBeat.win;
    if (!_raceCreated) return DemoBeat.createRace;
    if (!_friendsInvited) return DemoBeat.inviteFriends;
    if (!_introAcknowledged) return DemoBeat.intro;
    if (_boxesOpened < 1) return DemoBeat.openBox;
    if (!_boostUsed) return DemoBeat.useBoost;
    if (_boxesOpened < 2) return DemoBeat.openSecondBox;
    if (!_shieldUsed) return DemoBeat.useShield;
    if (!_attackResolved || !_attackAcknowledged) return DemoBeat.blockedAttack;
    if (_boxesOpened < 3) return DemoBeat.openThirdBox;
    if (!_shortcutUsed) return DemoBeat.useShortcut;
    return DemoBeat.finish;
  }

  /// Whether tapping this tray item is what the CURRENT beat is teaching.
  ///
  /// Consulted only by the host's tap gate. [beat] itself stays deliberately
  /// order-tolerant — it reports the first unsatisfied goal, so state that
  /// arrives early can never dead-end the script. This is the separate
  /// question of whether we should let the tap happen at all, and it exists
  /// because "open the second box" was reachable while the coach was asking
  /// for the Protein Shake, which silently skipped that lesson.
  ///
  /// Card-driven beats (intro, the blocked attack, the final clock) return
  /// false for everything: the tray is not the lesson there, and the coach
  /// always carries a CTA, so blocking cannot strand anyone.
  bool isOnScriptTap({required bool isMysteryBox, String? type}) =>
      switch (beat) {
        DemoBeat.openBox ||
        DemoBeat.openSecondBox ||
        DemoBeat.openThirdBox => isMysteryBox,
        DemoBeat.useBoost => !isMysteryBox && type == 'PROTEIN_SHAKE',
        DemoBeat.useShield => !isMysteryBox && type == 'COMPRESSION_SOCKS',
        DemoBeat.useShortcut => !isMysteryBox && type == 'SHORTCUT',
        // The prologue beats do not render the tray at all.
        DemoBeat.createRace ||
        DemoBeat.inviteFriends ||
        DemoBeat.intro ||
        DemoBeat.blockedAttack ||
        DemoBeat.finish ||
        DemoBeat.win => false,
      };

  void acknowledgeIntro() {
    if (_introAcknowledged) return;
    _introAcknowledged = true;
    _notify();
  }

  void acknowledgeAttack() {
    if (_attackAcknowledged) return;
    _attackAcknowledged = true;
    _notify();
  }

  // -- Rival drift (§5.4) -----------------------------------------------------
  // Scripted per beat, not per second, so the outcome is identical no matter
  // how long the user takes. Standings are never frozen; the clock is not what
  // moves them.

  static const Map<String, int> _driftPerBeat = {
    rivalLeaderUserId: 100,
    'demo-jordan': 70,
    'demo-priya': 50,
  };

  void _applyDrift() {
    _driftPerBeat.forEach((userId, amount) {
      _steps[userId] = (_steps[userId] ?? 0) + amount;
    });
  }

  // -- Actions ----------------------------------------------------------------

  /// Begins a mystery-box roll. Scripted by **open order**, not by slot id, so
  /// a user who taps the second box first still gets the boost first. The
  /// visible inventory is untouched until [commitBoxOpen].
  Map<String, dynamic> openBox(String powerupId) {
    final row = _rowFor(powerupId);
    final existing = _pendingRolls[powerupId];
    if (existing != null) {
      return {'result': Map<String, dynamic>.from(existing)};
    }

    if (row == null || row['status'] != 'MYSTERY_BOX') {
      return {
        'result': {
          'powerupId': powerupId,
          'type': null,
          'rarity': 'COMMON',
          'autoActivated': false,
          'coinsSpent': 0,
        },
      };
    }

    final type =
        boxRollOrder[(_boxesOpened + _pendingRolls.length).clamp(
          0,
          boxRollOrder.length - 1,
        )];
    final roll = <String, dynamic>{
      'powerupId': powerupId,
      'type': type,
      'rarity': 'COMMON',
      'autoActivated': false,
      'coinsSpent': 0,
    };
    _pendingRolls[powerupId] = roll;
    return {'result': Map<String, dynamic>.from(roll)};
  }

  /// Commits a pending roll exactly once at the reel's reveal boundary.
  /// Duplicate reveals and stale callbacks after cancellation are safe no-ops.
  void commitBoxOpen(String powerupId) {
    final roll = _pendingRolls.remove(powerupId);
    if (roll == null) return;
    final row = _rowFor(powerupId);
    if (row == null || row['status'] != 'MYSTERY_BOX') return;

    final type = roll['type'];
    final typeName = type is String && type.isNotEmpty ? type : 'POWERUP';
    if (type is String && type.isNotEmpty) {
      row['type'] = type;
    }
    row['rarity'] = roll['rarity'];
    row['status'] = 'HELD';
    _boxesOpened += 1;
    _applyDrift();
    onDemoEvent?.call('demo_box_opened');
    _activity.insert(0, {
      'id': 'demo-sys-box-$_boxesOpened',
      'kind': 'SYSTEM',
      'eventType': 'MYSTERY_BOX_OPENED',
      'powerupType': typeName,
      'body': 'You opened a mystery box and found ${_articleFor(typeName)}!',
      'actorUserId': myUserId,
      'createdAt': DateTime.now().toIso8601String(),
    });
    _notify();
  }

  /// Aborts a pending roll without advancing the tutorial.
  void cancelBoxOpen(String powerupId) {
    if (_pendingRolls.remove(powerupId) != null) {
      _notify();
    }
  }

  /// Uses a held powerup. Returns the shape `_usePowerup` reads defensively:
  /// `result.coinsSpent` plus the `outcome` / `blocked` / `reflected`
  /// discriminators (§6.4).
  Map<String, dynamic> usePowerup({
    required String powerupId,
    String? targetUserId,
  }) {
    final row = _rowFor(powerupId);
    final type = row?['type'] as String?;
    var stepsStolen = 0;

    if (row != null && row['status'] == 'HELD') {
      _inventory.removeWhere((p) => p['id'] == powerupId);
      switch (type) {
        case 'PROTEIN_SHAKE':
          _steps[myUserId] = (_steps[myUserId] ?? 0) + 1500;
          _boostUsed = true;
          _applyDrift();
          _pushActivity(
            'POWERUP_USED',
            type!,
            'You chugged a Protein Shake for +1,500 steps.',
          );
        case 'COMPRESSION_SOCKS':
          _shieldUsed = true;
          _shieldArmed = true;
          _applyDrift();
          _pushActivity(
            'POWERUP_USED',
            type!,
            'You pulled on Compression Socks. Shielded from the next attack.',
          );
        case 'SHORTCUT':
          stepsStolen = _resolveShortcutSteal(targetUserId);
          _shortcutUsed = true;
          _pushActivity(
            'POWERUP_USED',
            type!,
            'You took a Shortcut and stole '
                '${_formatSteps(stepsStolen)} steps.',
          );
      }
      if (type != null) onDemoEvent?.call('demo_powerup_used');
      _notify();
    }

    return {
      'result': {
        'powerupId': powerupId,
        'type': type,
        'coinsSpent': 0,
        'outcome': 'APPLIED',
        'blocked': false,
        'reflected': false,
        if (type == 'SHORTCUT') 'stepsStolen': stepsStolen,
      },
    };
  }

  /// Beat 6: the scripted rival Shortcut. Resolves through the REAL `blocked`
  /// outcome path the screen already renders, so the demo teaches a real UI
  /// state rather than a bespoke one.
  Map<String, dynamic> resolveScriptedAttack() {
    if (!_attackResolved) {
      _attackResolved = true;
      _shieldArmed = false;
      _applyDrift();
      _activity.insert(0, {
        'id': 'demo-sys-attack',
        'kind': 'SYSTEM',
        'eventType': 'POWERUP_USED',
        'powerupType': 'SHORTCUT',
        'body':
            '$rivalLeaderName tried to steal 1,000 steps from you. '
            'Blocked!',
        'actorUserId': rivalLeaderUserId,
        'targetUserId': myUserId,
        'createdAt': DateTime.now().toIso8601String(),
      });
      _notify();
    }
    return {
      'result': {
        'type': 'SHORTCUT',
        'coinsSpent': 0,
        'outcome': 'BLOCKED',
        'blocked': true,
        'reflected': false,
        'actorUserId': rivalLeaderUserId,
        'actorDisplayName': rivalLeaderName,
        'targetUserId': myUserId,
      },
    };
  }

  /// Ends the race with the user in 1st. Called by the host once the final
  /// countdown has run out.
  void completeRace() {
    if (_completed) return;
    _ensureLead();
    _completed = true;
    onDemoEvent?.call('demo_won');
    _notify();
  }

  // -- Derived views ----------------------------------------------------------

  int stepsFor(String userId) => _steps[userId] ?? 0;

  /// Standings, highest first. Ties are broken by user id so two runs of the
  /// same script always produce byte-identical output.
  List<Map<String, dynamic>> get participants {
    final entries = _steps.entries.toList()
      ..sort((a, b) {
        final bySteps = b.value.compareTo(a.value);
        return bySteps != 0 ? bySteps : a.key.compareTo(b.key);
      });
    return [
      for (final e in entries)
        {
          'userId': e.key,
          'displayName': _nameFor(e.key),
          'totalSteps': e.value,
          'profilePhotoUrl': null,
          'accessories': e.key == myUserId
              ? myAccessories
              : const <Map<String, dynamic>>[],
          'status': 'ACCEPTED',
          'finishedAt': null,
          'stealthed': false,
        },
    ];
  }

  int get myPlacement {
    final ordered = participants;
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i]['userId'] == myUserId) return i + 1;
    }
    return ordered.length;
  }

  // -- Wire shapes (§6.4) -----------------------------------------------------

  /// [now] drives the simulation clock; [wallNow] anchors `endsAt` to the
  /// device's wall clock, because that is what the screen's own 1s countdown
  /// subtracts from. In production the two are the same instant.
  Map<String, dynamic> raceDetails(DateTime now, {DateTime? wallNow}) {
    return {
      'id': raceId,
      'name': raceName,
      'status': _completed ? 'COMPLETED' : 'ACTIVE',
      'myStatus': 'ACCEPTED',
      // Deliberately NOT the creator, even though the prologue had the user
      // create it: `isCreator` unlocks cancel / kick / edit-settings on the
      // real screen, and every one of those is a way to delete the race the
      // tutorial is standing in.
      'isCreator': false,
      'tournamentId': null,
      'maxDurationDays': _durationDays,
      'buyInAmount': 0,
      'payoutPreset': 'TOP3_70_20_10',
      'projectedPotCoins': _demoPrizePool,
      'prizePool': {
        'coins': _demoPrizePool,
        'projected': !_completed,
        'atMax': false,
        'playerCount': participants.length,
        'durationDays': _durationDays,
        // The REAL mirrored band table (models/race_prize_pool.dart), not a
        // local `<=1 ? 1 : 2` fork. The fork disagreed hardest at 7 and 14 —
        // exactly the durations the picker now offers — so the create plaque
        // and the demo race's scorecard showed two different pools for the
        // same race inside one tutorial (timeline spec §10.1 risk 4).
        'durationPoints': prizePoolDurationPoints(_durationDays),
        'coinUnit': kPrizeCoinUnit,
        'maxCoins': kPrizePoolMaxCoins,
        'funded': true,
      },
      // Derived from the pool above so the podium adds up to what the
      // scorecard promises (TOP3_70_20_10).
      'payoutTiers': [
        {'placement': 1, 'amount': (_demoPrizePool * 70) ~/ 100},
        {'placement': 2, 'amount': (_demoPrizePool * 20) ~/ 100},
        {'placement': 3, 'amount': (_demoPrizePool * 10) ~/ 100},
      ],
      'startedAt': _startedAt.toIso8601String(),
      'endsAt': (wallNow ?? now).add(remainingAt(now)).toIso8601String(),
      'myPlacementAlertsMuted': false,
      'myChatMuted': false,
      'participants': participants,
      if (_completed)
        'winner': {
          'userId': myUserId,
          'displayName': myDisplayName,
          'totalSteps': stepsFor(myUserId),
        },
    };
  }

  Map<String, dynamic> raceProgress(DateTime now) {
    return {
      'status': _completed ? 'COMPLETED' : 'ACTIVE',
      'participants': participants,
      'powerupData': {
        'enabled': true,
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'powerupStepInterval': 2000,
        'stepsUntilNextPowerup': 0,
        'inventory': [
          for (final row in _inventory) Map<String, dynamic>.from(row),
        ],
        'activeEffects': [
          if (_shieldArmed)
            {
              'type': 'COMPRESSION_SOCKS',
              'onSelf': true,
              'sourceUserId': myUserId,
              'targetUserId': myUserId,
              'expiresAt': now
                  .add(const Duration(minutes: 30))
                  .toIso8601String(),
            },
        ],
      },
    };
  }

  /// Activity (SYSTEM) and Chat (USER) feeds, newest-first as the live services
  /// expect. The demo has no chat traffic — nothing is ever written anywhere.
  Map<String, dynamic> messages(String? kind) {
    if (kind == 'USER') {
      return const {'messages': [], 'nextCursor': null};
    }
    return {
      'messages': [for (final m in _activity) Map<String, dynamic>.from(m)],
      'nextCursor': null,
    };
  }

  // -- Internals --------------------------------------------------------------

  Map<String, dynamic>? _rowFor(String powerupId) {
    for (final row in _inventory) {
      if (row['id'] == powerupId) return row;
    }
    return null;
  }

  String _nameFor(String userId) {
    if (userId == myUserId) return myDisplayName;
    return const {
      rivalLeaderUserId: rivalLeaderName,
      'demo-jordan': rivalSecondName,
      'demo-priya': rivalThirdName,
    }[userId]!;
  }

  /// Reads out a rolled powerup in the activity feed's voice.
  static String _articleFor(String type) => switch (type) {
    'PROTEIN_SHAKE' => 'a Protein Shake',
    'COMPRESSION_SOCKS' => 'a pair of Compression Socks',
    'SHORTCUT' => 'a Shortcut',
    _ => 'a powerup',
  };

  void _pushActivity(String eventType, String powerupType, String body) {
    _activity.insert(0, {
      'id': 'demo-sys-$powerupType',
      'kind': 'SYSTEM',
      'eventType': eventType,
      'powerupType': powerupType,
      'body': body,
      'actorUserId': myUserId,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// "The Shortcut always steals exactly enough" (§5.2). The base steal is the
  /// shipped 1,000 — which is what it costs the scripted leader — but if the
  /// user picks a different rival it takes whatever it needs, because **no path
  /// loses**.
  int _resolveShortcutSteal(String? targetUserId) {
    final target = targetUserId != null && _steps.containsKey(targetUserId)
        ? targetUserId
        : rivalLeaderUserId;
    final mySteps = _steps[myUserId] ?? 0;

    int maxOtherAfter(int stolen) {
      var best = 0;
      _steps.forEach((userId, steps) {
        if (userId == myUserId) return;
        final after = userId == target ? steps - stolen : steps;
        best = math.max(best, after);
      });
      return best;
    }

    var stolen = 1000;
    if (mySteps + stolen <= maxOtherAfter(stolen)) {
      stolen = maxOtherAfter(stolen) - mySteps + 560;
    }
    stolen = stolen.clamp(0, _steps[target] ?? 0);

    _steps[target] = (_steps[target] ?? 0) - stolen;
    _steps[myUserId] = mySteps + stolen;
    return stolen;
  }

  /// Belt and braces on "the user always wins": if any path somehow left the
  /// user behind, a scripted final surge puts them in front.
  void _ensureLead() {
    var maxOther = 0;
    _steps.forEach((userId, steps) {
      if (userId != myUserId) maxOther = math.max(maxOther, steps);
    });
    if ((_steps[myUserId] ?? 0) <= maxOther) {
      _steps[myUserId] = maxOther + 560;
    }
  }

  static String _formatSteps(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
