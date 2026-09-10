# Meta native validation — September 10, 2026

> The expanded-US-signal-only implementation described below was corrected by
> the [US GPP parser fix](meta-gpp-fix-validation.md). That document supersedes
> its US parsing and smoke-fixture details; this file retains the original
> release validation record.

The native integration is implemented in `MetaAppEventsPolicy.swift`,
`MetaAppEventsCoordinator.swift`, and `MetaCoreKitAdapter.swift`. AppDelegate
creates the coordinator before plugin registration and attaches its narrow
channel. `lib/main.dart` connects the existing CMP resolution/invalidation
callback independently of ad eligibility. No backend contract changes.

## Permission behavior

Successful current-launch UMP resolution is mandatory. GDPR uses Google AC
provider 89's consented segment, with valid v1/v2 syntax, including `dv` and
`dv.`. Disclosed-only membership is rejected. No Meta TCF purpose-bit mask
is inferred from another mediation partner's registration. Native UMP
`notRequired` cannot override contradictory GDPR or malformed/denied signals.
Applicable unknown GPP sections or missing required expanded fields fail closed.

GPP sections 7–27 use their individual IAB schemas: National has sale, sharing,
targeted-advertising and GPC; California has sale, sharing and GPC; remaining
states have sale and targeted advertising. Virginia, Utah, Florida, Indiana,
Kentucky and Rhode Island do not define the GPC subsection in these schemas.
The integration reads standardized expanded CMP fields rather than decoding
the compact GPP payload. Unknown applicable sections remain denied. Existing
legacy USP sale opt-out is respected too.

Sources: [Google AC specification](https://support.google.com/adsense/answer/9681920?hl=en),
[IAB GPP state specifications](https://github.com/InteractiveAdvertisingBureau/Global-Privacy-Platform/tree/main/Sections/US-States),
[IAB US National specification](https://github.com/InteractiveAdvertisingBureau/Global-Privacy-Platform/tree/main/Sections/US-National),
[IAB in-app storage/CMP specification](https://github.com/InteractiveAdvertisingBureau/Global-Privacy-Platform/blob/main/Core/CMP%20API%20Specification.md).

ID collection requires Meta permission plus ATT authorization. iOS14–16 also
set CoreKit's public legacy advertiser-tracking property from that same gate;
iOS17+ CoreKit reads ATT directly. No new ATT prompt. Missing/unresolved Debug
configuration disables measurement safely; Release/Profile configuration is
validated before compilation by the existing Flutter build phase. Supply
`META_APP_ID` and `META_CLIENT_TOKEN` through the normal Flutter `--dart-define`
arguments in README. The automatic shell phase decodes those two values from
`DART_DEFINES` into `$(DERIVED_FILE_DIR)/BaraInfo.plist`, preserving the source
plist's fixed Bara display name and disabled privacy defaults. All three native
configurations process that derived file. No manual helper or xcconfig secret
file is required. Invalid or missing Debug values clear both keys, including
after a previously configured build; Release/Profile fail before Flutter runs.

## Native checks

```bash
python3 scripts/run_meta_native_tests.py
python3 -m unittest discover -s scripts -p test_meta_ios_build_phase.py
```

Both pass. The native Swift executable checks unresolved/denied consent,
AC variants and malformed values, missing config, contradictory applicability,
all 21 supported US schemas (including each opt-out and missing field), GPC,
USP, ATT, background-only launch, delayed grant, withdrawal, regrant,
foreground-epoch deduplication, and narrow event rejection. New policy tests
were red before implementation; additional missing-config and malformed-header
cases were likewise observed red before their fixes. The eight configuration
tests pass. They cover space-containing paths, missing/partial input, malformed
base64, duplicate keys, command injection, trailing newline/NUL, unrelated
defines, source-plist preservation and incremental token changes. A minimal
native Xcode fixture executes the committed phase and real
`ProcessInfoPlistFile` for fresh Release, incremental Release, Profile and
unconfigured Debug builds; it verifies resolved bundle metadata and privacy
defaults. These replace the superseded manual Python/xcconfig configuration
tests after the user requested normal Dart defines. Existing Flutter native configuration tests pass;
root's full Flutter run covers the real CMP bootstrap tests and product events.

All three native Swift files typecheck against actual pinned CoreKit18.1.1,
UMP and Flutter frameworks with warnings treated as errors, targeting iOS14
simulator. This checks the legacy availability branch compiles; no iOS14–16
runtime is installed locally, so executing its setter remains a device check.

## Actual pinned SDK serialization

```bash
python3 scripts/run_meta_sdk_smoke.py --simulator <booted-disposable-simulator-udid> \
  --output docs/artifacts/meta-native-2026-09-10/sdk-smoke.json
```

The harness compiles the **real product policy/lifecycle and CoreKit adapter**
into an isolated UIKit simulator app using the actual pinned SDK frameworks.
Every run uses a fresh bundle/container and dummy Meta credentials. It does
not read Bara's local client token or production application container. The
fixture explicitly installs a URL protocol in the default URL-session
configuration before initializing CoreKit. HTTP bodies are decoded in memory;
the artifact records only checks/counts, not identifiers or request payloads.

The [final result](artifacts/meta-native-2026-09-10/sdk-smoke.json) passes all
16 checks on an iOS26.5 iPhone17 Pro simulator, including a repeat after the
configuration migration to Flutter Dart defines:

- No SDK requests before consent; foreground grant after a delay serializes
  real `MOBILE_APP_INSTALL`, `fb_mobile_activate_app` and `bara_shop_viewed`.
- Automatic logging and advertiser-ID collection remain disabled.
- Signup is rejected by the native allowlist. Withdrawal sets explicit-only
  flushing, disables ID collection, rejects the subsequent race action, and
  never serializes that rejected action.
- A quick resume coalesces into the current SDK session. An actual OS
  background/foreground cycle lasting four seconds, beyond the intercepted
  server configuration's one-second session timeout, serializes a second
  activation and the previous session's deactivation. Six SDK requests were
  intercepted in total, with two requests carrying activation events.

CoreKit configures dependencies synchronously inside its public launch method
before deferring other setup. The adapter calls that public method first,
applies settings, and manually activates in the same main-thread operation.
Pre-initialization safety comes from the plist defaults. It does not invoke
AppEvents setters before SDK configuration. NotificationCenter does not promise
observer priority: early observer registration is retained, and the actual
timeout-expired resume test verifies this SDK/runtime combination instead of
claiming a universal ordering guarantee.

An [earlier failed smoke result](artifacts/meta-native-2026-09-10/failed-smoke-registration-only.json)
is preserved from tool output. Global `URLProtocol.registerClass` alone did
not intercept CoreKit's NSURLSession on this simulator. That isolated run used
dummy credentials and attempted Facebook requests; it was terminated and
uninstalled. The final fixture explicitly configures its URLSession protocols
and passes the serialized-payload checks. An earlier attempt on the existing
simulator also stayed inactive behind an Apple account prompt; root supplied
a fresh disposable simulator, with no account interaction required.

## Practical limits and remaining device verification

These tests prove SDK serialization through the real pinned transport path,
not receipt by Meta's servers or AEM campaign eligibility. Root owns the final
paired app builds and independent review. Before declaring measurement
operational, verify on a physical device in the correct Meta Events Manager
data source: accept/reject, disclosed-only89, privacy edits, ATT denied and
authorized, real long background/resume, existing-install upgrade, and a
background Health launch. Verify older iOS ATE behavior on a supported device.

Withdrawal stops Bara's new explicit events and ordinary automatic flushing.
It does not cancel already-started requests, purge SDK-persisted data, disable
every SDK lifecycle/storage operation, or suppress every eager internal path.
The app neither removes private SDK observers nor deletes undocumented SDK
storage. Manual activation can include install/session/configuration traffic
and previous-session duration. Published privacy wording and iOS disclosures
must describe that scope; they are handled in the parent release work.
