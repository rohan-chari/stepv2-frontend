# Combined preview and coin-pack release

The user authorized building, uploading and replacing the waiting App Review
build, including the updated purchase products. The user separately authorized
the production backend deployment. Target iOS 2.3.13 (21), Android 203151;
manual App Store release remains required. No Play upload.

Included changes: owner Trail Mine placement in Active Effects; read-only
accessory previews with server-compatible character fallback and existing menu
styling; removal of character/accessory locks and scrims; coin packs of
500 / 3,000 / 7,500. Stable purchase IDs and historical receipt/refund grants
are preserved. Apple's configured USD prices were read back as
$0.99 / $4.99 / $9.99 before release. No price schedule mutation is planned.

Source: frontend build commit32531e9; backend92b386e based on current
productionb8a2969, preserving previously released paged odds and coin quantities.
There is no migration, dependency or configuration change. Existing PM2 worker
capacity and stopped staging are preserved.

Combined frontend checks70/70 passed and flutter analyze is clean. Exact
backend target30/30 HTTP integration tests passed on verified local test DB.
Independent combined reviewSHIP. Earlier broader feature/billing tests and
manual placement checklists are recorded in the component release notes.
Previously established unrelated36admin-suite failures were not rerun.

Both signed native artifacts passed source/configuration/freshness checks.
Backend deployment and live preview/billing/compatibility smoke passed, with
zero referral catch-up rows missing after the required audit/apply/audit.
iOS upload succeeded at2026-09-10T22:04:31.707Z; existing AppLovinSDK and
FBAudienceNetwork missing-dSYM warnings were nonblocking. Apple confirmed build21 VALID / IN_BETA_TESTING and membership in the existing
bara testers group at2026-09-10T22:10:28.855Z. Build ID:
`dae8354c-1c81-4410-88d0-4919d8dc31db`.

Replaced reviewec62661c-7eae-4d3f-902b-8bf841b4fbd9 with submission
`0b98ab5f-bb2a-4f90-af98-86cc2eef1225`, submitted at
`2026-09-10T22:11:08.35Z`. Final readback confirms **WAITING_FOR_REVIEW**,
version2.3.13/build21, and exactly four items: app version plus500/3000/7500
coin-pack versions. All three purchase products are WAITING_FOR_REVIEW, have
correct localized names and complete review screenshots, and retain their
configured USD prices. RevenueCat names were also read back successfully.
**MANUAL** App Store release remains set; no customer release or Play upload.

Full signed-artifact, TestFlight, product-price and submission evidence is under
`docs/artifacts/combined-preview-21/`. Backend docs-only followup `dfa7deb`
records deployment while runtime remains92b386e.


Manual UI placement checks remain in the [feature checklist](trail-mine-visibility-accessory-preview-requirements.md#manual-ui-placement-test-plan)
and [coin-pack checklist](coin-pack-amounts-release.md#manual-ui-checklist).
These are device checks for the user; no physical-device purchase or UI pass
is claimed by the release automation. Automated real-widget and HTTP checks
are the validation evidence above.
