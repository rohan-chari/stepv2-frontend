# Home header notifications requirements

## Summary and user story

Move the Home notification entry point out of the below-hero content board and
into the hero header. A signed-in user can open Inbox from a compact bell and
understand at a glance whether notifications are unread, without the control
disappearing against the day sun or night moon artwork.

The approved visual direction is a persistent bell in a self-contained,
opaque, pixel-HUD button. The backplate, border, and shadow provide their own
contrast instead of relying on the sky behind the button.

## Scope and non-goals

In scope:

- Add a minimum 44x44 logical-pixel notification button to Home's top hero row.
- Place it at the trailing edge of the existing identity/coin header.
- Show a compact unread badge only when the unread count is positive, capped
  visually at `9+`.
- Keep the button present with no badge at zero unread.
- Preserve the existing Inbox-opening callback and semantics.
- Remove the full-width `NOTIFICATIONS` block below the hero.
- Support compact and regular heights, long display names, text scaling, day
  and night palettes, and both iOS and Android safe areas.

Out of scope:

- Inbox behavior, notification delivery, read state, and backend changes.
- New artwork or changes to the sun/moon assets.
- Feature flags or release controls.
- Backend or database tests; the network/data contract is unchanged.

## API contract

**Locked backend contract: no changes.** Do not add or modify an endpoint,
request parameter, response field, status code, client capability, or runtime
flag for this work. The shell continues obtaining unread state through the
existing authenticated `GET /inbox/alerts` flow and defensively preferring the
existing non-negative `totalUnreadCount`, with the existing non-negative
`unreadCount` fallback. The shell continues passing the resulting local value
to `HomeTab` as `unreadNotificationCount` (defaulting to zero) and passing its
existing Inbox-navigation closure as `onOpenNotifications`.

The header bell is only a new presentation of those already-owned values. It
must not fetch, mutate, or reinterpret notification data itself. Frozen older
clients retain the below-hero card and keep using the same backend routes; new
clients use those routes unchanged.

## Data model and migrations

None. No backend source, Prisma schema, migration, seed, or production/staging
operation is required.

## Frontend implementation plan

1. In `lib/screens/tabs/home_tab.dart`, remove `_buildNotificationsCard` from
   the below-hero quick-actions area.
2. Refactor the hero's first row with explicit width constraints: the name is
   single-line and ellipsized, the bell remains fixed at no less than 44x44,
   and the coin area is bounded and scales down within its allocation. The
   trailing edge must never leave the viewport, including for large balances
   and increased text scaling.
3. Add a private notification HUD button using the opaque secondary-button
   `pillGold` palette, compact border/drop shadow, green bell glyph, and a
   44x44 tap target. Use the existing `onOpenNotifications` callback.
4. Overlay a small high-contrast badge for positive unread counts; render
   `1` through `9`, then `9+`, entirely within the safe horizontal bounds. The
   single semantics node is labeled `Notifications, no unread notifications`,
   `Notifications, 1 unread notification`, or `Notifications, N unread
   notifications` using the actual count even when the visual badge says
   `9+`; icon and badge descendants are excluded from semantics. Expose an
   enabled tap action only when the callback is non-null, preserving the
   tutorial preview's no-navigation behavior.
5. Remove the obsolete `_buildNotificationsCard` method.
6. Preserve tutorial behavior because tutorial/demo surfaces instantiate the
   real `HomeTab`; no forked header implementation should be introduced.
7. Move the compact-mode steps HUD below the complete header and badge bounds
   with a deliberate gap, then confirm it still clears the capybara. A 44px
   bell starting at `topInset + 12` otherwise overlaps the old compact HUD
   position at `topInset + 52`.
8. Move the existing `Key('home-notifications-card')` onto the new tappable
   bell and add a dedicated badge key for state assertions.
9. Update stale comments that describe Home as having no Inbox affordance or
   hiding the notification entry point with unavailable counts.

Loading/error/empty behavior: unread state is already shell-owned and defaults
to zero. Zero renders the persistent bell without a badge. No new nullable
server fields or casts are introduced.

## Backward compatibility and rollout

This is a local layout change in the shared Flutter code and ships identically
on iOS and Android. No deployment ordering is required because the network and
data contracts do not change. Frozen older clients retain the current card;
new clients render the header button against the same backend response.

## Test and verification plan

Verify by:

- Running `dart format` on changed Dart files.
- Running `flutter analyze` and requiring a clean result.
- Updating `main_shell_nav_order_test.dart` for the approved persistent bell
  behavior and covering zero unread, one unread, `9+` capping, accessibility
  semantics, constrained-width overflow, and Inbox navigation through the real
  `MainShell` surface.
- Running the targeted shell suite and the full Flutter suite.
- Manually checking day/night, compact/regular height, zero/positive/large
  unread counts, long names, Inbox navigation, and both platform safe areas.

## Acceptance criteria and definition of done

- Home has a persistent, tappable bell in the hero header.
- The bell remains legible where it overlaps either the sun or moon because
  its opaque backplate supplies contrast.
- Positive unread counts display a badge capped at `9+`; zero has no badge.
- The old below-hero notification section no longer renders.
- Inbox navigation remains unchanged.
- Long names cannot push the action group off-screen.
- iOS and Android are accounted for and `flutter analyze` is clean.
- The required UI-placement and code-review checks are completed.

## Manual UI-placement test plan

1. **Real Home — regular-height device, day**
   - **Get there:** Sign in on an iOS or Android device at least 760 logical
     pixels tall → Settings → Appearance → LIGHT → Home.
   - **Verify:** The header order is display name, coin balance, then bell at
     the trailing edge; the bell sits on its own backplate and remains fully
     visible where the day sun passes behind it. Confirm no `NOTIFICATIONS`
     block remains below the hero and no second bell appears there.
2. **Real Home — regular-height device, night**
   - **Get there:** Settings → Appearance → DARK → Home.
   - **Verify:** The bell remains in the same trailing header position and
     fully visible where the night moon passes behind it. Confirm the old
     below-hero notification block is still absent.
3. **Real Home — compact device and safe areas**
   - **Get there:** Open Home on a device below 760 logical pixels tall; check
     one notched iPhone and one Android device/emulator with a status-bar
     cutout or inset.
   - **Verify:** The name, coin control, and bell remain on one header row below
     the status bar; the bell is not clipped by the screen edge, notch, or
     cutout and does not overlap the centered steps HUD. Scroll Home and
     confirm the old notification block does not appear farther down.
4. **Real Home — constrained header content**
   - **Get there:** Set the account to a very long display name → increase
     system text size to the largest supported accessibility setting → return
     to Home on the compact device.
   - **Verify:** The display name truncates or yields space first; the coin
     control and complete bell/badge stay on-screen at the trailing edge
     without wrapping, overlapping, or being pushed beyond the safe area.
     Confirm the old notification block is not restored.
5. **Real Home — unread badge variants**
   - **Get there:** Use accounts or inbox fixtures with unread counts of `0`,
     `1`, `9`, and `10+`, returning to Home after each state.
   - **Verify:** Zero shows the bell in the header with no badge; `1` and `9`
     show those exact compact badges; `10+` shows `9+`. In every state the
     badge stays attached to the bell, is not clipped by the hero or screen
     edge, and no count/card appears in the old below-hero position.
6. **Real Home — Inbox route**
   - **Get there:** From Home, tap the header bell once with zero unread and
     once with unread notifications.
   - **Verify:** Each tap opens Inbox from the new header position. Return to
     Home and confirm there is still one bell only and no old notification
     entry point below the hero.
7. **Onboarding/tab tutorial — first Home beat**
   - **Get there:** Sign in with a fresh account and enter the onboarding
     tutorial, or go to Profile → Settings → View Tutorial; stop on the
     opening Home/“Just walk” beat.
   - **Verify:** The real Home header includes the bell after the coin control,
     with no badge and no old notification block below the hero. The
     `home.steps` spotlight still rings the step count rather than the nearby
     bell/header.
8. **Onboarding/tab tutorial — final Home beat**
   - **Get there:** Continue the tutorial to its final Home/“Win coins” beat.
   - **Verify:** The bell remains in the same header position with no duplicate
     below the hero; the `home.shop` spotlight still rings the shop target,
     not the bell or its former card location.

The demo race tutorial does not instantiate `HomeTab`. The tutorial's
hand-forked tab bar does not copy the hero header; its Home page embeds the real
`HomeTab`. Other tutorial pages do not render this header.

Risks: tutorial Home supplies neither an unread count nor an open callback, so
it validates only disabled zero-unread placement. The narrow header at large
text size with a long name, large coin balance, and `9+` badge is the primary
overflow risk. Both forced light and dark modes must be checked because the
sun and moon occupy the same upper-right area.

## Revision log

- Gap pass 1: made the bell persistent at zero unread, specified a 44x44 tap
  target, and defined the `9+` badge cap.
- Gap pass 2: added long-name/text-scale constraints, safe-area coverage,
  tutorial reuse, and explicit no-backend/version-skew behavior.
- Architect review: required explicit compact-HUD separation, bounded/scaled
  coin layout, preservation of the existing navigation-test key, exact
  semantics, and disabled tutorial behavior; all were added above.
- UI-placement review: added the eight-surface/state manual checklist and
  recorded the tutorial and constrained-header risks.
- Final implementation: adopted the opaque `pillGold` button palette, kept
  coins adjacent to the username, anchored the bell independently at the
  trailing edge, and moved the badge to the tap target's upper-right corner.
- Verification: updated the previously conflicting protected assertion after
  user authorization and added zero/one/`9+` integration-style widget coverage.
