# Team races up to 10v10 — 2.3.13 release candidate

Status: backend deployed and iOS build 9 uploaded on September 9, 2026, with explicit user authorization. Apple reports VALID / IN_BETA_TESTING; build 9 is confirmed in the internal “bara testers” group. Independent code review, analyzer, relevant tests and both signed release artifacts are verified. Staging remains stopped; production HTTP worker capacity remains two.

## Behavior and compatibility

Team capacity is 1–10 per side. Full accepted rosters are bounded at twenty and independent of invitation history/pagination. Pending, active, completed and results rosters show at most five rows per side, with independent inner scrolling. Existing row sizes, payouts, scoring and powerup rules remain unchanged.

The permanent binary capability `team_races_10v10_v1` protects frozen clients. Existing durable authenticated client-feature unions prove support for deferred approvals and populated-race resizing. Direct operations check the current request. Older clients retain accepted-member cards, rewards and safe exit actions; incompatible discovery/invitation rows are filtered. Active progress failures cannot expose identities from raw details. No team schema migration, runtime rollout flag or capacity increase.

Backend candidate is based on `c65798e`; production runtime was verified read-only at `442b749cd29f50efc0be3028e129193bc624882e`. The intervening base commit changes documentation only. Runtime `20e3909` was subsequently deployed; backend audit-only commit `53d9893` and frontend runtime `54b882c` were pushed to origin/main.

## Automated verification

- Backend implementation: 79 integration tests and 179 relevant unit tests pass, including eight deterministic resize/start/approval interleavings, invitation-heavy automatic start, scheduled twenty-player start, settlement and retry safety.
- Discovery: three real HTTP integration tests with local Redis verify old/new cache separation, filtering before suggestion limits, and retained accepted-member rewards/cards.
- Home read regression suite: thirteen pass. Two baseline tournament fixtures were reproduced against unchanged base and mechanically aligned with already-shipped timestamp/favorite fields; assertions remain strict.
- Full Flutter suite reported 3,131 passes and one pending-preview regression. The regression was fixed without changing its assertion; the entire failing suite plus roster/parser regressions pass (75 tests). The fix accepts only proven-complete legacy small-team pages; larger-team completeness remains strict. Final `flutter analyze` reports no issues. Release-note tests pass.
- Independent reviewer: SHIP after concurrency, active privacy, independent-scroll animation and preview compatibility fixes.
- Backend local load suite: ten pass using dedicated localhost test Postgres and Redis. Actual HTTP intake for 2,000 players across 100 full races uses concurrency eight, followed by real scoring workers at concurrency two, publication, and HTTP verification of all twenty members per race.

Measured local work: intake 52,037 SQL statements, resolution 2,930, publication 1,620. Intake wall time 7.32 seconds with request p95 38.19 ms; worker phase 0.64 seconds and publication 0.39 seconds. These are workstation smoke measurements, not production capacity predictions. Bootstrap reads at both sizes perform zero participant score updates. Team-wide powerup statements rise from 66/74/82 at 5v5 to 91/99/117 at 10v10 for Rally Flag/Uprising/Rainstorm. Per-recipient work remains bounded at ten; coordinated casting remains a balance consideration, with no rebalance in this release. Full raw measurements and settlement evidence live in the backend `docs/evidence/` directory.

## Manual device checklist

Run on iOS and Android after installing the candidate. These are outstanding visual checks for the user; widget tests cover prepared large-team fixtures but do not replace device inspection.

1. Create/edit: choose 10v10; confirm capacity labels, controls and bottom actions fit.
2. Pending lobby: five rows per side; independently scroll each side to members six–ten, with no missing or duplicate members.
3. Team switching: use unequal scroll offsets. Visible-slot animation connects actual positions; offscreen slots produce no flying or duplicate avatar.
4. Active standings: independently reach every member; headers remain aligned and rows stay clear of activity/chat and powerup controls.
5. Completed detail/results: reach all displayed members through five-row windows; summary actions remain accessible.
6. Small phones/enlarged text: inner and outer scrolling work independently, text does not overlap, and smaller teams have no unnecessary blank rows.
7. Demo/tutorial replays: inspect shared screens and coach highlights; repeat independent scrolling using prepared 10v10 fixtures. Existing solo fixtures alone cannot verify large rosters.

## Artifacts

Both signed artifacts verified, version 2.3.13, retained in `build/release-candidates/2.3.13-9/`:

| Artifact | Build | SHA-256 |
| --- | --- | --- |
| `Bara-2.3.13-9.ipa` | 9 | `5c8c5e9b809dcdad4de6a1d5ba05367ea3660e6f3aac059138e28bb10bd98d34` |
| `Bara-2.3.13-203139.aab` | 203139 | `da7b976bb20f41849be9865237df65ff490a30e8f4219c6eb82ab67011a58f60` |

IPA: signature valid, correct bundle/team, production APNs, no debug entitlement, all ten required public define values and large-team capability verified in compiled code. AAB: signature and trusted upload certificate valid, compiled manifest has correct package/version and Billing 8.3.0. All three packaged native libraries match independently stripped fresh compiler outputs, differ from build 8, and contain production configuration and large-team support.

README release values were checked before each build. All seven iOS AdMob units plus RevenueCat/Google/backend values retained; inline native units omitted on both platforms. Build logs retain existing nonfatal plugin migration/default launch-image warnings. Reports and logs accompany artifacts. Backend runtime `20e3909` is deployed and healthy. Xcode confirmed `Upload succeeded` and `EXPORT SUCCEEDED` at 16:32:18 UTC for build 9. The existing AppLovinSDK/FBAudienceNetwork missing-dSYM warnings remain nonblocking. No App Review submission, customer release or Play upload occurred.

Production post-deploy verification: public API/Redis healthy, two HTTP plus one cron/one resolution online, pool ceiling 32, PM2 saved, staging stopped. Referral audit/apply/final audit all zero. No migration/dependency/environment changes; existing powerup copy and balance drift preserved. Rollback/deployment tags are pushed; see backend `docs/team-races-10v10-production-deploy.md`.

Perform the manual device checklist in TestFlight before customer release. The signed matching Android artifact remains available locally.

Apple build ID: `3adc7522-5708-4d4e-b273-59434818ce44`. Existing exempt-encryption declaration is retained. Frontend runtime tag `testflight/2.3.13-9` points to `54b882c`; release audit documentation is pushed separately.
