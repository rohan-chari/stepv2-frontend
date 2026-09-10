# Shop Decoy and accessories release

Release candidate: Bara 2.3.13 (18), Android versionCode203148.

Status: implementation verified; release builds and deployment pending.

Requested behavior and the full manual placement checklist are in
[the requirements](shop-decoy-accessories-requirements.md).

Expected verification evidence:
- Decoy restored at150 base coins, existing membership discount preserved.
- Server enforces one hour after consumption, including bulk attacks; activation and natural expiry do not start cooldown.
- Separate Characters and Accessories sections, direct unowned-accessory purchase, Edit outfit entry.
- Only displayed shop artwork scale changes; card and global sprite dimensions remain stable.
- Tests-first backend HTTP/local DB and frontend real-widget coverage, clean Flutter analysis, code review.
- Backend additive migration, verified live catalog and healthy existing worker topology.
- Both signed artifacts with README production configuration and source fingerprints.
- ASC API-key upload, VALID/IN_BETA_TESTING and existing internal tester membership.

Manual physical-device placement remains for the user; automated visual/widget
checks will be recorded separately from device checks.

## Implementation verification
265 relevant Flutter tests pass, including all Shop suites, wardrobe, billing preview, wave5, Decoy inventory refund/message, and admin toast assertions. The full initial run was3284 passed/43 failed;5 task-related finder/fixture failures and2 admin-toast failures were corrected and passed isolated.36 remaining historical admin failures conflict with the previously committed redesign and are retained; all36 failures reproduced exactly on isolated unchanged baseline eca6acf (28 other tests passed). Final flutter analyze is clean. The full Flutter suite is not green.

The admin toast tests exposed a missing Material ancestor in the existing Tools groups; a transparent wrapper fixes it without moving UI. Original toast assertions remain intact.

Backend:13new HTTP tests,9 existing Decoy tests and actual migration isolation pass;3397 unit tests pass. Expanded wave5 has an unrelated Drill Sergeant failure reproduced on unchanged baseline45e622d. Backend integration suite is not claimed fully green.

Independent implementation review found no required fixes, including the late admin wrapper. Runtime rejected creating a separate code-reviewer thread twice (thread limit); the existing read-only architect agent loaded and applied the code-reviewer contract to the combined implementation and late delta.

Rendered phone captures inspected locally at /tmp/shop-powerups-characters.png and /tmp/shop-accessories.png: separate sections, Decoy150, direct accessory cards/edit entry, comparable art scale and unchanged card dimensions. Capture harness omitted MaterialIcons; physical-device glyph/placement checks remain manual.
