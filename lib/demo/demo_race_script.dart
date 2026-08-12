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
  /// 1 — make the race, on the REAL create screen. Waits for CREATE RACE.
  createRace,

  /// 2 — invite the three rivals, through the REAL invite screen.
  inviteFriends,

  /// 3 — orientation. Waits for a tap on the coach card.
  intro,

  /// 4 — open the first mystery box.
  openBox,

  /// 5 — use the Protein Shake that box rolled.
  useBoost,

  /// 6 — open the second mystery box.
  openSecondBox,

  /// 7 — use the Compression Socks (shield) before the attack lands.
  useShield,

  /// 8 — no tap: the scripted rival Shortcut resolves as `blocked`.
  blockedAttack,

  /// 9 — open the third mystery box, which rolls the Shortcut.
  ///
  /// The Shortcut used to start in the tray pre-owned, which quietly taught the
  /// wrong lesson: the attack powerup a user actually cares about is something
  /// you *find*, and finding it is the loop the demo exists to sell.
  openThirdBox,

  /// 10 — use the Shortcut on a rival through the REAL target picker.
  useShortcut,

  /// 11 — the clock runs out.
  finish,

  /// 12 — the win card.
  win,
}

/// How many beats the coach counts through ("STEP 3 OF 10").
final int kDemoBeatCount = DemoBeat.values.length;

extension DemoBeatX on DemoBeat {
  /// 1-indexed beat number. Doubles as the activation-telemetry `step` value,
  /// which is a **decimal string** on the wire (spec §5.9 / F7).
  int get number => index + 1;

  String get stepValue => '$number';
}

/// The demo rivals' display names.
///
/// They live HERE, not on the engine, because the coach copy below names them
/// and the engine already imports this file — putting them on the engine would
/// make the dependency circular. `DemoRaceEngine` re-exports them so callers
/// keep using `DemoRaceEngine.rivalLeaderName`.
///
/// They are bots on purpose: this is a scripted race against no one, and
/// human-looking names read as real friends the user doesn't recognise. One per
/// playable animal. Interpolate them into the copy rather than repeating the
/// literal — the previous copy hardcoded "Sam" in three places, which is
/// exactly how a rename leaves the coach naming a rival who no longer exists.
const String demoRivalLeaderName = 'CapyBot';
const String demoRivalSecondName = 'CorgiBot';
const String demoRivalThirdName = 'TurtleBot';

/// Coach-mark copy, keyed by beat. The last beat is the win card, which the
/// host renders itself.
const Map<DemoBeat, ({String title, String body, String? cta})> kDemoBeatCopy =
    {
      DemoBeat.createRace: (
        title: 'Every race starts here.',
        body: 'Pick how long yours runs, then hit CREATE RACE.',
        cta: null,
      ),
      DemoBeat.inviteFriends: (
        title: 'A race needs rivals.',
        body: 'Tap all three friends, then send the invites.',
        cta: null,
      ),
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
        title: 'Two boxes left.',
        body: 'Open the next one.',
        cta: null,
      ),
      DemoBeat.useShield: (
        title: '$demoRivalLeaderName is coming for you.',
        body: 'Shield up. Tap the Compression Socks.',
        cta: null,
      ),
      DemoBeat.blockedAttack: (
        title: 'Blocked!',
        body:
            '$demoRivalLeaderName tried to steal 1,000 steps. '
            'Your shield blocked it.',
        cta: 'NICE',
      ),
      DemoBeat.openThirdBox: (
        title: 'One box left.',
        body: 'Open it. Walking keeps them coming.',
        cta: null,
      ),
      DemoBeat.useShortcut: (
        title: 'A Shortcut. Now take the lead.',
        body: 'Tap it and pick $demoRivalLeaderName. It steals their steps.',
        cta: null,
      ),
      DemoBeat.finish: (
        title: 'Hang on…',
        body: 'The clock is running out.',
        cta: null,
      ),
      DemoBeat.win: (
        title: 'YOU WIN',
        body: 'That is the whole game.',
        cta: 'CONTINUE',
      ),
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

  /// The CREATE RACE button on the real create screen. The duration row sits
  /// directly above it, so marking the button alone keeps both in view without
  /// two rings competing on one screen.
  createButton,

  /// The countdown chip in the race hero header. Beat 8's whole lesson is that
  /// the clock is the thing that ends a race, so that beat scrolls back to the
  /// top and puts the mark on the timer rather than leaving the user staring at
  /// a powerup tray while the race runs out underneath them.
  clock,
}

const Map<DemoBeat, DemoAnchor> kDemoBeatAnchor = {
  DemoBeat.createRace: DemoAnchor.createButton,
  DemoBeat.inviteFriends: DemoAnchor.none,
  DemoBeat.intro: DemoAnchor.none,
  DemoBeat.openBox: DemoAnchor.powerups,
  DemoBeat.useBoost: DemoAnchor.powerups,
  DemoBeat.openSecondBox: DemoAnchor.powerups,
  DemoBeat.useShield: DemoAnchor.powerups,
  DemoBeat.blockedAttack: DemoAnchor.none,
  DemoBeat.openThirdBox: DemoAnchor.powerups,
  DemoBeat.useShortcut: DemoAnchor.powerups,
  DemoBeat.finish: DemoAnchor.clock,
  DemoBeat.win: DemoAnchor.none,
};
