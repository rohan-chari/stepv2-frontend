# Feature batch 2026-08-09 — requirements

Eleven user-reported items. Two are investigation-only (items 4, 5 — findings
recorded here, no code change). The other nine change code. Backend repo:
`/Users/rohan/repos/stepv2-backend` (paths below shortened to `BE/` and `FE/`).

Status: DRAFT — pending user interview answers + architect/game-analyst review.

---

## Item 1 — Nerf Wrong Turn & Leg Cramp upgrade durations

**User story:** 4-hour Wrong Turn / Leg Cramp is oppressive. Base stays 1h;
each upgrade adds **15 minutes** instead of 1 hour.

**Current state:** `BE/src/modules/powerups/powerupUpgrades.js:35-45` —
`LEG_CRAMP: [1h, 2h, 3h, 4h]`, `WRONG_TURN: [1h, 2h, 3h, 4h]`. Durations are
deliberately NOT balance config (file comment lines 14-18); they are stamped
into the effect row (`expiresAt`) at use time, so all app versions get the new
values instantly on deploy and in-flight effects are untouched.

**Change:**
1. `powerupUpgrades.js:36` and `:41` → `[1h, 1h15m, 1h30m, 1h45m]`
   (`[3600000, 4500000, 5400000, 6300000]` ms).
2. Copy seed `BE/src/modules/powerups/constants/powerupCopySeed.js:32-34`
   (LEG_CRAMP tiers) and `:99-106` (WRONG_TURN tiers) → "Freeze 1h / 1h 15m /
   1h 30m / 1h 45m", "Reverse …". Re-run `prisma/seed.js` (idempotent upsert)
   per environment after deploy; catalog is Redis-cached 60s.
3. Feed/push duration text: `notificationHandlers.js:743-753`
   (`attackWindowText`) currently renders non-integer hours as "75 minutes".
   Define ONE shared formatter with target format "1h 15m" and use it from
   both `usePowerup.js:354-357` (`hoursText`) and the notification handler —
   do not fix each site independently. (Architect REQUIRED-adjacent.)
4. Frontend bundled fallbacks (already stale today):
   `FE/lib/constants/powerup_copy.dart:415` (LEG_CRAMP says "2 hours" → "1
   hour"), `:543` (`['Freeze 2h','Freeze 3h','Freeze 4h','Freeze 6h']` →
   `['Freeze 1h','Freeze 1h 15m','Freeze 1h 30m','Freeze 1h 45m']`), `:545`
   (WRONG_TURN ladder), and while here `:544` STEALTH_MODE (stale `4/5/6.5/8h`
   → real `1/2/3/4h`).
5. Hand-maintained doc `BE/POWERUPS.md:28-30, :217` — update.
6. Update pinned tests: `BE/test/utils/powerupUpgrades.test.js:171-198`,
   `BE/test/commands/wrongTurn.test.js` / `legCramp.test.js`,
   `FE/test/case_opening_toast_test.dart:79`.

**DECIDED (user, 2026-08-09):** Mystery Potion's hardcoded 2h cramps
(`usePowerup.js:546` self, `:730` enemy) are aligned down to **1h** so the
nerf can't be dodged via potion; potion self wrong-turn (`:559`) is already
1h. Add these two edits + tests to the item-1 change list.

**Backward compat:** mechanics are server-computed — zero client risk. Copy
via catalog self-heals on next fetch; frozen clients that never fetch show
stale fallback strings (already true today).

**Upgrade-cost reprice (game-analyst REQUIRED — SOUND WITH CHANGES):**
- Corrected premise: live prod has `rarityByType.WRONG_TURN = RARE`, so
  Wrong Turn charges `[0,15,45,135]` (confirmed against prod
  `powerup_upgrade_events`), not the UNCOMMON `[0,10,30,90]` ladder.
- Without a reprice, L3 becomes the worst-value purchase in the game
  (14.5–19 steps/coin vs a 22–150 market band) and the WT/LC upgrade sink
  (18.7% of the total upgrade sink) dies.
- **Reprice via `upgradeCosts.byType`** (currently `{}`; config-only, no
  deploy, no soft-bound coverage): `LEG_CRAMP = [0,10,20,30]`,
  `WRONG_TURN = [0,15,30,45]` — arithmetic cost for arithmetic duration,
  flat 43 / 58 steps/coin at every level, L1 entry price unchanged.
  Apply in `defaults.js` AND the live config PUT.
- Mystery Potion 1h alignment: blessed (−87 swing steps/potion, ~5% of EV;
  potion is `active=false, test_only=true` in prod today anyway).

---

## Item 2 — Referral completes only on a real race, not daily/weekly

**User story:** Referred users currently qualify by being auto-enrolled in a
seeded daily and settling with any steps — no real engagement. The referral
must complete only when the referee finishes an **actual race** (user-created,
with other real people), not a seeded daily/weekly.

**Current state:** `BE/src/modules/social/commands/grantReferralReward.js:180-185`

```js
const isQualifyingRace = race.seedId != null || realParticipants.length >= 2;
```

`seedId != null` = system-seeded daily/weekly (`RaceSeed`, cadence
DAILY|WEEKLY) and qualifies unconditionally — even solo. New accounts are
auto-enrolled in all seeded races (`autoEnrollNewUser.js`), so referrals
complete within ~24h with zero real action.

**Change (backend, one line + tests):**

```js
const isQualifyingRace = race.seedId == null && realParticipants.length >= 2;
```

i.e. seeded races NEVER qualify; a qualifying race is non-seeded with ≥2
`ACCEPTED` participants with >0 steps, and the referee must be a finisher
(`placement != null && totalSteps > 0` — unchanged).

- Note: this makes the payout gate CONSISTENT with the redeem-window guard
  (`redeemReferralCode.js:49-54`), which already counts only `seedId: null`
  races. The two currently treat seeded races oppositely.
- 30-day qualify window, velocity caps, once-per-provider-identity ledger,
  review-account exclusion: all unchanged.
- **In-flight referrals — DECIDED (user, 2026-08-09):** the stricter gate
  applies immediately to all `PENDING` referrals (they can still qualify via a
  real race inside their 30-day window). No migration, no grandfathering.
- Existing test `BE/test/integration/referral_reward_flow.test.js:300`
  ("a SEEDED solo race also qualifies") asserts the OLD behavior — it will be
  INVERTED deliberately, with user sign-off per the protected-tests rule (this
  is a product-behavior change, not a weakened assertion).
- **Architect REQUIRED — polarity-flip hazard:** the gate changes from
  fail-closed (`undefined != null` → false) to fail-open (`undefined == null`
  → true): a caller passing a race projection WITHOUT `seedId` selected would
  silently re-qualify seeded dailies. Tests MUST run through the real
  settlement entry point (`completeRace` → `grantReferralRewardsForRace`, as
  `referral_reward_flow.test.js` already does) and MUST pin that a seeded
  MULTI-participant daily (≥2 real finishers) does NOT pay out — not just the
  solo case. Verify both `completeRace.js:286` and `:475` call sites hand over
  a race object with `seedId` present.

**Verbiage updates ("first race" → "first race with friends" / explicit that
daily & weekly challenges don't count):**

Frontend:
- `FE/lib/screens/referral_rules_screen.dart:21-23, 27-31, 41-43, 54-56` —
  rewrite the qualifying-race definition: "a race you create or join with at
  least one other real player who logs steps. Official daily/weekly challenges
  don't count."
- `FE/lib/screens/referral_screen.dart:570-579, 586-594, 601-604, 634-635`
  (headline, invite-row, redeemed, share text)
- `FE/lib/screens/onboarding_flow.dart:627-633` (referred-install welcome)
- `FE/lib/screens/get_coins_screen.dart:473` (consumes shared copy — verify)

Backend:
- Push copy `BE/src/modules/notifications/notificationHandlers.js:671-673`
  ("completed their first race" — still true; adjust to "finished their first
  race with friends")
- Web landing `BE/src/modules/web/referralLandingPage.js:189-190, :202`

**Backward compat:** backend gate is server-side and hits all versions at
once. Frozen clients show the old "finish your first race" copy — stale but
not misleading enough to break anything; the rules screen in the next build is
the authoritative wording. Deploy order: backend anytime; frontend copy ships
with next release.

---

## Item 3 — Shop spacing fix

**Current:** `FE/lib/screens/tabs/shop_tab.dart` header column — tabs →
category pills gap is `SizedBox(height: 8)` (line 534); category pills →
filter/sort button gap is `SizedBox(height: 2)` (line 540).

**Change:** line 540 `const SizedBox(height: 2)` → `const SizedBox(height:
8)`. The button only renders in STORE+POWERUPS (conditional at 538-542), so
verify no layout shift/overflow in the other tab combinations.

UI-placement change → ui-test-planner checklist required (screenshot
IMG_3502 confirms the cramped gap).

---

## Item 4 — Power Outage vs Decoy (INVESTIGATION ONLY — no change)

**Answer:** Power Outage is an untargeted AoE (`usePowerup.js:1387-1461`)
resolving per-victim: Umbrella → immune (not consumed); existing outage →
skip; Compression Socks → consumed, blocked; otherwise 30-min jam. It never
queries Decoy. Decoy redirects only single-target `OFFENSIVE_TYPES`
(`usePowerup.js:2165-2240`); AoEs (Rainstorm, Power Outage, Quicksand) are
deliberately not redirectable (comment at `usePowerup.js:114-117`). **A Decoy
holder hit by Power Outage is jammed normally; the Decoy is neither consumed
nor triggered.** Intended counters: Umbrella (immune) and Socks (block).

**Incidental defect found (flag to user, fix optional, NOT in this batch
unless requested):** `DECOY_REDIRECTABLE_TYPES` (`usePowerup.js:117`) is dead
code — the live gate uses bare `OFFENSIVE_TYPES`, so IMPOSTER is not actually
Decoy-redirectable despite the comment claiming it is. Default handling in
this batch: fix the COMMENT to match live behavior (no gameplay change);
making IMPOSTER actually redirectable is a separate product decision.

---

## Item 5 — Invite code auto-friend (ALREADY SHIPPED — no change)

Auto-friend is live on BOTH paths since 2026-07-12:
- Signup with code: `BE/src/modules/social/commands/recordReferral.js:67-91`
  creates an `ACCEPTED` friendship.
- Manual code entry: `redeemReferralCode.js:73-106` creates/upgrades to
  `ACCEPTED` in either direction.

**Minor inconsistency found (optional follow-up):** `redeemReferralCode` lacks
the `isReviewAccount` exclusion that `recordReferral` has (payout is still
blocked later, but attribution + auto-friend happen). Not user-visible; leave
unless the user wants parity.

---

## Item 6 — Power Outage: out of shop + daily roll, into box drops as RARE

**Key facts:** Shop and daily roll share one authority — the
`powerup_shop_items` row (`getEligiblePowerupPool.js:14-33` uses the same
`findActive` predicate as the shop). Box drops are balance-config only
(`dropPool` / `storeOnlyTypes`), disjoint from the shop table. The
`enforceStoreOnlyExclusion` trap (`balanceConfig.js:98-112`): the stored AND
code-default `storeOnlyTypes` lists are unioned and stripped from `dropPool`
on every load — if `defaults.js` still lists POWER_OUTAGE, drops are silently
zero after any deploy.

**Change (backend + live config, in this order):**
1. **Code defaults** (`BE/src/modules/economy/balanceConfig.defaults.js`):
   - `:204` remove `"POWER_OUTAGE"` from `storeOnlyTypes`
   - `:133` rarity `UNCOMMON` → `RARE`
   - `:161-172` add `"POWER_OUTAGE"` to `dropPool.RARE` (weight default 1.0)
2. **Deploy backend.**
3. **Live DB config:** `PUT /admin/balance-config` with the same three edits.
   Ordering rationale (architect correction): code must deploy FIRST because
   `enforceStoreOnlyExclusion` (`balanceConfig.js:98-112`) UNIONS the stored
   list with `defaultConfig().storeOnlyTypes` on every load — a config-only
   edit is silently re-stripped until the default changes. The PUT may need
   `acknowledgeBoundWarnings` if any soft bound trips (`balanceConfig.js:759-765`).
4. **Hide the shop row** (kills shop + daily roll + purchase in one write):
   `npm run powerups:store -- hide POWER_OUTAGE --db=prod --apply`
   (sets `active=false`; the script warns if a hidden SKU is still in the drop
   pool — expected and fine here). **Cache note:** the powerup catalog is
   Redis-cached (`cacheKeys.js:18,65`); confirm the script invalidates
   `POWERUP_CATALOG` or expect visibility to lag by the TTL.
5. **Do NOT touch** `POWERUPS5_GATED_TYPES` (`powerupGating.js:46`): old
   non-powerups5 clients must keep having it stripped from their drop pool
   (`powerupOdds.js:200-215`) — otherwise the drop would be a bricked slot
   (`usePowerup` rejects with `UPDATE_REQUIRED`). Frozen clients also keep the
   existing `POWER_OUTAGE → SIGNAL_JAMMER` effect relabel
   (`getRaces.js:57`, `getRaceProgress.js:916`).

**Verified odds (game-analyst, run through the backend's own
`typeOddsForPosition` against prod config v3):** slot-for-slot swap with
Fanny Pack — RARE tier weight stays **9.5**; every other type's odds are
byte-identical. P(POWER_OUTAGE) = **3.38% of leader boxes / 6.00% of
last-place boxes** (12.5% / 13.3% of the RARE tier after position filters);
app-wide free supply ≈13.9/day vs 13 shop copies sold all-time. Discard
payout 5 → 10 coins confirmed. Not upgradeable (unchanged).

**game-analyst REQUIRED additions:**
- **Add `positionRules.leadingDownweight = { POWER_OUTAGE: 0.3 }`** (defaults
  + live config; PO appears in exactly one positionRules list so
  `validateConfig` stays clean). Without it, leaders net **5.34×** more POs
  per race than last place (box-volume dominance swamps the per-box trailer
  bias) and a 30-min field-wide freeze becomes a lead-preservation tool.
  With 0.3: leader 1.11% / last 6.00%, per-race ratio 1.76:1, peak holder
  mid-pack. Keep type weight 1.0 (a flat weight cut scales both ends and
  fixes nothing).
- **Umbrella gap (surface to user):** the documented immunity counter is
  `active=false` and in no drop pool — Compression Socks is the ONLY
  reachable counter, at 35× the historical PO supply. Decide: reactivate
  Umbrella (separate change) or accept and monitor.
- Team-race feel note: PO on an all-jammed field consumes the item with
  `outcome: "BLOCKED"`; at 13.9/day two teammates can now collide within a
  30-min window. Accepted (low), documented here.

**Decision (user, defaulting to NO):** the code comment at `defaults.js:224-227`
names Power Outage as the next `teamOnlyTypes` candidate. Default: available
in all races, not team-only.

**Frontend (next build, cosmetic only):**
- `FE/lib/widgets/case_opening_strip.dart:558-570` — add POWER_OUTAGE to the
  `_rareTypes` decoy reel + `:520-541` `_bundledRarityByType` (absent today).
- Shop tab is server-driven; no removal work needed.

**Existing owners:** anyone holding a purchased Power Outage keeps it and can
still use it (`usePowerup` doesn't check shop visibility). Confirmed OK.

---

## Item 7 — Cleanse must not clear Rally Flag (bug fix)

**Root cause:** Cleanse removes any effect where `sourceUserId !=
targetUserId` (`usePowerup.js:300-320`); `NON_CLEANSABLE_TYPES = ["BOUNTY"]`.
Rally Flag / Uprising write one row per teammate sourced from the caster
(`upsertBuffWindow`, `usePowerup.js:1206-1233`), so every *teammate's* copy
looks opponent-inflicted and gets cleansed (caster's own survives — hence
"intermittent"). Frontend already classifies these as boosts
(`FE/lib/utils/effect_polarity.dart:14-24`); backend disagrees.

**Change (backend):**
1. `usePowerup.js:315` → `NON_CLEANSABLE_TYPES = ["BOUNTY", "RALLY_FLAG",
   "UPRISING"]`. This automatically fixes both CLEANSE (`:2761-2795`) and
   QUICK_RINSE (`:1198-1211`) — both filter via `isCleansableDebuff`.
2. The "No debuffs to cleanse" 400 guard (`:2001-2004`) then correctly stops
   counting a lone Rally Flag as a cleansable debuff (no separate edit — it
   uses the same predicate; add a test asserting it).
3. Tests: extend `BE/test/integration/powerups-cleanse-legcramp.test.js` /
   follow the `powerups-bounty-not-cleansable.test.js` precedent — teammate's
   Rally Flag and Uprising survive Cleanse and Quick Rinse; Cleanse with ONLY
   a Rally Flag present returns **400** (`usePowerup.js:2001-2004`) while
   Quick Rinse with only a Rally Flag returns **409 `NO_TIMED_DEBUFFS`**
   (`usePowerup.js:1990-1996`) — assert both codes; real debuffs still
   cleansed alongside a surviving flag.

No frontend change; no data migration (already-cleansed flags are gone).
Server-side, applies to all app versions on deploy.

---

## Item 8 — Remove Fanny Pack; Lucky Horseshoe → 100% rare, can't roll itself

### 8a. Fanny Pack removal
Only obtainable from the in-race mystery box (`dropPool.RARE`,
`defaults.js:165`); no shop SKU, hence not in daily roll.

1. Remove `"FANNY_PACK"` from `dropPool.RARE` in `defaults.js` AND the live
   config (`PUT /admin/balance-config`). Keep it in `BALANCE_POWERUP_TYPES`
   and `rarityByType` (validation requires rarity coverage; rarity-without-
   drop-slot is the established pattern — CAMPFIRE_REST/TRAIL_MAGNET).
2. Existing owners unaffected: held copies still usable, slot-revert on expiry
   intact (`expireEffects.js:59-69`). The full-inventory auto-activate and
   already-expanded re-roll special cases in `openMysteryBox.js:197-242`
   become dead code — leave in place (harmless) to keep the diff minimal.
3. Frontend maps are lookup-with-fallback — no crash risk; remove FANNY_PACK
   from the decoy reel `_rareTypes` (`case_opening_strip.dart:558-570`) next
   build so the case animation stops advertising it.

### 8b. Lucky Horseshoe rework
Today: on use, rolls rare-chance by level `[0, 0.2, 0.45, 1.0]`
(`defaults.js:378-380`), miss → UNCOMMON floor; the floored box re-picks from
the position-filtered pool (`openMysteryBox.js:176-196`); RARE pool contains
LUCKY_HORSESHOE so it can hand back another horseshoe (~10% of forced-rare
picks).

1. **100% rare at every level:** `luckyHorseshoe.rareChanceByLevel` →
   `[1, 1, 1, 1]` in `defaults.js:378-380` AND live config.
   **DELETE the `SOFT_BOUNDS` entry at `defaults.js:441-446`** (game-analyst:
   do not widen it — `[1,1,1,1]` would trip the level-1 bound → 422 unless
   `acknowledgeBoundWarnings`, which stamps a sticky `boundOverride=true`
   that masks future real warnings; the bound guards a ramp being retired).
   Prod facts sizing this change: 4 horseshoe upgrades ever (3 users, 295
   coins, all consumed, zero upgraded copies currently held); no shop SKU
   exists. EV note for copy/expectations: a forced-rare box is worth 0.94–
   1.01× a normal box mid-pack but **0.51× for the leader** (leaderExcluded
   strips the high-swing rares) — "guaranteed rare" is a feel upgrade, not
   an EV upgrade; accepted.
2. **Upgrades become meaningless — retire WITHOUT breaking frozen clients
   (architect REQUIRED).** Do NOT remove `LUCKY_HORSESHOE` from
   `upgradeableTypes`: the client's "is upgradeable" decision is BUNDLED
   (`FE/lib/constants/powerup_copy.dart:260` + ladder `:552-557`), so frozen
   binaries would keep offering L1-3 and hit a permanent 400
   ("not upgradeable", `usePowerup.js:1013-1015`). Instead keep it listed and
   flatten the cost: `upgradeCosts.byType.LUCKY_HORSESHOE = [0,0,0,0]`
   (defaults + live config) — old clients see free, inert upgrades; the NEW
   build hides the horseshoe upgrade UI (drop the Dart tier labels at
   `powerup_copy.dart:552-557`). Add a mixed-version test: POST a horseshoe
   use with `upgradeLevel: 3` → succeeds, behaves as L0.
   **DECIDED (user, 2026-08-09): no refund** — quietly retire the ladder.
   game-analyst to report how many users actually hold upgraded levels.
3. **Can't roll itself — DECIDED (user, 2026-08-09): forced boxes only.**
   **Corrected mechanism (architect REQUIRED):** with `rareChanceByLevel =
   [1,1,1,1]`, `rollPowerup` coerces the tier BEFORE the pick
   (`powerupOdds.js:305-307` → `coerceMinRarity` → `pickTypeForRarity`), so
   the backstop at `openMysteryBox.js:184-196` never fires — an exclusion
   there would be a NO-OP. Implement instead at the roll seam: add an
   `excludeTypes` option to `rollPowerup` → `eligiblePoolFor`, applied only
   when `options.minRarity` is set (i.e. horseshoe-forced boxes), excluding
   `LUCKY_HORSESHOE`, with the empty-pool fallback (pick from the full
   filtered pool) living at that seam. The player-facing odds disclosure
   (`typeOddsForPosition`, `powerupOdds.js:264`) deliberately does NOT mirror
   the exclusion (it shows steady-state box odds, not the forced-box special
   case) — document this in code.
   **Reroll path (architect correction): UNCHANGED.** `rerollMysteryBox.js:295-296`
   deliberately applies no horseshoe minimum — there is no duplicated block to
   edit. Add a test asserting a reroll still applies no rarity floor.
   A natural (un-floored) RARE roll may still yield a horseshoe.
4. Copy: `powerupCopySeed.js` horseshoe description/tiers ("guarantees a rare
   powerup from your next box; can't grant another Horseshoe"), Dart fallback
   `FE/lib/constants/powerup_copy.dart:552-557` tier labels removed/updated.
5. Price/EV: horseshoe is a RARE-tier item whose value just tripled at L0
   (guaranteed rare vs 20%). **game-analyst must reprice** (shop price if any,
   discard value interaction, EV vs 150-coin boxes) before numbers commit.

---

## Item 9 — Mandatory tutorial (remove skip)

Two tutorials share the onboarding slot (`onboarding_flow.dart:176-186`):
v3 demo race (live) and v1/v2 spotlight (legacy + Settings replay). Four
escape paths must close in BOTH:

1. Intro "Skip for now" buttons: `FE/lib/screens/onboarding_flow.dart:795-815`
   (v3) and `:720-739` (v1/v2) — remove.
2. In-tutorial skip controls: `_SkipChip` at `FE/lib/demo/demo_race_host.dart:551`
   (+ class `:989-1017`) and spotlight SKIP pill
   `FE/lib/tutorial/spotlight_overlay.dart:217-257` (+ `onSkip` plumbing) —
   remove.
3. Back gesture: `FE/lib/tutorial/tutorial_screen.dart:371-377` currently maps
   back → skip; make it a no-op (PopScope already `canPop: false`).
   Verify the demo race host has no equivalent leak.
4. Mark-seen-on-any-return: `FE/lib/screens/main_shell.dart:2243` marks the
   tutorial seen regardless of completion (`onDone(completed)` flag discarded
   at `:2233`) and `:2250-2253` (`_skipTutorialOnboarding`) — make marking
   conditional on `completed == true`; delete the skip handler. Also audit
   `main_shell.dart:286`.
   **Consequence to accept:** killing the app mid-tutorial re-runs it on next
   launch — that's the point of "mandatory," but the tutorial must be cleanly
   re-enterable from the start (verify demo host state resets).
5. Copy ("we promise it's quick"): `onboarding_flow.dart:768-786` — e.g.
   dock body → "A quick 90-second practice race — we promise it's fast, and
   you keep the 100 coins."; keep `'90 SECONDS · 100 COINS'`. Mirror for
   v1/v2 at `:690-711`. Update design-rationale comments `:764-767, :783-785`.
6. Settings "VIEW TUTORIAL" replay (`settings_screen.dart:383-394`) keeps its
   exit affordances — replay is voluntary; only onboarding is mandatory.
   The spotlight overlay's skip removal must therefore be conditional
   (mandatory in onboarding context, closable in replay) — thread a
   `mandatory` flag rather than deleting the control outright.
7. Analytics: `tutorial_skipped` events become dead in onboarding; keep the
   event wired for the replay context; note in admin funnel docs
   (`admin_screen.dart:483-485`).

**Remote kill switch + circuit breaker (architect REQUIRED — replaces the
"accepted risk" stance):** a hard-blocked user must be defusable without an
App Store cycle (~1 week phased). Add `tutorialMandatoryEnabled` to
`KNOWN_FLAGS` (`BE/src/shared/config/appSettings.js:30` pattern, default
**false**, backend deploys first, toggled from the admin flags card). Client
reads it defensively: flag absent or false ⇒ skippable (today's behavior);
only `true` activates mandatory mode. Plus a LOCAL circuit breaker: after 3
abandoned tutorial entries (started, never completed), re-show the skip
control — so a crash loop in `DemoRaceHost` can't wedge a user even before
the flag is flipped. The `mandatory` flag threads to BOTH the spotlight SKIP
pill AND the `PopScope` back handler (`tutorial_screen.dart:371-377`),
defaulting false so the Settings-replay call site is untouched (a replay user
with a broken spotlight anchor must always have an exit — ui-test-planner
risk R2).

**Additional implementation notes (ui-test-planner risks):**
- R1: v3 (`OnboardingDemoRaceStep`) and v1/v2 intro steps have independent
  skip buttons — both must be edited.
- R3: audit all callers of `_finish(completed: false)` in
  `demo_race_host.dart` (error/edge paths, not just `_SkipChip`) before
  removing; confirm `main_shell.dart:286` and the `onDone(_)` discard at
  `:2233` so mark-seen truly becomes completion-gated (when the mandatory
  flag is ON; skip path still marks seen when OFF).
- Reward idempotency: seen-marking now happens after completion; a crash
  between completion and marking re-runs the tutorial — verify the 100-coin
  grant is idempotent by `refId` on the server and assert it in a test.
- Mirrors (explicit per CLAUDE.md): `tutorial_preview_data.dart` fixtures,
  `demo_race_api_service.dart` (guard test exists), and the hand-copied tab
  bar in `tutorial_real_screens.dart` are NOT touched by this item — verified
  during planning; the checklist still eyeballs spotlight anchors.

UI-placement change → ui-test-planner checklist required (onboarding v3, v1/v2
mirror, Settings replay). Rollout: backend flag deploys first (OFF); frontend
ships mandatory-capable; flip the flag once the build has rolled out.

---

## Item 10 — Admin page revamp (categorized + actionable stats)

**Current:** one 1,294-line `FE/lib/screens/admin_screen.dart` hub: TrailSign
header, SETTINGS flags card, STATISTICS mega-card (raw `$queryRaw` blocks in
`BE/src/modules/admin/getAdminStats.js`), TOAST TESTS, 36-icon POWERUP ICONS
gallery, COSMETICS (tuner link), ECONOMY (balance config + powerup shop
links), decorative POWERUP CRATE. Known dead weight: backend computes
`teamRaces` stats never rendered; `GET /admin/feedback/suggestions` API has no
UI; toast tests / icon gallery / spinning crate are debug toys.

**DECIDED (user, 2026-08-09):** sections as proposed below, PLUS new
coin-economy stat blocks (coins minted vs sunk per day, shop purchases by
SKU, box opens) and ad-revenue detail blocks (rewarded-ad watches/day trend,
per-user cap utilization, banner impressions if tracked). Crate + icon
gallery + toast tests demoted to a collapsed DEBUG section (not deleted).
game-analyst defines the exact metric formulas before implementation.

Structure — replace the single scroll with a sectioned hub (tabs or grouped
cards):
- **GROWTH** — new users (7/30d), DAU + trend, referral funnel (link opens →
  signups → real-race finish → rewarded, matching item 2's new gate),
  onboarding funnel (existing), retention D1/D7 (existing split by
  has-friend), app-version adoption.
- **ENGAGEMENT** — races created/active (private/public/team — surface the
  already-computed teamRaces block), boxes opened/day, powerup usage.
- **REVENUE / ECONOMY** — rewarded-ad watch counts (coin + extra-spin; the
  app's only revenue proxy today), coin sources vs sinks per day, shop
  purchases by SKU. (New stats require new `getAdminStats` blocks + tests.)
- **CONFIG** — feature flags (existing switches), balance config, powerup
  shop (existing sub-screens).
- **INBOX** — suggestions viewer over the existing unused
  `fetchAdminSuggestions` API.
- **DEBUG** (collapsed by default) — toast tests, icon gallery, tuner, crate.

Kill list (user to confirm): decorative crate card, icon gallery (or move to
DEBUG), any stat not in the categories above.

**Implementation shape (architect REQUIRED — sectioned endpoint):** do NOT
bolt the new aggregates onto the existing single `GET /admin/stats` response
— the shipped admin build would pay for ~10 extra `$queryRaw` aggregates it
can't render, on the one-vCPU prod box. Add a `sections=` query param
(absent ⇒ exactly today's payload and query set — old build unchanged); the
new frontend requests per-section data lazily as each section expands. Every
new aggregate gets an explicit time bound (default 30d) and a stated index
(likely on `coin_transactions(created_at, reason)` and the box-open/ad event
tables — implementer verifies with EXPLAIN against staging). Existing JSON
keys stay byte-stable. Each new block gets a pinned query test
(`adminStats*.test.js` precedent); frontend splits `admin_screen.dart` into
per-section widgets.

---

## Item 11 — Stealth mode: push notification leaks attacker name (bug fix)

**Root cause:** the `POWERUP_USED` push handler
(`BE/src/modules/notifications/notificationHandlers.js:779-840`) interpolates
`attackerName` from `findActorName()` with NO stealth check (only stealth
mention in the module is an unrelated comment at `:763`). In-app feed, race
messages, and leaderboard all already redact to "???"
(`getRaceFeed.js:33-94`, `getRaceMessages.js:151-168`, `raceIllusions.js`).

**Change (backend, architect-corrected):** the caster's own stealth state is
NOT already loaded before the emit (`usePowerup.js` reads target stealth at
`:1689`; caster effects only at `:3614`, after the emit at `:3591`). Add an
explicit caster-stealth read
(`effectModel.findActiveByTypeForParticipant(myParticipant.id, "STEALTH_MODE")`)
and thread `stealthed` onto **every** emit that can carry an allowlisted
type: `usePowerup.js:3591` (main), `:1163` (Quicksand per-victim), `:1449`
(Power Outage AoE), `:1332` / `:1374`, `:740` (Mystery Potion). Default
`stealthed: false` in the handler so an unthreaded emit fails SAFE (visible
name, never silent anonymization). In the handler, when `stealthed`, replace
the attacker name with `"???"` (feed convention); powerup name and duration
text intact.

- Cover every template in `POWERUP_ATTACK_MESSAGES` (`:755-777`) for the
  allowlisted push types (`LEG_CRAMP, RED_CARD, SHORTCUT, WRONG_TURN,
  SIGNAL_JAMMER, LEECH, HITCHHIKE, QUICKSAND`).
- **Second leak (architect REQUIRED — in scope):** the high-multiplier push
  (`notificationHandlers.js:1094-1099`, triggered from `usePowerup.js:3610-3623`)
  interpolates the actor's displayName with no stealth check — a stealthed
  player self-buffing is named to every rival. Apply the same `stealthed`
  anonymization there; acceptance criterion 11 covers BOTH pushes.
- Tests: extend `BE/test/integration/powerups-stealth-mode.test.js` +
  `powerup-attack-push-durations.test.js` — stealthed attacker → body contains
  "???" and not the display name; un-stealthed unchanged.
- No frontend change. Server-side, fixes all app versions on deploy.

---

## Cross-cutting: rollout order

1. **Backend PR** (items 1, 2, 6, 7, 8, 11 + admin `sections=` stats for 10
   + `tutorialMandatoryEnabled` flag for 9, default OFF): deploy;
   re-run seed (item 1 copy); `PUT /admin/balance-config` (items 6, 8 —
   including `upgradeCosts.byType.LUCKY_HORSESHOE=[0,0,0,0]`);
   `npm run powerups:store -- hide POWER_OUTAGE` (item 6).
2. **Frontend PR** (items 3, 9, 10 UI + fallback-copy touch-ups for 1, 6, 8;
   referral verbiage for 2): iOS + Android built in lockstep, normal release.
3. **Flip `tutorialMandatoryEnabled` ON** only after the carrying build has
   rolled out (~1 week phased); before that, all builds behave as today.
4. No `testOnly` gating needed anywhere: no item makes an old client render
   content it doesn't bundle. Item 6's drop stays powerups5-gated exactly as
   the wave-5 machinery already provides.

## Test plan (tests first, then logic)

Backend (`test:unit` / `test:integration`, test DB only):
- Item 1: upgraded durations table; effect `expiresAt` = use time + 1h15m at
  L1; push/feed duration string "1h 15m".
- Item 2: seeded race settlement does NOT reward a pending referral (inverts
  the existing `:300` assertion — flagged, deliberate); non-seeded ≥2-real-
  participant race does; solo non-seeded still doesn't; 30-day window still
  expires.
- Item 6: catalog + daily-roll pool exclude POWER_OUTAGE once row inactive;
  box drop possible for powerups5 client at RARE; NOT droppable for
  non-powerups5 client; purchase 404/409.
- Item 7: teammate Rally Flag + Uprising survive Cleanse and Quick Rinse;
  lone Rally Flag → 400 "no debuffs"; caster's own flag unaffected; real
  debuff still cleansed alongside.
- Item 8: Fanny Pack absent from box drops; horseshoe floor always RARE at
  L0; forced-rare pick never LUCKY_HORSESHOE (exclusion at the `rollPowerup`
  seam, only when `minRarity` set); empty-pool fallback safe; reroll applies
  NO rarity floor (unchanged behavior, pinned); horseshoe use with
  `upgradeLevel: 3` from a frozen client succeeds as L0 (no 400).
- Item 11: stealthed attacker push shows "???", non-stealthed shows name;
  per-type templates; high-multiplier push also anonymized; unthreaded emit
  defaults to visible name (fail-safe pinned).
- Item 2 (hardened): tests go through real `completeRace` settlement; seeded
  multi-participant daily with ≥2 real finishers does NOT pay a referral.
- Item 10: each new stats block pinned by a query test.

Frontend (widget/integration, pump real screens):
- Item 3: pump shop tab, assert 8px gap both sides (and other tab combos
  unaffected).
- Item 9: with mandatory flag ON — onboarding v3 intro has no skip control;
  demo host shows no skip chip; back gesture during spotlight tutorial
  doesn't complete onboarding; seen-flag set only on `completed == true`.
  With flag OFF/absent — skippable exactly as today. Settings replay always
  closable regardless of flag. Circuit breaker: 3 abandoned entries re-shows
  skip. Coin grant idempotent on tutorial re-completion.
- Item 10: admin sections render with mocked stats payload; missing fields
  degrade to "—" not crash.
- Items 1/6/8 fallback copy: updated constants tests.

## Acceptance criteria
1. Wrong Turn/Leg Cramp max duration is 1h45m at L3; labels match everywhere.
2. A referred user auto-enrolled in dailies alone is never rewarded; finishing
   a real ≥2-person race rewards both sides; all copy says so.
3. Shop gap above filter row == gap above category pills (8px).
4. (No change — findings delivered.)
5. (No change — already shipped; findings delivered.)
6. Power Outage: absent from shop & daily roll; drops as RARE in boxes for
   powerups5 clients only; old clients unaffected.
7. Cleanse/Quick Rinse never remove Rally Flag or Uprising.
8. Fanny Pack undropable (held copies still work); Horseshoe guarantees rare
   at all levels and never yields another horseshoe from a forced box.
9. With `tutorialMandatoryEnabled` ON and the carrying build installed, the
   onboarding tutorial cannot be skipped or bypassed via back/return (except
   the 3-abandon circuit breaker); replay from Settings still optional; new
   copy live; old builds and flag-OFF behave as today.
10. Admin hub categorized (Growth/Engagement/Revenue/Config/Inbox/Debug) with
    the approved metric set; dead stats removed.
11. Stealthed attacks push "???" instead of the attacker's name — in both the
    POWERUP_USED attack push and the high-multiplier push.

## Open questions for the user
None — all four interview questions answered 2026-08-09; decisions folded
into items 1, 2, 8, 10 above.

## Manual UI-placement test plan (ui-test-planner, verbatim)

**Item 3 — Shop spacing**
1. Real shop screen, STORE + POWERUPS — Home tab → SHOP pill → STORE →
   POWERUPS. Verify: gap above the filter/sort row visually equals the gap
   above the category pills (8px both); no double-gap (old 2px SizedBox not
   left in addition).
2. STORE + CHARACTERS and STORE + ACCESSORIES — filter/sort row absent, no
   stray 8px void under the pills, tile list starts at the same height as
   before.
3. INVENTORY segment (each category) — same as #2; no overflow stripe on
   small devices (check an SE-size phone if handy).

**Item 9 — Mandatory tutorial** (test with `tutorialMandatoryEnabled` ON)
4. Onboarding v3 intro (fresh account) — "Skip for now" gone; START THE
   TUTORIAL full-width, not floating oddly; new copy present ("we promise
   it's quick" phrasing, `90 SECONDS · 100 COINS` retained).
5. Demo race in progress — no SKIP chip during all 12 beats; iOS back-swipe /
   Android back does nothing at every phase; coach chrome unshifted where the
   chip was removed.
6. Kill-and-relaunch mid-tutorial — tutorial re-runs cleanly from the start;
   still impossible to reach the main app without finishing.
7. v1/v2 spotlight intro (staging, onboardingV3 off) — "Skip for now" gone
   from "Earn your first 100 coins"; mirrored new copy present.
8. Spotlight tutorial, onboarding context — no SKIP pill on any step; back
   gesture no-op (does NOT complete onboarding); spotlight still rings home
   steps / milestones / SHOP pill / friends correctly.
9. Settings replay — Profile → Settings → VIEW TUTORIAL: SKIP pill IS
   present and works; back gesture still exits; completing returns to
   Settings normally.
10. Bail-out no longer marks seen — background/kill at the v3 intro step;
    relaunch lands back at the tutorial step.
   (Also verify flag OFF: behavior identical to today, skip present.)

**Item 10 — Admin hub**
11. Admin screen — six sections in order GROWTH / ENGAGEMENT / REVENUE /
    CONFIG / INBOX / DEBUG; every pre-existing card findable exactly once
    (flags→CONFIG, stats split per spec, tuner+balance+shop→CONFIG, toast
    tests+icon gallery+crate→DEBUG); DEBUG starts collapsed; nothing left in
    an old flat-scroll position.
12. Admin sub-screens reachable — tuner, balance config, powerup shop,
    suggestions INBOX each open; INBOX renders the list (empty state OK,
    crash is not).
13. Admin against current prod backend (or pre-deploy staging) — missing
    sections degrade to "—", layout holds with absent data.

**Surfaces confirmed unaffected:** ShopTab has no tutorial/demo mirror (only
constructed from the Home SHOP pill); the `home.shop` spotlight anchor rings
the home-tab pill, not the shop screen; AdminScreen has no mirror and no
spotlight key; race_detail/case_opening untouched by item 9; no tab reorder.

## Revision log
- Draft 1: initial spec from five exploration reports.
- Gap pass 1: added Mystery Potion bypass question (item 1); flagged the
  protected-test inversion in item 2 explicitly; added `enforceStoreOnlyExclusion`
  code-before-config ordering (item 6); added empty-pool fallback for
  horseshoe self-exclusion (8b); made spotlight skip-removal conditional so
  the Settings replay stays closable (item 9); noted seen-flag semantics
  change needs no backend edit (item 9).
- Gap pass 2: added upgrade-cost EV question for nerfed WT/LC (item 1);
  pinned deploy order backend-code → deploy → config-PUT → shop-hide
  (item 6); added reroll-path duplication note (8b) and admin-stats key
  stability for the current build (item 10); AoE stealth anonymization for
  QUICKSAND (item 11); confirmed no testOnly gating needed anywhere.
- User interview (2026-08-09): potion cramps → 1h; strict referral gate
  applies to pending; no horseshoe refund + forced-box-only exclusion; admin
  sections as proposed + coin-economy + ad-revenue stat blocks.
- Architect review (REVISE → folded): horseshoe exclusion moved to the
  `rollPowerup` seam (backstop was unreachable after coercion); reroll path
  confirmed floor-free, not edited; horseshoe stays in `upgradeableTypes`
  with zeroed byType costs (frozen-client 400 avoided); item 11 enumerates
  all emit sites with fail-safe default + adds the high-multiplier push
  leak; item 9 gains `tutorialMandatoryEnabled` remote kill switch +
  3-abandon circuit breaker + mandatory-conditional PopScope; item 10 moves
  to a `sections=` param with bounded, indexed queries and byte-stable
  legacy keys; item 2 tests pinned to the real settlement path incl. seeded
  multi-participant negative case; item 6 ordering rationale corrected
  (union semantics) + cache invalidation note; item 7 Quick Rinse 409 case;
  shared "1h 15m" duration formatter (item 1); combined post-batch RARE
  table for game-analyst (items 6+8).
- ui-test-planner: 13-point manual checklist added below; risks R1-R5 folded
  into item 9 implementation notes and item 10 key-stability requirement.
- game-analyst (SOUND WITH CHANGES ×3 → folded): WT cost premise corrected
  to the RARE ladder; byType reprice LC [0,10,20,30] / WT [0,15,30,45];
  verified PO odds (3.38%/6.00%, tier weight 9.5 unchanged) replace the
  estimates; `leadingDownweight = { POWER_OUTAGE: 0.3 }` added (5.34:1
  leader dominance without it); SOFT_BOUNDS horseshoe entry deleted rather
  than widened; no-refund confirmed a non-event (0 upgraded copies held);
  Umbrella one-counter gap surfaced as a user decision; horseshoe
  self-exclusion reframed as feel/anti-dud (no farming loop exists — chain
  length 1.12 even unexcluded); Mystery Potion alignment blessed.
