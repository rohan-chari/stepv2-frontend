# Team races up to 10v10 — feasibility and proposed requirements

Status: implementation approved by the user, September 9, 2026, for app version 2.3.13. Prepare and verify backend and iOS/Android release candidates; report readiness for production and TestFlight. Production deployment and uploads are not requested yet. Sources are local frontend/backend code, not a production capacity measurement. Backend paths below are relative to the separate backend repository.

## Approved implementation amendment

The user approved the proposal with two concrete changes: team rosters must ignore participant pagination, and the team container must display at most five rows per side with internal vertical scrolling to reach members six through ten. Apply the five-row viewport to pending, active and completed team rosters while preserving each screen's existing row sizes and chrome. Keep team headings/counters outside scrolling content. Each side scrolls independently; lobby switch animation accounts for both scroll offsets and skips its flying avatar when either slot is offscreen. The outer page still scrolls separately. Do not render a ten-row-tall page section or reduce row/touch-target sizes.

The full accepted team roster is bounded by the server's twenty-player cap and must be loaded independently of invitation history. Ignore participant offset/limit for that roster; keep nonaccepted history bounded. The backend implementation owner records the exact additive wire contract and capability/admission schema in backend `docs/team-races-10v10-contract.md` before the frontend codes against it. All existing payout/scoring versions remain authoritative. No runtime flag is introduced.

User authorization to expand the allowed sizes supersedes the old maximum-five requirement: existing tests that reject size six without new binary support retain that protection, while new-capability requests explicitly test success through ten and rejection at eleven. All intermediate sizes, public/private parity, pending resizing with compatibility checks and existing equal-smaller-team start behavior are in scope.

## Final implementation decisions

The implemented contract is recorded in backend `docs/team-races-10v10-contract.md`. Requests advertise permanent binary capability `team_races_10v10_v1`. Deferred approval and populated-race resizing reuse the authenticated, durable union of existing `User.clientFeatures`; no schema migration or new capability endpoint is needed. Direct operations always check the current request. Large-race invitations/discovery are hidden from incompatible clients while accepted-member cards, payout and safe exit access remain available.

New capable team details/bootstrap include additive `teamAcceptedParticipants` (all accepted members, including forfeits, maximum twenty) and `teamRosterComplete`; invitation history remains bounded separately. Active incomplete-progress fallback displays anonymous membership placeholders instead of leaking identities from unmasked details. Pending, active, completed and results rosters use independent five-row containers. Team-only automatic start now counts up to twenty accepted members independently of resolved invitations; smaller teams and solo races retain existing behavior.

The findings and proposed alternatives below document the original research, not outstanding implementation decisions. Release verification and final manual checklist are in `team-races-10v10-release.md`.

## Summary and user story

Allow a creator to choose any per-side capacity from 1 through 10, so friends can run a race with up to 20 accepted participants. Keep two teams, existing combined effective-step scoring, duration rules, and race lifecycle. This is feasible without replacing the team-race system. It is more than changing a maximum: frozen clients truncate rosters and the details API has a paging boundary below 20.

Recommended scope: public and private ordinary team races, creation and pending-race resizing, invites, share links, approvals, rematches, viewing and settlement. Team size remains a CAP: existing manual-start behavior permits equal smaller sides. Preserve scheduled/autostart rules. Do not add team tournaments, recurring team races, new art, new reward tiers, or increase production worker capacity.

## Verified findings

| Area | Evidence | Consequence |
| --- | --- | --- |
| Server maximum | Backend `src/modules/races/services/validateRaceConfig.js:182` rejects non-integers or sizes outside 1–5; create and edit share it. | Raise authoritative bound to 10 after compatibility handling is specified. |
| Storage | Backend `prisma/schema.prisma:1737`; `prisma/migrations/20260715162329_add_team_races/migration.sql` uses nullable integer `team_size`, not a five-value enum. | Size expansion itself needs no column migration or backfill; update stale comments. |
| Create/edit controls | `lib/screens/create_race_screen.dart:1124`; `lib/screens/edit_race_screen.dart:151`, `:442`. | Update both steppers and edit initialization; prevent displaying 10 as 5. |
| Lobby truncation | `lib/widgets/team_lobby_board.dart:205` clamps size to 5. | Existing binaries cannot display slots 6–10. New binary must render every accepted member. |
| Lobby height | Same widget `:106`, `:223`: 64-pixel rows and 10-pixel gaps. | Five rows = 360 logical pixels; ten = 730, before header. Preserve readable rows and page scrolling; do not squeeze 20 avatars into today's height. |
| Details paging | `lib/screens/race_detail_screen.dart:689`, `:1368` requests 15. Backend `queries/getRaceDetails.js:222` pages team details too; `routes.js:1500` returns non-active bootstrap with progress null. | Pending bootstrap can omit accepted members. Invited/declined rows also consume page slots; merely requesting 20 does not guarantee 20 accepted members. |
| Progress distinction | Backend `queries/getRaceProgress.js:1746`, `:2078` explicitly excludes teams from active paging; non-active progress returns accepted roster at `:2033`. | Do not claim all progress is truncated. Preserve full authoritative team progress and repair details/bootstrap completeness, including error fallback. |
| Membership/scoring | Backend `teamRaces.js:7`, `:20`, `:33`, `:74` counts/sums dynamically; `commands/startRace.js:108` allows equal sides of at least one. | No hardcoded five-person scoring algorithm found. Preserve locking, capacity and equal-start rules. |
| Frozen-client boundary | Backend `teamRaces.js:54`; app `backend_api_service.dart:403` uses `team_races` for every current team-capable binary. | Existing token cannot distinguish a five-slot renderer from a new ten-slot renderer. |
| Approval identity | Backend `commands/respondRaceJoinRequest.js:146` constructs requester features from responder input and infers team support from request.team. | New compatibility validation must use the actual joining player's capability, never the owner's device capability. |
| Rewards | Backend `services/teamWinnerReward.js:8` and `services/teamPayoutPlan.js` support stamped fixed per-winner rewards alongside legacy modes. | Preserve versioned payout calculation; do not replace it with a newly inferred pot formula. See economy review below. |

## Proposed API contract and compatibility

Keep the existing endpoints and response fields. Representative changed fields (not complete payloads):

```json
{"isTeamRace": true, "teamSize": 10, "maxParticipants": 20}
```

`POST /races` continues returning HTTP 201 with `{"race": {...}}`; the server derives `maxParticipants = 2 * teamSize`. `PATCH /races/:raceId` with `{"teamSize": 10}` continues returning HTTP 200 with `{"race": {...}}`. Keep optional fields optional. Valid integer sizes become 1–10; 0, 11, fractions and invalid types return 400. Preserve existing `TEAM_FULL`, `TEAM_SIZE_TOO_SMALL`, `TEAMS_UNEVEN`, and already-started error semantics.

Recommended permanent compatibility design: a versioned binary capability, provisionally `team_races_10v10_v1`, in the existing client capability mechanism. This denotes actual rendering support; it is not a runtime release switch. No rollout percentage, environment flag or kill switch is proposed. Existing `team_races` behavior for 1–5 remains intact. Confirm the token naming and implementation contract before code.

For configured sizes 6–10, require this capability for creation, resizing, joining and invite acceptance. Old clients receive the existing recognized `UPDATE_REQUIRED` error envelope, such as `{"error":"Update the app to join this team race","code":"UPDATE_REQUIRED"}`. Suppress incompatible discoveries, suggestions and invite cards consistently; direct links/read endpoints must return a safe recognized update response rather than an unusable roster. Never remove memberships, hide earned rewards, or silently resize a race as a compatibility measure.

Audit all surfaces, not just public discovery: `/races`, `/public`, `/discovery-summary`, Home cards/suggestions, invite preflight, inbox/push links, detail/bootstrap/progress, payout offers, invite/respond, share join, approval join, switching, start, rematch and any internal creation. Preserve ordinary races and old team races byte-for-byte where the expansion is irrelevant. The two current frontend header variants and any explicit request header builders must all advertise the same binary capability.

When a pending 1–5 race grows above five, reject enlargement if an accepted member lacks verified new support; leave race/memberships unchanged. Handle outstanding invites and approval requests explicitly: they must not become an admission bypass after resizing. Membership reads, resize validation and write must serialize with joins/accepts/switches/start under the established per-race lock. The current edit path reads before mutation and must be audited for races with concurrent joins.

Account-stored `clientFeatures` is advisory, not proof of the device making a request: users may have two devices or downgrade. Validate request capability for direct actions. Deferred owner approval must validate the requester independently, retaining an appropriate request-time version stamp if current storage cannot prove support. That may require an additive migration; the numeric size expansion alone does not. Define old-device access for an already-enrolled larger-race member, with safe update responses and preserved balances, payouts and leave/forfeit access, before implementation.

Any cache whose contents vary with support must distinguish the new capability, or apply filtering after shared cache reads. Audit `services/raceListCache.js:61` plus Home/discovery/count caches. Test warm-cache alternation between old/new headers. A new app talking to an old backend must handle rejection clearly without pretending the race was created; deploy server support before shipping the binary.

## Frontend and roster plan

Use the existing parchment/wood team UI and stepper, retaining touch targets and text sizes. Centralize the new app-side bound; update create, edit and lobby. Harden `TeamRace.teamSize` (`lib/utils/team_race.dart:81`) so absent/null/malformed fields cannot throw. Default missing fields safely, and never derive full-side availability, resize floors or scores from a partial roster.

Make accepted roster completeness explicit for team details/bootstrap. Preferred bounded response: up to 20 accepted members with existing privacy fields and authoritative team counts; pending invitation history remains separately bounded/paged. Do not globally disable pagination or uncap invited rows. Pin the additive field/shape and the merge precedence with progress before implementation. Loading/error states must distinguish unavailable roster data from genuine empty slots; a missing progress response must not replace a full roster with a partial details page.

Verify pending, active and completed team boards, target selectors (ten opponents or nine other allies), personal highlighting, edit-floor checks, winner rows, team chat member displays, race cards, invitation and Home layouts. Active progress already supports full team arrays, so retain that path. Both iOS and Android use the shared Dart behavior; include real demo/tutorial mirrors in widget and manual coverage.

## Performance research and measurement plan

20 accepted players is bounded, but more players generate more scoring input, effects, notifications and settlement work. Existing team aggregation itself is linear in participants. Do not infer that total DB CPU merely doubles or that current infrastructure is sufficient from this bound.

Benchmark equivalent 5v5 and 10v10 fixtures against a dedicated local/test DB, including concurrent step sync, team-wide powerups, bootstrap polling and race end. Record whole-request SELECT/INSERT/UPDATE/DELETE counts, rows, duration/p95, worker jobs and downstream writes; separate cold/warm cache cases. Include a fixed-total-user comparison as well as fixed-number-of-races comparison. Stress thousands of synchronized users through bounded concurrency. Preserve current two production HTTP workers; no infrastructure change is justified by code inspection alone.

Prioritize batching actual member-loop database work if these measurements expose material amplification. Preserve transaction safety, effect stacking, eligibility, idempotency and committed payout versions. Any bulk participant-total optimization must use the existing race resolution queue; settlement and coins remain durable Postgres operations. Do not add a cache surface or redesign the entire scoring system merely to raise the cap.

## Tests-first implementation sequence

1. Pin permanent compatibility semantics, roster contract and deferred approval identity. Inventory relevant existing rejection assertions: `test/commands/createRace.teamRaces.test.js:350` and `editRace.teamRaces.test.js:261` currently require size 6 to fail. Explicitly approve the intended requirement change; do not silently weaken/delete those tests. Preserve old-client rejection coverage and add upper-bound-11 rejection coverage.
2. Backend agent writes failing HTTP/real-test-DB coverage for every integer size 1–10, invalid values, capacity20, eleventh on a side, concurrent final-slot joins, shrinking, growing with legacy members, invite/share/approval/rematch entry, equal smaller-side start, uneven rejection and scheduled/autostart. Prove no membership or reward mutations on rejection.
3. Add old/new/no-feature HTTP matrix, cache isolation, downgraded-device behavior, direct endpoints, full-roster detail/bootstrap/progress with >20 total invitation rows, incomplete progress fallback, all20 results, reward previews and settlement parity, retry/double-credit safety. Keep legacy payout fixtures intact.
4. Backend contract is implemented and locked before frontend implementation. Frontend agent writes failing real-screen widget tests for6v6,10v10,20 accepted members, size-preserving edit, last roster row/self visibility, data-error fallbacks, all valid targets, completed results and mirrors. Then update production code.
5. Run relevant tests then full Flutter suite and clean `flutter analyze`; backend targeted integration suite only after confirming a dedicated test database. Run code-reviewer. Build/verify both platforms using README release defines when a release is authorized.
6. Separately authorized backend deployment first; verify deployed endpoints with new headers before app release. Older binaries continue existing sizes; new app can create6–10 only after actual server support. Waiting a week alone is not a compatibility solution. No production or staging service changes during this research.

## Economy review

Game-analyst verdict: SOUND WITH CHANGES. Preserve payout versions, verify all-member flows and coordinated powerup coverage, and test/bound recipient-loop cost. These are code-derived results, not live price/config verification. A read-only DB connection attempt failed certificate validation before any query returned; no database mutation occurred.

For a full fixed-V1 race, winner award R and size n, base issuance is nR. A tie pays all2n members R/2, with the same total. Assuming symmetric teams, no forfeits and excluding ad bonuses:

| Duration | Winner reward | 5v5 issuance | 10v10 issuance | Symmetric EV/player |
| --- | ---: | ---: | ---: | ---: |
| 1 day | 100 | 500 | 1,000 | 50 |
| 2–3 days | 200 | 1,000 | 2,000 | 100 |
| 4–7 days | 500 | 2,500 | 5,000 | 250 |
| 8+ days | 1,000 | 5,000 | 10,000 | 500 |

Replacing two full5v5 races with one10v10 changes no base issuance. Adding ten new participant-race memberships does increase total issuance. Preserve accepted existing no-activity eligibility: zero-step ties and inactive winning teammates currently receive rewards; raising size expands cohort farming, not individual EV. Do not introduce an activity threshold in this size change.

Rally Flag, Uprising and Rainstorm affect twice as many potential members per cast. Equal-activity relative score swing per cast is unchanged, but twice as many teammates can supply casts, making sustained coverage easier. Verify active-team locks, merged windows, protection, and nonmultiplicative overlap behavior. Prices and availability are not rebalanced here.

Inferred inner-loop costs from backend `commands/usePowerup.js:2073`, `:2175`, `:2235`, `:3980` and `commands/completeRace.js:459`, `:489`:

- Rally/Uprising:5→10 beneficiary lookups plus5→10 effect writes per cast.
- Rainstorm, distinct unshielded victims:10→20 defense lookups plus5→10 effect creates, excluding shared work/decoys.
- Settlement:10→20 placement updates; ordinary win5→10 reward calls/payout updates; tie10→20.
- Constant casts per player plus twice as many targets can yield approximately4× aggregate recipient-effect work per race. This is not a whole-request query count or measured CPU multiplier.

No payout redesign is mathematically necessary. Preserve legacy unstamped modes. The analyst added these findings to `docs/economy.md` section4.3a.1; no production economics changed.

## Manual UI-placement test plan

The planner's checklist is reproduced verbatim below. Clarification to its paging risk: active progress already excludes teams from paging; the proven truncation seam is details/non-active bootstrap, plus partial-data fallbacks. Add dedicated team fixtures because solo tutorial replay cannot demonstrate a20-member layout.

**Manual UI-Placement Test Plan — Team races up to 10v10**

*Elements under test:*  
Create/edit size controls: extend existing 1v1–5v5 controls through 10v10.  
Team rosters: extend existing two-column lobby and standings to ten members per side.  
Existing cards, invitation surfaces, target sheets and results: accommodate the larger format and participant lists.

*Checklist* — use prepared pending, active and completed 10v10 races with twenty named participants. Repeat crowded screens on the smallest supported iPhone/Android device with enlarged system text.

1. **Create and edit — real screens**  
   **Get there:** Races → Create → Teams; pending race you own → Edit.  
   **Verify:** 10v10 and its twenty-racer caption fit beside the controls; summary and bottom action remain reachable. No duplicate or overlapping controls.

2. **Pending lobby — owner, member and invitee**  
   **Get there:** Open the prepared pending race from Races, then open it from an invited account.  
   **Verify:** Both columns expose all ten positions, including the last member/empty slot; no roster ends at five or fifteen total participants. Scroll to the bottom actions and back; plaques, counters and invitations do not overlap rows.

3. **Active detail and power-up sheets**  
   **Get there:** Active 10v10 race → standings; inventory → a targeted power-up and a multi-target power-up, without confirming use.  
   **Verify:** Ten members per side are reachable; members appearing after the first fifteen are not missing or duplicated. Target lists scroll to the last eligible displayed opponent; sheet actions stay reachable. Team scoreboard, activity/chat and inventory remain in their intended sections.

4. **Completed detail and results summary**  
   **Get there:** Completed 10v10 race → final standings; open the prepared race-completion summary.  
   **Verify:** Both final rosters and all ten winning-team members are reachable; no clipping, missing last rows or duplicate participants. Completion actions remain below/alongside their intended content.

5. **Home, race lists and invitations**  
   **Get there:** Home → race card/suggestion; Races → pending/active/completed tabs; pending race → Invite friends; invited account → incoming invitation.  
   **Verify:** 10v10 badges, names, counts and action buttons fit. Scroll the invitation list to its final rows; no actions are covered or duplicated.

6. **Demo race tutorial — shared screens and separate coach chrome**  
   **Get there:** Profile → Settings → demo replay, or a fresh account’s demo flow.  
   **Verify:** Create → Invite → race detail remain framed correctly; coach rings still surround their intended controls. If a prepared team-demo fixture is supplied, repeat the ten-slot roster check. Existing solo demo data alone cannot verify 10v10.

7. **Tab tutorial — shared previews and separate spotlight chrome**  
   **Get there:** Profile → Settings → tutorial replay → Home, Races and race-detail preview beats.  
   **Verify:** Cards and detail preview remain visible; spotlights ring their intended elements with no displaced/duplicate controls. A prepared team preview is required to inspect 10v10 placement here.

## Acceptance criteria and remaining decisions

- All capacities1–10 work with no overfill; existing equal-smaller-team start behavior is preserved.
- All20 accepted members remain accessible in lobby, standings, targeting and results, including bootstrap/progress failure cases and invitation-heavy lobbies.
- Older apps retain their existing races and economics; unsupported larger-race actions fail safely with recognized errors.
- No new global toggle, no automatic old-client migration, no unbounded roster query, and no speculative worker increase.
- Current payout stamps and powerup rules remain unchanged unless a separate balance decision is approved.
- Complete compatibility/roster contract, measured load evidence and reviews are implementation/release prerequisites. This research does not claim tests have run or capacity is proven.

Product assumptions for review: all intermediate sizes6–10; public/private parity; pending resizing allowed with compatibility checks; equal smaller teams may still start. These are recommendations, not extra user-approved requirements.

## Revision log

- Gap pass1: distinguished active progress's existing full-team response from paged details; added invitation-heavy lobbies because a limit20 does not guarantee20 accepted players. Added all old-device entry paths and cache variants.
- Gap pass2: added resize/join serialization, approval requester identity, dual-device/downgrade behavior, preserved leave/forfeit/payout access, explicit treatment of protected size6-rejection tests, and separated size-schema sufficiency from possible capability-stamp migration.
- Architect review: APPROVE for research, no required corrections. Incorporated queue/durability constraint and corrected helper reference. Capacity alone does not require a new immutable race stamp: `teamSize > 5` plus permanent binary support identifies the rendering contract. Durable requester/admission proof (or deferring enlargement of populated legacy races) remains a concrete implementation decision. Existing payout stamps remain authoritative.
- Economy review: SOUND WITH CHANGES; included fixed-V1 issuance, existing inactivity policy, coordinated powerup coverage and inferred inner-loop costs. No balance settings changed.
- UI planner: reproduced seven-point manual checklist above; require dedicated team fixtures and preserve the distinction between paged details and full-team active progress. No manual device checks were performed during research.
