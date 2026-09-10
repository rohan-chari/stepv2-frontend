# Admin redesign — TestFlight 2.3.13 (17)

Uploaded on 2026-09-10 with the existing App Store Connect API key. Xcode
confirmed `Upload succeeded` and `EXPORT SUCCEEDED`. Apple confirmed
**VALID / IN_BETA_TESTING**, with build 17 present in the existing **bara
testers** internal group. [Apple status](artifacts/admin-redesign-17/testflight-status.json).

The exempt-encryption declaration matches build 16. A direct group-add request
returned 422 because this group manages build availability automatically;
the subsequent read confirmed membership and installable status.

Source commit `a33cfc84fe1fdfb2a42f0a48bac482b9c79ad232` was pushed to
`origin/main` before building. It contains all pending frontend work: the
[approved admin redesign](admin-redesign-requirements.md), the previously
verified [Meta consent fix](meta-gpp-fix-validation.md), and its build-16
release evidence. Version 2.3.13 remains unchanged; the iOS build is 17 and
the matching Android version code is 203147.

Both signed production artifacts passed version, package, configuration and
signature checks. The actual iOS archive/export and Android AOT libraries
contain the new admin interface. Android packaged code matches fresh compiler
output across all three ABIs. All README-required configuration is retained;
inline native-ad defines remain omitted. Source fingerprints matched again
immediately before upload.

Full Flutter analysis is clean. The 45 existing API/control tests and native
policy/lifecycle checks, including 99 independently encoded GPP fixtures,
passed. Final code review: SHIP. The user waived adding admin tests; the full
Flutter suite and old stacked-layout suites were not rerun. Existing tests
were not weakened or removed.

[Verification evidence](artifacts/admin-redesign-17/release-verification.json).
Artifacts, full reports and logs are retained under
`build/release-candidates/admin-redesign-2.3.13-17/`.

The existing AppLovinSDK and FBAudienceNetwork missing-dSYM warnings were
nonblocking. The Android artifact is retained locally; no Play upload,
backend deployment, App Review submission or customer release was performed.
Physical-device admin placement and live consent checks remain manual; the
admin checklist is in the approved spec.
