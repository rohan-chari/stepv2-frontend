# Powerup Ideas Catalog

Ranked ideas for new store powerups, informed by how other games design power-up
systems (Mario Kart's position-scaled catch-up items, Mario Party's
steal/swap/trap items, card-game buff/debuff taxonomies, casual async mobile
boosters) and constrained to what our effect engine already supports.

**Status: ideas only.** Nothing here is spec'd or approved for build. Winners go
through the spec-first pipeline (`CLAUDE.md`) before any code.

## How to read the entries

- **Engine fit** — which existing effect shape the idea reuses. The scorer
  (`stepv2-backend/src/modules/races/services/effectiveStepScoring.js`) supports:
  windowed multipliers (2x / 0.5x / 0x freeze / −1x reverse), zero-sum transfer
  (Leech/Shortcut), non-zero-sum copy (Hitchhike), instant bonus/penalty,
  use-time shields/reflect (Mirror → Socks precedence in `usePowerup.js`),
  dispel, info/reveal, traps (Trail Mine), and box/economy meta.
- **Build cost** — S: config + copy + a use-time gate on an existing shape.
  M: bounded new engine work (new resolution hook or multi-row logic).
  L: fights the additive model or needs a new subsystem.
- **Price** — suggested, on the existing 40 / 75 / 150 / 300 ladder. Catch-up
  effects are gated by position instead of price (Mario Kart gives its
  strongest items to the players furthest behind); mass/AoE effects sit at the
  Leech tier (300).

---

## Tier A — near-free retrofits (build cost S)

### 1. Uprising — catch-up
- **Effect:** the **entire bottom half of the race** (caster included) gets 2x
  steps for 2h. Usable only while you're in the bottom half. The top half gets
  to sweat.
- **Target / duration / price:** all bottom-half racers · 2h · **300 coins**
  (Leech tier — it's a mass effect, priced like one).
- **Engine fit:** Runner's High multiplier rows fanned out per-beneficiary
  (Rainstorm/Quicksand's multi-row creation pattern, but as a buff) + a
  use-time position gate mirroring Red Card's "blocked if leading" check in
  `usePowerup.js`. Membership snapshotted at activation.
- **Why:** the store has no true comeback item (Second Wind is box-only), and
  making it a *collective* uprising turns one purchase into board-wide drama —
  the leaders feel hunted, the back half feels like a team.
- **Risks:** stacking with Runner's High should take max, not sum (Campfire×RH
  precedent); double-cast by two bottom-half players should merge windows, not
  stack to 4x (Rainstorm's per-victim merge is the template); team races need
  a defined "bottom half" (use the 2-slot team standings).

### 2. Ghost Pepper — gamble / chaos
- **Effect:** 3x your steps for 30min, then **frozen for 30min**. Boost first,
  crash after.
- **Target / duration / price:** self · 1h total (two phases) · ~75 coins.
- **Engine fit:** Campfire Rest's two-phase code path inverted (Campfire is
  freeze-then-boost; this is boost-then-freeze). Same metadata shape, same
  overlap rules.
- **Why:** skill expression — you fire it right before a walk. The crash makes
  it a real decision instead of a strictly-better Runner's High.
- **Risks:** hourly-bucket proration makes short phases estimates (the
  Wrong Turn / bracket-900 lesson); the 5-min sample rollout largely fixes
  this — consider gating availability on the 5-min flag.

### 3. Coin Flip — gamble
- **Effect:** server rolls 50/50 at use-time: **2x for 1h** or **0.5x
  (self-rainstorm) for 1h**. Result shown immediately with big win/lose juice.
- **Target / duration / price:** self · 1h · ~30 coins.
- **Engine fit:** one multiplier row whose magnitude is rolled server-side at
  activation; both magnitudes (2.0, 0.5) already exist in the scorer. Outcome
  lands in the effect row metadata like other magnitudes.
- **Why:** cheapest thrill in the store; gamble items are proven engagement in
  casual mobile (spin/box mechanics already do well here).
- **Risks:** self-debuff outcome must be Cleanse/Quick Rinse-**immune**
  (self-inflicted, not opponent-inflicted — the dispel logic already filters
  by source, verify it treats self-source correctly).

### 4. Mystery Potion — gamble
- **Effect:** applies one random effect from a curated pool of existing
  effects, e.g. Protein Shake, Runner's High (1h), Leg Cramp on a random
  rival, Pinecone Toss, small coin refund.
- **Target / duration / price:** varies by roll · varies · ~50 coins.
- **Engine fit:** pure use-time roll that creates an existing effect row —
  zero scorer changes. Pool and weights belong in `balance-config.json` so
  they're tunable without deploy.
- **Why:** recycles the whole existing catalog into new content; the reveal
  moment reuses case-opening juice.
- **Risks:** rolled offensive effects must still respect shields/jammer on
  the rolled target (route the roll through the normal use path, don't
  shortcut it).

### 5. Decoy — defense / chaos
- **Effect:** held shield: the **next targeted attack on you redirects to a
  random other opponent** in the race.
- **Target / duration / price:** self (held) · until consumed or 24h · ~100
  coins.
- **Engine fit:** third entry in the use-time shield precedence chain
  (Mirror → Decoy → Socks), resolved where Mirror/Socks already resolve in
  `usePowerup.js`. The redirected target gets the normal attack-outcome
  treatment.
- **Why:** Mario Party-grade chaos — attacks ricocheting into bystanders
  creates stories and group-chat drama, which is the app's social engine.
- **Risks:** define behavior in a 2-player race (no third party → behaves as
  a block); team races must redirect to an **enemy**, not a teammate.

---

## Tier B — bounded new engine work (build cost M)

### 6. Power Outage — chaos
- **Effect:** AoE Signal Jammer: **no opponent can use any powerup for
  30min**.
- **Target / duration / price:** all opponents · 30min · ~150 coins.
- **Engine fit:** Signal Jammer's use-block check already exists; creation
  fans out per-victim rows like Rainstorm/Quicksand. No scorer changes at all.
- **Why:** the "lightning bolt" — a board-wide tempo play before your big
  walk. Short duration keeps it annoying-not-oppressive.
- **Risks:** shield semantics per-victim (Socks holders should be exempt,
  matching single-target Jammer); stacks with individual Jammer by merging
  windows, not extending.

### 7. Umbrella — defense
- **Effect:** 12h self-immunity to **AoE debuffs** (Rainstorm, Power Outage).
  Targeted attacks still land.
- **Target / duration / price:** self · 12h · ~75 coins.
- **Engine fit:** exempt check inside the scorer's rainstorm merge
  (`mergeRainstormWindows` path) + a use-time exempt for AoE fan-out. This is
  the one Tier A/B idea that touches the scorer's overlap loops — hence M.
- **Why:** Rainstorm currently has no counterplay except Cleanse-after-the-
  fact; pre-emptive defense creates a buy-before-bed habit loop.
- **Risks:** overlap accounting is manual in the additive model; needs its own
  settlement-parity test.

### 8. Rally Flag — team
- **Effect:** in team races, your **whole team** gets 1.25x steps for 1h.
- **Target / duration / price:** allied team · 1h · ~150 coins.
- **Engine fit:** multi-row self-buff fan-out across team members (membership
  from `teamRaces.js`); each row is a plain multiplier the scorer already
  handles. Usable only in team races (use-time gate).
- **Why:** team races have team-targeted *attacks* but no team *buff*; buying
  for the squad is a distinct, social spend motivation (inter-team
  competition + intra-team collaboration is the researched sweet spot).
- **Risks:** stacking rule if two teammates fire it (merge windows, cap at
  1.25x — Rainstorm's per-victim merge is the template).

### 9. Drill Sergeant — sabotage
- **Effect:** dare a rival: they must walk **3,000 steps in the next 2h** or
  lose **1,500 steps**. If they hit it, nothing happens (optionally: they gain
  a small bonus, making it risky to cast on a walker).
- **Target / duration / price:** one opponent · 2h · ~100 coins.
- **Engine fit:** new expiry-time evaluation hook in `expireEffects.js` that
  reads the window's samples and writes an instant penalty. Needs the
  snapshot fallback for sample-less users and a settlement path for races
  that end mid-dare (evaluate pro-rata or void — spec decision).
- **Why:** it's a *provocation* mechanic — the push notification ("you've
  been dared!") is itself an activity driver, not just sabotage.
- **Risks:** hourly-bucket proration (mitigated by 5-min samples); dare
  target should get a push + visible countdown or the mechanic feels like a
  hidden gotcha.

### 10. Piggy Bank — economy
- **Effect:** for 24h, earn **1 coin per 300 steps**, capped at **80 coins**.
  Only ONE active piggy per user globally (across all races) — closes the
  multi-race same-steps faucet exploit.
- **Target / duration / price:** self · 24h · 40 coins. Break-even at 12,000
  steps; a hardcore 24k day nets +40 max — the buyer only profits by walking
  *more* than usual, which is the intended behavior loop. (Cap must exceed
  price or the item can never pay off.)
- **Engine fit:** effect row + expiry-time coin mint from samples in
  `expireEffects.js`; no scorer involvement. Rate/cap/price live in
  `balance-config.json` + env-tunable (like `AD_COIN_REWARD_*`) so tuning
  needs no deploy.
- **Why:** an *engagement-shaped* coin faucet that chips at the economy
  problem (median earner ~6 coins/day vs 75-coin prices) without a free
  handout — you pay up front to unlock earning by walking.
- **Risks:** it's a coin faucet, and step data is client-reported (same trust
  level as race steps, but now it mints currency) — keep the cap hard.
  Game-theory guardrail: net expected profit per purchase must stay small
  (single digits for a median walker), or it deflates every other price in
  the store; anything like 1-per-100 with a large cap makes powerups
  effectively free for active walkers.

### 11. Bounty — economy / sabotage
- **Effect:** place a bounty on a rival ahead of you; **if they finish behind
  you**, you collect ~50 coins at settlement. Publicly visible ("💰 on
  Anjali's head").
- **Target / duration / price:** one opponent · until settlement · ~100
  coins (partial refund/payout math is the spec question).
- **Engine fit:** settlement hook + mirror in `raceStateResolution.js`
  (parity-test pattern already established). No scorer involvement — it's a
  placement predicate at settle time.
- **Why:** Mario Party's Boo/duel energy; makes mid-pack placement fights
  matter, not just first place.
- **Risks:** forfeit/void/late-settle edge cases (the scheduled-race
  backdate and raceExpiry lessons apply); coin flow is player→pot→player so
  it's not a net faucet.

---

## Tier C — big swings (future maybes, build cost L)

- **Tether** — you and a rival both score `min(you, them)` for 1h. Fights the
  additive model; would need new cross-user overlap loops in the scorer.

---

## Cross-cutting requirements (apply to every idea above)

- **Frozen clients:** every new type ships behind a new `powerups5`
  `X-Client-Features` token (catalog-filtered in `getPowerupShopCatalog.js`,
  declared in `backend_api_service.dart`) **and** `testOnly: true` until the
  carrying App Store build has rolled out. Old binaries must never receive an
  unknown enum.
- **Windowed effects** need: the `StepSample.sumStepsInWindow` path **and**
  the snapshot fallback; exclusion of the in-progress bucket; a
  settlement-parity integration test
  (`test/integration/*-settlement-parity.test.js` pattern); explicit overlap
  rules vs freeze / reverse / rain.
- **Tuning lives in `balance-config.json`** (rates, pools, caps, magnitudes),
  not hardcoded — and remember the deploy-time seed clobber trap for
  `priceCoins`/`active`.
- **Price bands:** stick to the 40/75/150/300 ladder; mass/AoE effects at the
  Leech tier (300), chaos items mid, economy items priced so the faucet stays
  modest.

## Recommended first batch

If picking ~5 for a `powerups5` wave: **Uprising, Coin Flip, Decoy,
Power Outage, Ghost Pepper** — they cover all four flavors, none touches the
scorer's overlap loops beyond existing patterns, and together they give the
store a comeback story, a gamble, a defense, a board-wide attack, and a
skill-timing play. Piggy Bank is the one worth pulling forward if the economy
fix is a priority.

## Sources

- [Mario Kart CPU / item distribution (rubber banding)](https://mariokart.fandom.com/wiki/CPU)
- [Rubber banding as a retention technique](https://www.patent355.com/resources/rubber-banding-in-gaming-a-technique-for-improved-retention)
- [Mario Party Superstars — every item explained](https://gamerant.com/mario-party-superstars-every-item-guide/)
- [Mario Party series items (Warp Block, Plunder Chest, Dueling Glove, Boo)](https://www.mariowiki.com/Mario_Party_(series))
- [Power-up (overview of the design space)](https://en.wikipedia.org/wiki/Power-up)
- [Buff/debuff taxonomy example (shields, reflect, lifesteal)](https://plariumplay-support.plarium.com/hc/en-us/articles/8032334929052-List-of-Buffs-and-Debuffs)
- [Gamified fitness apps — collaborative-competitive mechanics research](https://www.mdpi.com/2414-4088/5/2/5)
- [StepSmash — power-ups in a step-competition app](https://stepsmash.com/)
