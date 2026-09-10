# Shop and outfit follow-up — 2026-09-10

The owner explicitly requested direct implementation and release after these
additions; no new spec or approval gate applies.

## Bara+ restoration

Bara+ is on hold in this app build. Commented entry points are retained in
`shop_tab.dart` (Featured composition and membership focus),
`get_coins_screen.dart` (card), `profile_tab.dart` (badge), and
`billing_preview_app.dart` (navigation destination). Restoring preview navigation
also requires restoring its page-index mapping. Shop's retained membership sheet
keeps its account-change cleanup. Restore its import and remove the documented
unused-method suppression when re-enabling the entry.

The standalone membership screen, billing catalog, account reconciliation,
subscription handling, and existing member benefits remain implemented. Existing
discounted prices still apply without Bara+ branding. This is a UI change, with no
runtime flag, API change, subscription cancellation, or backend deployment.

## Manual UI checklist

Produced by the UI-test-planner; these are device checks for the owner, separate
from automated verification.

Latest additions: Shop and wardrobe back controls are icon-only. The preview
uses the existing Home day/night environment and walking draft character. A
top-right green check means saved; a red information icon means unsaved and opens
an explanation. Selected accessories have an explicit badge as well as the
selected border/status. The old preview-state text is removed.

- Check one arrow in each header, no Back/Back to Characters text, comfortable
  tap areas, and one labeled VoiceOver/TalkBack focus target.
- Preview Capybara, Corgi and Turtle with large accessories: feet align with the
  ground during the walk, outfit art stays inside the scene, and no old white
  card or duplicate avatar remains. Check both day and night and reduced motion.
- Select an accessory: its marker stays inside the tile without covering art or
  labels. Tap the red information icon; the explanation and dismissal control fit
  above the footer. Saving/resetting restores the green check appropriately.
- Tutorial highlights must surround the new scene, floating Save, ownership
  sections and arrow-only back control. The scene status icon and coach controls
  must remain clear of one another.

1. **Home → Shop:** Featured, Powerups, Characters & Accessories appear in order
   with descriptions. Powerup and character cards match dimensions and columns.
   Only unowned characters have locks, contained within the card. No Bara+ row,
   membership retry, or space reserved for them remains.
2. **Home/Shop coin +:** Coin offers scroll into view after loading. No membership
   panel opens; Powerups follows the offers without overlap.
3. **Owned character → Edit outfit:** Owned precedes Unowned, with each compatible
   accessory shown once. Other owned items is absent. Exactly one Save outfit
   action remains above the bottom safe area while scrolling. The final row and
   Load more can scroll fully into view and remain tappable.
4. **Character navigation:** Locks do not intercept card taps. Unowned characters
   still open the buy sheet; owned characters open customization. The floating
   Save control does not leak onto Shop or purchase sheets. Back and close work.
5. **Settings → Help & Legal → View Shop Tutorial:** Check Shop section highlights
   and the wardrobe Save, preview, accessory, and back highlights. Coach controls
   remain reachable, including near the floating action. No removed UI returns.
6. **Profile and View Tutorial:** Check ordinary and existing-member accounts.
   No Bara+ badge or promotion remains. Profile spacing and Home's Shop spotlight
   remain correct. Existing discounts and owned items are preserved.
7. **iOS and Android, light/dark, narrow/large text/tablet:** Descriptions and
   ownership headings wrap cleanly. Merchandise geometry matches. Save stays
   above the home indicator/navigation bar and does not obscure the final row.
8. **Billing preview:** Shop, Coins and Profile navigation retain their intended
   destinations after Bara+ removal. Shared Shop and wardrobe match the app.

The race demo does not render these merchandise layouts. The general tutorial
uses the shared Profile and Home surfaces covered above. Legacy Get Coins is
retained but has no current production constructor call site.

## Version compatibility

The frontend continues consuming the existing wardrobe and billing contracts.
Hidden incompatible accessories retain their preservation data; editing must not
erase an existing saved outfit merely because an item is absent from the grid.
Older app versions and backend behavior are unchanged. Coin fulfillment remains
server-authoritative; no real-money purchase is performed by automated checks.
