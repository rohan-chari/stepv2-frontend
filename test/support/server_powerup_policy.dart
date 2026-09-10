import 'package:step_tracker/constants/powerup_copy.dart';

// Explicit backend fixture for screens whose scenario includes paid upgrades.
const serverUpgradeTierFixture = {
  'PROTEIN_SHAKE': [
    '+1,500 steps',
    '+2,250 steps',
    '+3,000 steps',
    '+4,500 steps',
  ],
  'SHORTCUT': [
    'Steal up to 1,000 steps',
    'Steal up to 1,500 steps',
    'Steal up to 2,000 steps',
    'Steal up to 3,000 steps',
  ],
  // 2026-08-15: joined the 15-min upgrade ladder (was 3/4/5/7h here, never
  // matched the backend's real 1/2/3/4h ladder either).
  'DETOUR_SIGN': [
    'Hide leaderboard 1h',
    'Hide leaderboard 1h 15m',
    'Hide leaderboard 1h 30m',
    'Hide leaderboard 1h 45m',
  ],
  'TRAIL_MIX': [
    '+100 steps per unique type',
    '+150 steps per unique type',
    '+200 steps per unique type',
    '+300 steps per unique type',
  ],
  // 2026-08-15: joined the 15-min upgrade ladder (was 3/4/5/7h here, never
  // matched the backend's real 1/2/3/4h ladder either).
  'RUNNERS_HIGH': [
    '2x for 1h',
    '2x for 1h 15m',
    '2x for 1h 30m',
    '2x for 1h 45m',
  ],
  // Item 1 — each upgrade adds 15 minutes on top of the 1h base.
  'LEG_CRAMP': ['Freeze 1h', 'Freeze 1h 15m', 'Freeze 1h 30m', 'Freeze 1h 45m'],
  // 2026-08-15: joined the 15-min upgrade ladder (was 4/5/6.5/8h here
  // originally, then fixed to the old 1/2/3/4h ladder — now stale again).
  'STEALTH_MODE': ['Hide 1h', 'Hide 1h 15m', 'Hide 1h 30m', 'Hide 1h 45m'],
  'WRONG_TURN': [
    'Reverse 1h',
    'Reverse 1h 15m',
    'Reverse 1h 30m',
    'Reverse 1h 45m',
  ],
  'COMPRESSION_SOCKS': ['Shield 24h', 'Shield 30h', 'Shield 36h', 'Shield 48h'],
  // LUCKY_HORSESHOE deliberately has NO bundled ladder (batch 2026-08-09
  // item 8b): it now guarantees a rare at every level, so the upgrade UI —
  // which this map gates via `isUpgradeable` — is hidden in this build. The
  // type stays in the backend's `upgradeableTypes` with zeroed costs so
  // frozen binaries that still offer L1-3 don't hit a permanent 400, and a
  // backend that still serves a ladder still overrides this omission.
  'CAMPFIRE_REST': ['2.25x boost', '2.5x boost', '2.75x boost', '3x boost'],
  'TRAIL_MAGNET': [
    'Box 1,000 steps closer',
    'Box 1,500 steps closer',
    'Box 2,000 steps closer',
    'Box 3,000 steps closer',
  ],
  'POCKET_WATCH': ['Extend 1h', 'Extend 1.5h', 'Extend 2h', 'Extend 3h'],
  'TRAIL_MINE': ['3% penalty', '5% penalty', '8% penalty', '12% penalty'],
  'PINECONE_TOSS': [
    '-750 steps',
    '-1,000 steps',
    '-1,500 steps',
    '-2,250 steps',
  ],
};
Future<void> seedServerPowerupPolicy() async {
  PowerupCopy.resetForTest();
  await PowerupCopy.refresh(
    fetch: () async => {
      'version': 'test-server-policy',
      'powerups': [
        for (final row in serverUpgradeTierFixture.entries)
          {
            'type': row.key,
            'name': PowerupCopy.nameFor(row.key),
            'description': PowerupCopy.descriptionFor(row.key),
            'upgradeTierLabels': row.value,
          },
      ],
    },
  );
}
