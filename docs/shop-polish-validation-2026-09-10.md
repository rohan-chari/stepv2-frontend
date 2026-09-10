# Shop and wardrobe polish — build 15

Character names are centered; the persistent footer has only Save outfit (yellow in light mode, themed purple in dark mode). Discard and conflict prompts use the app’s GameContainer, PixelText and PillButton presentation. Locked replaces Unowned; centered locks shade only artwork. Coin packs use full-width themed price bands with one accessible purchase action. Powerups use one grid with larger quantity badges, retaining owned-only inventory and global alphabetical sorting.

No backend/API, prices, rewards, product identifiers or fulfillment behavior changed. Older binaries remain compatible. Both platforms share these widgets; billing retains pending, account and route guards.

Reviewer: SHIP, no outstanding findings. Regression coverage includes semantic checkout and duplicate prevention, sorting including owned-only inventory, locks, centered headers, custom prompts and retained wardrobe guards. Final full Flutter suite: **3,315 passed**; `flutter analyze`: **No issues found**. Runtime source: `12bf042`. Release results are recorded with the release evidence.

Actual widget captures: [Shop](artifacts/shop-polish-2026-09-10/) and [wardrobe](artifacts/shop-wardrobe-polish-2026-09-10/), light/dark at normal and 1.6 text scale. Fixture prices do not charge money.

## Manual UI checklist

- On iOS and Android, check light/dark themes and narrow/large screens with enlarged text. Names stay centered; headers, prices, badges and locks fit.
- Shop: no Buy/Owned Powerup toggle or empty gap; quantities remain visible. Character and Powerup cards match. Owned artwork stays undimmed; locked art has a centered lock without covering labels.
- Open coin packs from Home + and Shop +. Price bands span each card. Art, amount and price activate the same purchase action; VoiceOver/TalkBack exposes one action. Use preview/test billing only.
- Wardrobe: Owned then Locked, no Other owned items. Locked items remain selectable for preview; selected indicators stay clear. Scroll to the last row: Save remains reachable above the safe area, with no Reset.
- Make a draft and go back. Custom discard prompt fits, and Keep editing retains the draft. Check the custom conflict prompt using a test account changed on another device.
- Check Shop and wardrobe tutorial spotlights/copy against the new sections, scene, Save and back button. Check inventory-only/catalog-error fallback still shows owned items.

General tab tutorials and demo race rendering do not use the changed Shop/wardrobe chrome. Physical-device visual checks remain a user checklist; automated fixture captures are not a substitute for them.
