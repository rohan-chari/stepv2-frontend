/// The demo race's scripted beat list (spec §5.3).
///
/// Kept separate from the engine so the *copy* and the *simulation* can be read
/// (and reviewed) independently. Nothing here is random: every beat, every
/// number and every powerup is fixed, because a tutorial the user can lose
/// teaches them they are bad at the game.
library;

/// One beat of the demo. Beats are **state-driven, not sequence-driven**
/// (spec §5.7b): the engine derives the live beat from its own state, so a user
/// who wanders — or who opens both boxes at once — still lands on a reachable
/// beat instead of dead-ending the script.
enum DemoBeat {
  /// 1 — orientation. Waits for a tap on the coach card.
  intro,

  /// 2 — open the first mystery box.
  openBox,

  /// 3 — use the Protein Shake that box rolled.
  useBoost,

  /// 4 — open the second mystery box.
  openSecondBox,

  /// 5 — use the Compression Socks (shield) before the attack lands.
  useShield,

  /// 6 — no tap: the scripted rival Shortcut resolves as `blocked`.
  blockedAttack,

  /// 7 — use the Shortcut on a rival through the REAL target picker.
  useShortcut,

  /// 8 — the clock runs out.
  finish,

  /// 9 — the win card.
  win,
}

extension DemoBeatX on DemoBeat {
  /// 1-indexed beat number. Doubles as the activation-telemetry `step` value,
  /// which is a **decimal string** on the wire (spec §5.9 / F7).
  int get number => index + 1;

  String get stepValue => '$number';
}

/// Coach-mark copy, keyed by beat. Beat 8 has no card (the clock is the beat)
/// and beat 9 is the win card, which the host renders itself.
const Map<DemoBeat, ({String title, String body, String? cta})> kDemoBeatCopy = {
  DemoBeat.intro: (
    title: '2 minutes left.',
    body: "You're in 2nd. Let's fix that.",
    cta: "LET'S GO",
  ),
  DemoBeat.openBox: (
    title: 'Walking earns mystery boxes.',
    body: 'Tap a box to open it.',
    cta: null,
  ),
  DemoBeat.useBoost: (
    title: 'Boosts add steps.',
    body: 'Tap your Protein Shake, then USE.',
    cta: null,
  ),
  DemoBeat.openSecondBox: (
    title: 'One box left.',
    body: 'Open it.',
    cta: null,
  ),
  DemoBeat.useShield: (
    title: "Sam's coming for you.",
    body: 'Shield up — tap the Compression Socks.',
    cta: null,
  ),
  DemoBeat.blockedAttack: (
    title: 'Blocked!',
    body: 'Sam tried to steal 1,000 steps. Your shield ate it.',
    cta: 'NICE',
  ),
  DemoBeat.useShortcut: (
    title: 'Now take the lead.',
    body: 'Tap your Shortcut and pick Sam.',
    cta: null,
  ),
  DemoBeat.finish: (title: 'Hang on…', body: 'The clock is running out.', cta: null),
  DemoBeat.win: (title: 'YOU WIN', body: 'That is the whole game.', cta: 'CONTINUE'),
};

/// Which part of the real screen the coach mark points at for a given beat.
/// Anchored to **stable layout containers** (spec §8.5 option 1), never to an
/// individual animating chip.
enum DemoAnchor {
  /// No anchor — a centred card (beats 1, 6, 8, 9).
  none,

  /// The POWERUPS block (the inventory tray), which holds both the boxes and
  /// the held powerups. It does not move while the demo runs.
  powerups,

  /// The countdown chip in the race hero header. Beat 8's whole lesson is that
  /// the clock is the thing that ends a race, so that beat scrolls back to the
  /// top and puts the mark on the timer rather than leaving the user staring at
  /// a powerup tray while the race runs out underneath them.
  clock,
}

const Map<DemoBeat, DemoAnchor> kDemoBeatAnchor = {
  DemoBeat.intro: DemoAnchor.none,
  DemoBeat.openBox: DemoAnchor.powerups,
  DemoBeat.useBoost: DemoAnchor.powerups,
  DemoBeat.openSecondBox: DemoAnchor.powerups,
  DemoBeat.useShield: DemoAnchor.powerups,
  DemoBeat.blockedAttack: DemoAnchor.none,
  DemoBeat.useShortcut: DemoAnchor.powerups,
  DemoBeat.finish: DemoAnchor.clock,
  DemoBeat.win: DemoAnchor.none,
};
