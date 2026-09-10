#!/usr/bin/env python3
"""Compile and run the native consent/lifecycle contract without an app build."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="bara-meta-native-tests-") as directory:
    executable = Path(directory) / "meta-tests"
    subprocess.run(["swiftc", "-warnings-as-errors",
                    str(ROOT / "ios/Runner/MetaAppEventsPolicy.swift"),
                    str(ROOT / "scripts/meta_app_events_native_tests.swift"),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

# Structural version guard: only iOS26 simulator is installed locally, so
# executing the real legacy setter on iOS14-16 requires a device/older runtime.
adapter = (ROOT / "ios/Runner/MetaCoreKitAdapter.swift").read_text()
assert "if #unavailable(iOS 17) {\n      Settings.shared.isAdvertiserTrackingEnabled = enabled" in adapter
assert "Settings.shared.isAdvertiserIDCollectionEnabled = enabled" in adapter
assert "setTrackingPermission(false)" in adapter
print("Legacy iOS14-16 public ATE setter branch is present; runtime device check remains.")
