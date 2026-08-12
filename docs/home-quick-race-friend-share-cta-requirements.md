# Home quick-race friend-share CTA requirements

## Summary and user story

When the existing Home Next Race card is eligible to offer quick creation and
the app has successfully loaded fewer than five accepted friends, the card
uses a share-first message. The user should understand that they can create a
race, send its link, and automatically become Bara friends with someone who
joins through that link.

As a new or lightly connected user, I want the empty-race prompt to explain how
to invite people I know so I can start a race and build my Bara friend list at
the same time.

## Locked product behavior

- The share-first variant appears only when all of these are true:
  - the authenticated user envelope advertises the literal capability
    `featureFlags.quickRaceShareAutoFriendEnabled: true`; and
  - the server-owned `nextRace` state is resolved, eligible, visible, and has
    `createEnabled: true`; and
  - `friendsStepsState` is successful; and
  - the accepted-friends list contains zero through four entries.
- The existing server-owned Next Race eligibility remains the authority for
  the race-membership rule. It already excludes users who are in a qualifying
  non-Daily/Weekly race while allowing the section for users whose only race
  memberships are the automatic Daily/Weekly challenges.
- At exactly five accepted friends, use the normal quick-race copy.
- While friend data is absent, loading, refreshing, malformed, or failed, use
  the normal copy. Never infer
  “few friends” from unknown data.
- Share-first copy:
  - heading: `RACE WITH YOUR FRIENDS`
  - body: `Create a race, then send the link to your friends. Your race starts when someone joins.`
  - button: `CREATE & SHARE`
- The button opens the existing quick-create duration sheet. A successful
  quick creation continues to open Race Detail with its existing post-create
  share prompt and persistent Share controls.
- The established backend behavior remains unchanged: a successful link
  join automatically creates the canonical accepted friendship unless an
  existing declined/removed suppression rule forbids it.

## Scope and non-goals

In scope: Home Next Race copy/CTA selection, defensive friend-count handling,
widget coverage, and the Home tutorial/mirror placement audit.

Out of scope: changing quick-race creation, starting, share-link generation,
deep-link routing, automatic-friendship rules, Suggested Races ordering, the
Races tab, referral attribution, friend limits, or backend eligibility policy.

## API contract

Every authenticated own-user envelope that already contains `featureFlags`
adds the following optional field:

```json
{
  "user": {
    "featureFlags": {
      "quickRaceShareAutoFriendEnabled": true
    }
  }
}
```

The backend value is the existing server flag of the same name. It is a literal
boolean and defaults to `false`. There are no new request parameters, response
statuses, or errors. Frozen clients ignore the additive key. New clients treat
absent, null, malformed, and false as unsupported and use normal copy.

The accepted-friends endpoint keeps its existing JSON shape. Its client decoder
must eagerly validate every list element as a string-keyed map; one malformed
element fails the fetch closed rather than undercounting friends and selecting
the share-first variant.

## Data model and migrations

No data-model change, migration, backfill, seed, or index.

## Frontend implementation plan

1. Add an opt-in `quickRaceShareAutoFriendEnabled` value to `AuthService`,
   populated only by the literal authenticated-envelope flag and reset safely
   by an authoritative old-backend envelope that omits it.
2. Derive the presentation inside `HomeTab` from that capability plus
   `friendsStepsState.isSuccess` and `friendsSteps.length < 5`. The Next Race
   widget remains gated by the parsed server state, so the variant cannot
   appear for an ineligible user. This keeps real-screen widget tests on the
   same production derivation and prevents direct callers from forcing it.
3. In `_NextRaceSection`, switch only heading, body, and button label. Reuse
   the existing game-frame, typography, spacing, icon, semantics, and callback
   so it remains visually native to Bara on iOS and Android.
4. Do not add a second share layer. The CTA describes the existing create-then-
   share flow and the existing Race Detail prompt owns actual link sharing.

## Loading, empty, and error behavior

- Capability true plus successful zero-to-four friend data: share-first copy.
- Successful five-or-more friend data: normal copy.
- Capability absent/false, or initial/loading/refreshing/error/unknown friend
  data: normal copy.
- `nextRace` absent, malformed, unresolved, or ineligible: preserve the
  existing hidden-state behavior.
- `createEnabled: false`: preserve the existing Open Races copy and do not
  render the share-first CTA, regardless of friend count.

## Backward compatibility and rollout

Deploy the additive backend capability first with the existing runtime flag
off, then ship iOS and Android in lockstep. After the carrying build is broadly
available, enable `quickRaceShareAutoFriendEnabled`; the same flag atomically
enables backend automatic friendship and advertises truthful share-first copy.
Disabling the flag is the rollback: auto-friend stops and capable clients fall
back to normal copy after the existing authenticated-user cache window. Frozen
clients ignore the new field. A newer app against an older backend sees the
field as absent and uses normal copy.

## Tests-first plan

- Pump the real `HomeTab` before changing production logic and prove the new
  share-first assertions fail.
- Backend integration coverage proves every authenticated envelope advertises
  the existing flag as literal true/false without changing frozen keys.
- Auth-state coverage proves true is applied and authoritative absent/null/
  malformed/false values clear the capability.
- Capability true with successful counts 0 and 4 shows the share-first
  heading/body/button.
- Count 5 shows the established heading/body/button.
- Missing, loading, refreshing, and error friend states show established copy.
- A malformed friends-list element fails decoding and the real widget path
  keeps normal copy without crashing.
- A share-first button tap calls the same `onStartQuickRace` callback.
- `createEnabled: false` retains Open Races and never shows the share-first
  copy.
- Tutorial preview remains free of the Next Race section.
- Add a compact-width/text-scale widget case for the longer copy and button.
- Run the focused Home/Next Race suites, repository-wide `flutter analyze`,
  and diff check. Report any pre-existing repository-wide failure plainly.

## Acceptance criteria and definition of done

- Every locked behavior above has real widget coverage written before the
  implementation.
- No existing assertion is weakened or skipped.
- The existing create/share/auto-friend path is reused; only its existing
  runtime flag is exposed additively to authenticated clients.
- Focused tests and scoped analysis pass; any repository-wide unrelated
  failures are reported plainly.
- The required architect, UI-placement planner, frontend/backend implementer,
  and final code-reviewer checks run. The manual checklist is handed to the
  user.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Home quick-race friend-share CTA**

*Elements under test:*  
Share-first heading, body, and `CREATE & SHARE` button replace the normal quick-race copy inside the existing Home Next Race card; the card itself remains between pending invites/SETUP and Today’s Coins.  
No new share surface is added to Home; the existing duration sheet and Race Detail share prompt/controls remain in their established locations.

*Checklist*

1. **Home — real screen, 0–4 accepted friends**
   - **Get there:** On staging, sign in with a quick-create-eligible account having 0–4 accepted friends and no qualifying non-Daily/Weekly race → finish onboarding if required → Home.
   - **Verify:** One Next Race card appears in its existing slot above Today’s Coins. The share-first heading, body, and `CREATE & SHARE` button are together inside that card. The old `START YOUR OWN RACE` / `START A RACE` presentation is not still present, and no duplicate CTA or separate share panel appears elsewhere on Home. Repeat once on iOS and once on Android.

2. **Home — real screen, normal-copy states**
   - **Get there:** Use staging accounts/states for exactly 5 accepted friends, and for friends still loading or failed, while Next Race remains quick-create eligible → Home.
   - **Verify:** The normal quick-race presentation remains in the same Next Race card position. The share-first heading/body/button do not appear anywhere, and there is only one Next Race card.

3. **Home — real screen, Open Races and hidden states**
   - **Get there:** First use a staging account whose resolved Next Race has `createEnabled: false`; then use an account in a qualifying non-Daily/Weekly race or with Next Race unavailable.
   - **Verify:** With creation disabled, the single card stays in its usual slot and shows only the Open Races presentation; neither quick-create CTA variant appears. When Next Race is ineligible/unavailable, the entire section is absent with no blank slot, orphaned button, or CTA elsewhere on Home.

4. **Quick-create handoff — Home to Race Detail**
   - **Get there:** From checkpoint 1, tap `CREATE & SHARE`, choose a duration, and complete quick creation.
   - **Verify:** The existing duration sheet appears over Home; no separate share sheet or share card is inserted on Home. After creation, Race Detail opens with the existing post-create share prompt immediately below the race hero and the persistent Share control in the waiting-for-another-walker area. Neither share surface is duplicated.

5. **Tab tutorial — Home preview beats**
   - **Get there:** Profile → Settings → View Tutorial. Check the first Home beat (`Just walk.`), advance through the tutorial, then check the final Home beat (`Win coins.`).
   - **Verify:** The Next Race section—including both the share-first and normal quick-race presentations—is absent with no empty gap. On the first beat, the spotlight still rings the step total in the hero; on the final beat, it still rings the Shop button. No CTA overlaps either spotlight or tutorial callout.

6. **Legacy spotlight onboarding — Home preview beats**
   - **Get there:** On a test configuration with onboarding v3 disabled and the spotlight tutorial owed, sign in with a fresh account → onboarding → tutorial; inspect its first and final Home beats.
   - **Verify:** The same absence and spotlight placement from checkpoint 5 holds: no Next Race CTA appears, and the step-total and Shop spotlights ring their intended elements.

*Surfaces confirmed unaffected:*  
Playable v3 demo race — `DemoRaceHost` renders Create Race and Race Detail, never `HomeTab`, so it has no Home Next Race CTA checkpoint.  
Demo race fixtures — `demo_race_engine.dart` and `demo_race_api_service.dart` do not feed a Home surface or `nextRace` card.  
Races, Friends, Leaderboard, and Profile tutorial previews — the CTA is owned only by the real `HomeTab`; these previews do not render it.  
Tutorial tab bar — the hand-copied `WoodenTabBar` contains navigation only; this change neither adds nor reorders a tab item.

*Risks found while planning:*  
The tutorial passes `friendsSteps: []` without a successful `friendsStepsState`; deriving “few friends” from the raw empty list inside `HomeTab` would make tutorial fixtures look eligible. Keep the variant opt-in default false and derive it in `MainShell` only after a successful friends load.  
Tutorial suppression is currently doubled: `isTutorialPreview: true` forces `nextRace` to null, and `tutorialPreviewHomeRaceCard()` fabricates no `nextRace`. Removing either safeguard later could expose the CTA and shift tutorial content.  
The Next Race card carries no tutorial spotlight key. The relevant Home anchors remain on the hero step total and Shop button, so no key migration is required, but both Home tutorial beats must still be eyeballed.  
`DemoRaceHost` has no Home mirror; adding hand-copied CTA chrome there would be an unintended new surface.

## Revision log

- Gap pass 1: made the server-owned Next Race eligibility authoritative instead
  of duplicating race-membership classification in Flutter; specified the
  exact boundary at five accepted friends.
- Gap pass 2: added fail-safe behavior for unknown friend state, protected the
  `createEnabled: false` branch, and prohibited a duplicate share surface.
- UI planner: confirmed tutorial suppression must remain opt-in/default-false,
  identified both Home spotlight beats, and confirmed DemoRaceHost has no Home
  mirror to update.
- Architect review: required the existing server-only auto-friend flag to be
  exposed as a fail-closed client capability; resolved refresh semantics to
  success-only; required eager malformed-friend validation and production-path
  tests; strengthened rollout/rollback and repository-wide analysis gates.
