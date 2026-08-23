# Step-change popups — requirements

## Summary & user story

When a power-up changes a player's race steps, the affected player should see
the change in that race, with the power-up icon that caused it. A global 2x
steps event affects multiple races, so its aggregate result belongs on Home.
The popup must make the signed amount unmistakable: positive values use a bold
green `+` amount and negative values use a bold red `-` amount.

The popup policy is intentionally selective:

- Incoming debuffs from another player: show in the affected race.
- Runner's High and Ghost Pepper used by the current player: show in the
  affected race when they produce a concrete step change.
- Leech: show for both the victim and the leecher, in their race view.
- Shortcut: show only for the player it is used against, not the player using
  it.
- Protein Shake and other self-only step bonuses that are not explicitly in
  the allowlist: do not show a popup.
- 2x global event: show on Home as `+X steps across all races` (or the signed
  equivalent), using the event icon/logo rather than a race power-up icon.

## Scope / non-goals

In scope:

- Replace the current batched `POWERUP SUMMARY` race modal with one popup per
  eligible step-change notice, preserving the existing acknowledgement and
  retry behavior.
- Add explicit attribution/direction metadata needed to distinguish an
  incoming Shortcut from the caster's positive side and to preserve both sides
  of Leech.
- Render signed, locale-formatted amounts with bold color styling and the
  causing power-up icon.
- Keep the existing Home global-event summary flow, changing its copy and
  amount styling to the requested signed format.
- Cover real race and Home screens through integration/widget tests, including
  old/missing backend fields.

Out of scope:

- Changing scoring, power-up magnitudes, event multipliers, prices, odds, or
  economy rules.
- Showing popups for Protein Shake, passive status-only effects, or arbitrary
  power-up activity without a concrete delta.
- Replacing the existing activity feed or attack interception modal.

## Current implementation evidence

- `lib/screens/race_detail_screen.dart:1241` fetches recipient-private active
  impact notices, currently folds all notices into one summary and uses the
  first power-up icon.
- `lib/screens/race_detail_screen.dart:1303` currently formats amounts as
  plain text and uses a single `showPowerupRevealModal` call.
- `lib/screens/main_shell.dart:3072` presents the existing global 2x summary
  on Home, with plain body text and copy that says “extra race steps”.
- `lib/services/backend_api_service.dart:2104` defensively reads the additive
  active-impact endpoint.
- `5c29e2c` introduced the batched race summary and resolved-impact baseline;
  this feature refines that work rather than creating a second notification
  system.
- Backend `src/modules/races/models/raceImpactEvent.js` already persists
  recipient-level `deltaSteps`, `powerupType`, and `sourceId`; Shortcut writes
  both a victim negative delta and caster positive delta, while Leech writes
  both sides through its transfer path.

## Proposed API contract

Prefer additive fields on the existing active-impact response. Existing app
versions ignore unknown fields and continue to receive the current summary
behavior.

Each eligible notice may add:

```json
{
  "id": "impact:<uuid>",
  "powerupType": "SHORTCUT",
  "deltaSteps": -1500,
  "description": "You lost 1,500 steps to Shortcut.",
  "sourceDirection": "INCOMING",
  "sourceUserId": "opaque-user-id",
  "popupPolicy": "RACE_POWERUP",
  "resolvedAt": "2026-08-23T18:00:00.000Z",
  "valueStatus": "SYNCED_SNAPSHOT"
}
```

`sourceDirection` and `popupPolicy` are additive and optional for old rows.
The frontend must safely fall back to the existing type/delta policy when they
are absent. No existing endpoint parameters become required. A missing or
malformed field suppresses only the specialized popup, never the race screen.

The Home batch's existing `globalEventSummary` remains additive-compatible:

```json
{
  "id": "summary-id",
  "extraRaceSteps": 1500,
  "raceCount": 3,
  "popupPolicy": "GLOBAL_STEP_EVENT",
  "eventType": "DOUBLE_STEPS"
}
```

The old `extraRaceSteps` and `raceCount` fields remain authoritative for old
clients. No migration is required unless the backend review finds that event
type/source metadata cannot be derived safely from existing rows.

## Frontend plan

1. Add a small shared signed-step amount widget that formats absolute values
   with locale separators, includes the sign, and uses bold green for positive
   and bold red for negative values.
2. Extend the race notice parser defensively with direction/policy fields.
3. Filter notices through an explicit allowlist. Incoming targeted debuffs and
   Leech are eligible; Shortcut caster-positive rows and Protein Shake are not.
   Runner's High/Ghost Pepper are eligible only when the backend supplies a
   concrete resolved delta attributable to that activation.
4. Present each eligible race notice separately, with its own icon and signed
   amount. Acknowledge each notice only after its popup completes.
5. Update Home's global summary to use the signed amount widget and copy such
   as `+1,500 steps across all races.` Preserve the existing queueing,
   acknowledgement, and Home-only eligibility guards.
6. Keep demo/tutorial services returning empty notices and ensure both iOS and
   Android use the same Dart rendering path.

## Backend plan

1. Review the existing direct and settlement attribution paths for the exact
   allowlist and direction metadata.
2. Add only additive projection fields or filtering needed to identify the
   policy. Do not change scoring or issue new required request parameters.
3. Add integration coverage against a dedicated test database for targeted
   debuffs, Shortcut both recipients, Leech both recipients, self-bonus
   exclusions, Runner's High/Ghost Pepper attribution, and global 2x summary.

## Test-first plan

Frontend:

- Real `RaceDetailScreen`: one popup per eligible notice, correct icon, signed
  amount, color/weight, and per-notice acknowledgement.
- Race screen: incoming Shortcut appears; Shortcut caster positive row does not.
- Race screen: Leech appears for both recipient directions.
- Race screen: Protein Shake does not appear.
- Race screen: malformed/missing additive metadata degrades safely.
- Home: positive and negative global summaries use signed bold styling and
  `across all races` copy; queueing while off Home remains intact.

Backend:

- Integration tests assert the actual HTTP payload and recipient visibility for
  every allowlisted/excluded power-up case.
- Existing older-client response shape remains valid.

## Backward compatibility & rollout

Backend changes deploy first. Older app versions continue using the existing
summary modal and ignore additive fields. The new app treats missing fields as
legacy data and uses safe type/delta defaults. No release flag is proposed.
The carrying iOS and Android builds must ship together; no new asset is needed
because existing power-up icons are already bundled.

## Acceptance criteria / definition of done

- Every eligible concrete race step delta appears in its race with the correct
  icon and one popup per notice.
- Excluded self bonuses never appear; Shortcut is victim-only; Leech is shown
  on both sides.
- Global 2x summaries appear only on Home and say `+X steps across all races`
  or the signed equivalent.
- Positive amounts are bold green with `+`; negative amounts are bold red with
  `-`; zero/malformed deltas do not render.
- Old backend responses and old app versions remain safe.
- Tests are written first and pass, `flutter analyze` is clean, backend unit
  and integration tests pass against a test database, both platforms are
  accounted for, and the required review/manual UI checklist is complete.

## Decisions recorded

- Runner's High and Ghost Pepper show only when a concrete resolved step delta
  exists; activation alone does not invent a number.
- Leech shows the exact signed transfer amount to both players in separate
  popups.
- Multiple eligible changes appear one at a time, preserving per-notice
  acknowledgement.

## Manual UI-placement test plan

The required manual review must cover real Race Detail, Home, demo
race tutorial, tab tutorial previews, and any hand-forked effect/summary copy.

## Revision log

- Draft 1: separated race-local impact delivery from the Home global summary;
  recorded the current batched-summary implementation and existing backend
  attribution fields.
- Gap pass 1: added explicit inclusion/exclusion policy, direction metadata,
  legacy fallback behavior, per-notice acknowledgement, and the distinction
  between activation effects and concrete deltas.
- Gap pass 2: added older-client compatibility, both-platform requirements,
  test-database integration coverage, and unresolved UX questions for approval.
- Decision pass: resolved the three UX questions in favor of concrete resolved
  deltas, exact signed Leech transfers, and sequential per-notice popups.
