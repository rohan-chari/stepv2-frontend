# Social Follow Rewards — Implementation Specification

## Summary & user story

Authenticated Bara users can visit Bara's Instagram, TikTok, or X profile from the existing Get Coins hub and then explicitly claim 200 coins for each platform once. The backend owns state, eligibility, amount, balance mutation, and exactly-once behavior.

Canonical campaign:

| Platform | Handle | URL | Amount |
|---|---|---|---:|
| Instagram | `@bara.steps.app` | `https://instagram.com/bara.steps.app` | 200 |
| TikTok | `@bara.app` | `https://www.tiktok.com/@bara.app` | 200 |
| X | `@BaraStepsApp` | `https://x.com/BaraStepsApp` | 200 |

## Scope / non-goals

In scope: Get Coins UI, bottom-sheet explanation, HTTPS external launch, durable opened/claimed state, authenticated status/open/claim API, Prisma model/migration, `awardCoins` integration, lifecycle refresh, analytics, integration/widget tests, iOS/Android-compatible Dart behavior.

Out of scope: OAuth, real follow verification, scraping, third-party verification, device fingerprinting, multi-account detection, feature flags, remote kill switches, remote reward configuration, unrelated Home redesign, changes to existing ad/daily/referral rewards, deployment.

## Data model / migration

Add `SocialRewardClaim` to `../stepv2-backend/prisma/schema.prisma`:

- `id String @id @default(uuid())`
- `userId String @map("user_id")`, required User relation with existing relation conventions
- `platform String`
- `openedAt DateTime? @map("opened_at")`
- `claimedAt DateTime? @map("claimed_at")`
- `rewardAmount Int @map("reward_amount")`
- `createdAt DateTime @default(now()) @map("created_at")`
- `updatedAt DateTime @updatedAt @map("updated_at")`
- `@@unique([userId, platform])`
- `@@index([userId])` only if not redundant with the composite unique index and actual query needs it
- mapped table `social_reward_claims`

Generate one additive migration only. It must create the table, primary key, unique `(user_id, platform)` index/constraint, user foreign key, and timestamp columns. No backfill is needed. Existing users safely read as `not_started` because missing rows are synthesized by status output. Review generated SQL before running tests.

## API contract

Mount an authenticated router under `/social-rewards`, following existing auth/module routing. Server constants/config in the module define the only three platforms, labels, handles, HTTPS URLs, and amount `200`; clients send no amount, URL, handle, or state.

### `GET /social-rewards/status`

Response `200`:

```json
{
  "rewards": [
    {"platform":"instagram","label":"Instagram","handle":"@bara.steps.app","url":"https://instagram.com/bara.steps.app","amount":200,"state":"not_started","openedAt":null,"claimedAt":null},
    {"platform":"tiktok","label":"TikTok","handle":"@bara.app","url":"https://www.tiktok.com/@bara.app","amount":200,"state":"not_started","openedAt":null,"claimedAt":null},
    {"platform":"x","label":"X","handle":"@BaraStepsApp","url":"https://x.com/BaraStepsApp","amount":200,"state":"not_started","openedAt":null,"claimedAt":null}
  ],
  "totalAvailable":600,
  "totalClaimed":0
}
```

All three rows are always returned in Instagram/TikTok/X order. State is derived server-side: `claimedAt != null` → `claimed`; otherwise `openedAt != null` → `opened`; otherwise `not_started`.

### `POST /social-rewards/:platform/open`

No request body is required. The route validates auth and the exact allowlist. It creates the row if absent, sets `openedAt` only when absent, and never changes `claimedAt` or grants coins. Repeated calls return `200` with the existing state. Invalid platform returns the repository's validation error shape; unauthenticated requests are rejected by normal auth middleware.

### `POST /social-rewards/:platform/claim`

No request body is required. The route validates auth/platform, requires `openedAt`, and runs the claim-row transition plus `awardCoins({tx, userId, amount: 200, reason: 'social_follow_reward', refId: platform})` in one Prisma transaction. Already-claimed retries return a safe idempotent `200` with `awarded:false`, current authoritative balance, and claimed state. First success returns `awarded:true`, `amount:200`, resulting `coins`, `state:'claimed'`, and `claimedAt`. Claim-before-open is a stable client error. Client fields are ignored/rejected; amount and timestamps are server-owned.

### Compatibility

The new routes are additive. Existing clients do not call them and remain unchanged. New clients must treat status fields as optional/defensive and handle a 404/unsupported response without crashing or inventing a reward. Backend deploy precedes app release. No existing endpoint gains a required field.

## Backend implementation path

1. Write integration tests first under `../stepv2-backend/test/integration/` using the dedicated test DB.
2. Add Prisma model and migration.
3. Add a focused social-rewards constants/validation/service/route module under `src/modules/socialRewards/` and mount it from `src/app.js` using normal auth middleware.
4. Implement status synthesis, idempotent open, and transactional claim.
5. Use only `src/shared/economy/awardCoins.js` for balance mutation and stable `reason/refId`.
6. Add activation analytics only through existing allowlisted event infrastructure, with `{platform}` context.
7. Run Prisma validation, focused integration/economy tests, then broader backend tests.

## Frontend plan

Modify `lib/services/backend_api_service.dart` with defensive status/open/claim methods. Add a focused `SocialRewardsController`/state model rather than changing `RewardedCoinsController`; it owns loading, per-platform state, deduplicated requests, open/claim errors, status refresh, and resume refresh.

Modify `GetCoinsScreen` to add a separated “FOLLOW BARA” section in the existing earn-coins list. Keep all three rows visible and use existing card, spacing, typography, coin glyph, button, loading, toast, and accessibility patterns. States: loading, unavailable/unsupported, not started (`Follow`), opened (`Claim 200`), claiming, claimed (`Claimed`), and retryable error.

Follow opens the existing bottom-sheet style. The sheet uses platform label/icon where safe, body explaining “Follow us on …, then come back to Bara to claim 200 coins,” and one primary `Open Instagram`/`Open TikTok`/`Open X` action. The action calls `launchUrl(Uri.parse(serverUrl), mode: LaunchMode.externalApplication)`; only a true result calls `/open`. Failed launch does not mark opened. Dismissal never claims.

On Get Coins entry and `AppLifecycleState.resumed`, refresh status only. Never open a sheet or award automatically. On claim success or idempotent already-claimed reconciliation, call `AuthService.updateCoins` with returned `coins`; never add 200 locally. Ambiguous claim errors trigger status/current-user reconciliation and remain retryable.

Analytics events: `social_reward_impression` once per eligible/unclaimed Get Coins visit/section render; `social_reward_opened` after successful launcher and successful `/open`; `social_reward_claimed` only after server-confirmed claim/already-claimed reconciliation; `social_reward_claim_failed` for failed claim with bounded `{platform}` context only.

## Test plan — tests first

Backend integration tests must prove status, open idempotency/no-award, invalid/unauthorized handling, claim-before-open, first/second claim, client amount rejection/ignore, exact balance, three-platform independence, repeated retry, and concurrent claims with one ledger row/one 200 increment/one claimed row.

Frontend tests must cover three rows/handles/amounts, sheet copy/actions/dismiss, correct URL launcher, launcher success/failure, open status, resume refresh without modal, claim/balance/state transitions, retry/ambiguous reconciliation, loading dedupe, and independent platform states. Extend `test/get_coins_screen_test.dart` or add a focused social-reward test with injected launcher/controller seams.

## Acceptance criteria / definition of done

- all canonical handles/URLs and 200 amounts are server-owned and correct;
- all three rows are visible in Get Coins;
- Follow opens the sheet, sheet opens external HTTPS, and launch success alone never grants coins;
- open persists indefinitely and resume/entry refreshes state;
- claim is explicit and server-authoritative;
- reinstall/device switching preserves account state;
- concurrent/replayed claims cannot exceed 200 per platform / 600 total;
- no direct `User.coins` mutation outside existing seams;
- no OAuth, verification, scraping, flags, or unrelated reward changes;
- migration is additive and reviewed;
- focused tests, `flutter analyze`, relevant Flutter tests, Prisma validation, and backend tests pass without new regressions;
- manual UI checklist is completed for Get Coins on iOS and Android, including lifecycle return and accessibility.

## Manual UI-placement test plan

1. Fresh authenticated account: open Home → coin `+` → Get Coins; verify “Follow Bara” section appears in the earn area without changing the Home badge layout.
2. Verify Instagram, TikTok, X rows are simultaneously visible/scrollable, ordered correctly, with exact handles and `+200 coins`.
3. Tap each Follow row; verify the existing slide-up sheet, platform-specific title/body/action, coin visual, dismiss behavior, and no claim.
4. Tap each Open action; verify the correct HTTPS URL is requested, the sheet does not reopen on return, and a failed launch leaves the row at Follow.
5. Return from the external app/browser; verify resume refresh changes only that row to Claim 200.
6. Kill/relaunch after opening; verify the row remains claimable. Sign in on a second device/session and verify the same state.
7. Claim each platform; verify authoritative balance, one success state, no duplicate after repeated taps/retries, and `Claimed` persists.
8. Verify offline/no-network launch/claim errors are retryable and do not mint locally.
9. Test light/dark mode, small phone width, large text, screen reader labels, keyboard/focus where applicable, safe-area bottom sheet, and Android/iOS external-launch behavior.
10. Confirm no resume event automatically opens a modal and no existing daily/rewarded-ad/referral UI changed.

## Revision log

- Drafted from `docs/social-media-rewards-research.md` and the implementation request.
- Gap pass 1: added explicit additive old-client behavior, no-row default semantics, no-feature-flag constraint, launcher-failure ordering, and ambiguous-claim reconciliation.
- Gap pass 2: added transaction co-location, stable ledger ref, concurrent integration assertions, platform ordering, lifecycle/manual mirrored-surface checklist, accessibility and iOS/Android validation.
- Architect review: NOT RUN — no subagent runner is exposed in this session.
- UI-test-planner review: NOT RUN — no subagent runner is exposed in this session; manual checklist above is the fallback and must be executed before done.

