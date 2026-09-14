# Otter and Sea Lion publication

Published at user request on 2026-09-14. Otter version `71abf0567ddf` (latest tail revision); Sea Lion version `df5d4edd4b6a`. Backend asset commit `57d9385`; copied static files without restarting services. CDN bytes and public TestFlight manifest verified. Existing admin pipeline mirrored both catalog entries successfully.

Both use CHARACTER, active/testOnly/remoteOnly true; six 96px frames, baseline -0.03125. Price matches freshly verified live Mouse at 1,000 coins before existing server discounts. No new power/scoring behavior. Both granted to exact Rohan and Nathan accounts through locked idempotent transactions; no coins or equipment changed. Private audit retained on production host.

First/repeated live authenticated catalogs for both recipients passed: current TestFlight sees each character; production and TestFlight without remote capabilities do not. Production manifest excludes both. No app build required; economy/code reviews SOUND/SHIP. No integration tests run against production.

## Manual placement checklist

1. As each recipient, open TestFlight Shop → Characters → each animal's wardrobe: one centered character, no clipped otter tail or sea-lion chest/flippers, no neighboring sprite frame.
2. Equip each manually → Home: check a single grounded character and clear surrounding content.
3. Check race cards, race detail and available team slots in both facing directions: no overlap with names, medals or racers.
4. Check leaderboard and public profile slots for full silhouettes and no previous-character duplication.
5. Where available, inspect compatible accessory and referral previews for fit.

Repeat on both supported platforms where a test-channel build is available. Demo/tab tutorials use separate capybara/corgi fixtures and do not validate these animals. Unavailable states and device playback remain manual/unverified.
