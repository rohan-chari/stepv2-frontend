# Meta US consent parsing fix — 2026-09-10

> Release follow-up: [TestFlight build 16](meta-consent-testflight-16.md) is now
> verified and available to internal testers. The release ran all 3,315 Flutter
> tests and built/verified both production artifacts; the original fix-only
> validation and its limits below are retained as a record.

## Cause and behavior

Google UMP writes only `IABGPP_GppSID` and `IABGPP_HDR_GppString` for
US consent. Bara previously required expanded per-field US keys, so valid
compact-only choices were denied. A second assumption required a European
`gdprApplies=0` key for an obtained US message, although US applicability is
already supplied by GPP. Neither issue proves that the owner's observed
session was affected: Events Manager subsequently showed install, activation,
and Shop events for the carrying build.

The native policy now decodes the GPP header and applicable US sections in
memory. It supports the existing section IDs 7–27, US National versions 1/2,
legacy USP section 6, optional GPC, and the optional IN/KY/RI sensitive-data
segments. A missing optional segment is distinguished from a malformed one.
Unknown applicable sections, unsupported versions, malformed/truncated input,
invalid padding, missing applicable payloads, explicit opt-outs and conflicting
expanded/encoded signals deny collection. Parsing has explicit input, section,
and Fibonacci bounds. No CMP storage is written or synthesized.

Current-launch CMP resolution remains mandatory. European Additional Consent
requirements and ATT gating of advertiser-ID collection remain in place.
Existing expanded-only signals retain their prior behavior. Android has no
native Meta acquisition-event implementation and continues using the existing
no-op boundary. This fix does not change Android partner-ad consent handling.
No backend/API, configuration, dependency, UI, flag, or version-number changes.
Older app binaries continue their existing behavior; the fix takes effect only
when users install a carrying build. No migration or coordinated deployment.

## Sources and fixture provenance

- [Google UMP US signal storage](https://developers.google.com/admob/ios/privacy/us-iab-support#read_consent_choices).
- [IAB GPP format](https://github.com/InteractiveAdvertisingBureau/Global-Privacy-Platform/blob/main/Core/Consent%20String%20Specification.md).
- [Official IAB encoder](https://github.com/IABTechLab/iabgpp-es/tree/fd0546e7b28e7e186bc27aac6375e6c10a80e47e),
  version 3.2.0, Apache-2.0; used only as a temporary offline reference.

`scripts/fixtures/meta_gpp.json` contains 99 independently encoded cases from
that reference: each supported US section's allowed choice, every relevant
opt-out, GPC true/absent, US National v1, contiguous header ranges and
noncontiguous section offsets. The generator accepts a compiled official
`GppModel.js` path:

```bash
node scripts/generate_meta_gpp_fixtures.mjs <official-encoder>/GppModel.js
python3 scripts/run_meta_native_tests.py
```

No IAB library is linked into Bara. Parser math and malformed-signal cases use
native tests; actual lifecycle/SDK serialization is verified separately below.

## Verification

- Before the fix, the new native fixture failed at `usnat: allowed collection`;
  the protected existing policy/lifecycle assertions still passed.
- The real SDK smoke fixture was changed to evaluate actual compact-only CMP
  signals through the product policy, instead of supplying a preapproved
  permission. Before the fix, it produced **zero** requests and failed install,
  activation and Shop serialization checks.
- After the fix, native policy/lifecycle tests, all **99** independent cases,
  and malformed/contradictory signal tests pass. The runner now isolates its
  compiler cache in its temporary directory.
- The real pinned CoreKit **18.1.1** fixture passes all **16** checks: six
  intercepted requests, install/activation/Shop serialization, and no new
  event after an encoded US sale opt-out. Regrant and long resume work.
  Before/after artifacts are in `docs/artifacts/meta-gpp-fix-2026-09-10/`.
  The fixture compiles the real native policy/adapter for iOS14 and runs on
  an isolated iOS26.5 simulator with dummy credentials and intercepted HTTP.
- `flutter analyze`: clean.
- Six relevant Flutter suites: **35 tests pass**, including real Shop,
  consent bootstrap, privacy refresh, native configuration and platform guard.
- Independent code reviewer: **SHIP**, no remaining findings. An optional
  IN/KY/RI segment rejection caught by both fixtures and review was corrected.

Full Flutter suite and production iOS/Android artifacts were not rebuilt for
this native policy fix. No upload or release was performed. Simulator transport
checks prove the fixed SDK path, not live receipt for a future carrying build.
After that build is installed, verify US allow/opt-out/regrant on a physical
device and confirm allowed events in the correct Events Manager app.
