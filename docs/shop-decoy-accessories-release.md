# Shop Decoy and accessories — TestFlight 2.3.13 (18)

The App Store Connect API-key upload succeeded on September 10, 2026 at
19:43:26 UTC. Apple confirmed **VALID / IN_BETA_TESTING** at 19:49:30 UTC,
with build 18 present in the existing **bara testers** internal group.
[Apple status](artifacts/shop-decoy-accessories-18/testflight-status.json).
The unchanged exempt-encryption declaration matches build 17. A direct group
assignment returned 422 because this group manages availability automatically;
the following read confirmed membership.
The matching signed Android artifact, version code 203148, is retained locally.

Decoy is available for 150 base coins, with the existing membership discount
preserved. The backend prevents reuse in the same race for one hour after an
attack pops it. Natural expiry does not start that cooldown. Rejected use keeps
held items or returns redeemed inventory.

The Shop now has separate Characters and Accessories sections. Unpurchased
accessories open the existing purchase flow directly, and Accessories has an
Edit outfit entry for the active character. Powerup art is displayed at 0.8×
and character art at 1.1× inside unchanged cards. Other screens and source
artwork are unaffected.

Frontend runtime source is `32aa92b`, pushed to main. Backend runtime
`6a0f6c39df749f0abbabe59e935d1341d1347379` was deployed before the upload.
Both additive migrations succeeded; their checksums and the concurrent index
were verified. Live current and legacy catalog requests return 200, the
current catalog offers Decoy at 150 with updated copy, and health/Redis checks
pass. Two HTTP workers and the existing resolution/cron workers are online;
staging remains stopped. Unrelated live catalog settings, environment, and
server lockfile were preserved.

Both signed artifacts passed version, production configuration, signature,
and compiled-code checks. All three Android ABIs match fresh compiler output.
Source fingerprints matched immediately before upload. The existing AppLovin
and Meta missing-dSYM warnings were nonblocking. No App Review submission,
customer release, or Google Play upload was performed.

Validation:

- Final Flutter analysis is clean; 265 relevant tests pass, including Shop,
  wardrobe, billing preview, Decoy stash refund/message, and admin toast tests.
- The full initial Flutter run had 3,284 passing and 43 failing tests. Five
  task-related finder/fixture failures and two admin toast failures were fixed
  and passed on rerun. All 36 remaining historical admin failures reproduced
  exactly on unchanged baseline `eca6acf`; their assertions remain intact.
  **The full Flutter suite is not green.**
- Backend: 3,397 unit tests, 13 new HTTP tests, nine existing Decoy tests, and
  actual migration-isolation tests pass. Related concurrency regressions pass.
  One unrelated Drill Sergeant failure in the expanded wave5 suite also
  reproduces on unchanged baseline `45e622d`; that assertion is retained.
- Independent implementation and late-delta review found no required fixes.
  The runtime rejected creating a separate code-reviewer thread twice because
  of its thread limit. The existing read-only reviewer loaded and applied the
  code-reviewer contract to both repositories and the final commits.

The admin toast tests exposed an existing missing Material ancestor in Tools.
A transparent wrapper fixes the assertion without moving UI. Navigation helpers
now follow Tools → Debugging; every original toast assertion is preserved.

Rendered phone captures confirm the section layout and artwork scale. Their
capture harness omitted MaterialIcons, so those screenshots have placeholder
icon glyphs. Physical-device placement remains a manual check; the full
[manual checklist](shop-decoy-accessories-requirements.md#manual-ui-placement-test-plan)
covers both platforms, Shop entries, outfit editing, tutorial continuation,
and the billing preview.

[Verification report](artifacts/shop-decoy-accessories-18/release-verification.json).
Full artifacts, test logs, baseline evidence, and visual captures are retained
under `build/release-candidates/shop-decoy-accessories-2.3.13-18/`.
