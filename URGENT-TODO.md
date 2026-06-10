# URGENT-TODO

Scan date: 2026-06-10. Focus: placeholder/missing image assets and other
urgent follow-ups. Ordered by priority. File:line references are clickable.

---

## P0 — Art debt created by the 1.3.0 Ranked v2 release (ships to everyone)

These render as **placeholders the moment 1.3.0 is on a phone**, because the new
ranked tab shows the full 6-tier ladder strip to every user.

### 1. Platinum & Legend tier shields (missing art → tinted placeholders)
- **What:** `assets/images/shield_platinum.png` and `assets/images/shield_legend.png`
  do not exist. `tierShieldAsset()` currently **reuses the Silver and Diamond
  shields** and recolors them via `tierShieldTint()`.
- **Where:** `lib/widgets/tier_badge.dart:99` (`tierShieldAsset`) and
  `lib/widgets/tier_badge.dart:118` (`tierShieldTint`).
- **Visible:** everywhere a tier shield shows — the ranked hero, the 6-tier
  "ladder" strip (shown to all users), profile badge, cohort rows.
- **Do:** add the two PNGs (match the existing `shield_*.png` style/size), then
  point `tierShieldAsset()` at them and delete the `tierShieldTint()` branch +
  the `color`/`colorBlendMode` lines in `TierShield.build`.

### 2. Legend Crown accessory (missing art → errorBuilder fallback)
- **What:** `assets/images/accessories/legend_crown.png` does not exist. The
  `ranked_legend_crown` cosmetic (assetKey `legend_crown`) is **already seeded to
  prod** (earn-only). When equipped it renders the generic accessory fallback.
- **Where:** asset folder `assets/images/accessories/`; assetKey defined in
  backend `data/cosmetics.json` and `src/commands/grantLegendCosmetic.js`.
- **Urgency:** lower than the shields — it's earn-only and first granted at a
  Legend settlement (~weeks out), so no user can equip it yet. But it must exist
  before the first cohort produces a Legend.
- **Do:** add the PNG (HEAD slot; tune offset/scale via the in-app accessory
  tuner like the other hats).

---

## P1 — Pre-existing art debt (already in prod)

### 3. Mirror powerup icon (missing art → fallback icon)
- **What:** `assets/images/powerups/mirror.png` is missing; every other powerup
  in `assets/images/powerups/` has art. Mirror is a live, purchasable powerup,
  so it currently shows the generic fallback icon.
- **Where:** `lib/widgets/powerup_icon.dart:40` (existing `TODO(1.1.7 art)`).
- **Do:** add `mirror.png` matching the other powerup icons, then drop the TODO.

---

## P2 — Minor / cleanup

### 4. Dead "FRIENDS" button on the legacy ranked ladder
- **What:** `_LadderTitle(onFriendsTap: () {})` renders a "FRIENDS" button that
  does nothing.
- **Where:** `lib/screens/tabs/ranked_tab.dart:1101`.
- **Scope:** only on the **legacy** `/ranked` fallback path (backends without
  `/ranked/v2`); the new cohort UI doesn't render it. Either wire it to a
  friends-scope filter or remove the button.

### 5. Legacy season ranked system is now dormant — schedule sunset
- **What:** `GET /ranked` (RP seasons) still runs with rewards zeroed, only to
  serve app ≤ 1.2.0. Per `RANKED_V2.md`, replace it with a legacy-shaped
  projection of the cohort system once 1.3.0 saturates, then delete the season
  tables. **Never 404 `/ranked`** — old apps treat that as permanent "coming soon".
- **Where:** backend `src/constants/rankedTiers.js`, `src/queries/getRanked.js`,
  `src/jobs/computeRanks.js`; plan in `steps-tracker-backend/RANKED_V2.md`.

---

## In-flight deploy (not code TODOs, but pending right now)

The 1.3.0 / Ranked v2 cutover is mid-deploy. Code is on `main` (both repos) and
the **prod DB is already migrated**. Still pending (manual):
1. **Droplet restart** — `git pull && npm install && npx prisma generate &&
   node prisma/seed.js && pm2 restart 3` (skip `migrate deploy`, already applied).
   Seeds the Legend crown; **zeroes legacy ranked rewards on restart**.
2. **App Store submit** — `flutter build ipa --flavor prod --release
   --dart-define=BACKEND_BASE_URL=https://steptracker-api.org` → Transporter →
   Bara → version 1.3.0, phased release ON.

See `steps-tracker-backend/RANKED_V2.md` for the full checklist/invariants.
