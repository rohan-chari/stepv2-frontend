#!/usr/bin/env python3
"""Build an isolated simulator fixture using the real pinned CoreKit binaries.

The fixture intercepts all URL loading and uses dummy app credentials. It never
loads the repository's local Meta configuration or production app container.
"""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, help="Booted simulator UDID")
    parser.add_argument("--output", type=Path, required=True, help="JSON evidence path")
    args = parser.parse_args()
    identifier = "com.bara.meta-smoke.fixture-" + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="bara-meta-sdk-smoke-") as directory:
        root = Path(directory)
        app = root / "MetaSmoke.app"
        frameworks_dir = app / "Frameworks"
        frameworks_dir.mkdir(parents=True)
        frameworks = []
        for pod in ("FBSDKCoreKit", "FBSDKCoreKit_Basics", "FBAEMKit"):
            framework = next(path for path in (ROOT / "ios/Pods" / pod).rglob("*.framework")
                             if path.parent.name == "ios-arm64_x86_64-simulator")
            destination = frameworks_dir / framework.name
            shutil.copytree(framework, destination, symlinks=True)
            frameworks.append(destination)
        plist = {"CFBundleIdentifier": identifier, "CFBundleExecutable": "MetaSmoke",
                 "CFBundleName": "MetaSmoke", "CFBundlePackageType": "APPL",
                 "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
                 "MinimumOSVersion": "14.0", "LSRequiresIPhoneOS": True,
                 "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False,
                   "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [
                     {"UISceneConfigurationName": "Default Configuration",
                      "UISceneDelegateClassName": "SmokeSceneDelegate"}]}},
                 "UILaunchScreen": {},
                 "UIDeviceFamily": [1, 2], "FacebookAppID": "123456789",
                 "FacebookClientToken": "00000000000000000000000000000000",
                 "FacebookDisplayName": "Offline SDK Fixture",
                 "FacebookAutoLogAppEventsEnabled": False,
                 "FacebookAdvertiserIDCollectionEnabled": False}
        (app / "Info.plist").write_bytes(plistlib.dumps(plist))
        command = ["xcrun", "--sdk", "iphonesimulator", "swiftc", "-target", "arm64-apple-ios14.0-simulator", "-sdk",
                   run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"),
                   "-F", str(frameworks_dir), "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
                   str(ROOT / "ios/Runner/MetaAppEventsPolicy.swift"),
                   str(ROOT / "ios/Runner/MetaCoreKitAdapter.swift"),
                   str(ROOT / "scripts/meta_sdk_smoke_host.swift"), "-o", str(app / "MetaSmoke")]
        subprocess.run(command, check=True)
        for framework in frameworks:
            run("codesign", "--force", "--sign", "-", str(framework))
        run("codesign", "--force", "--sign", "-", str(app))
        run("xcrun", "simctl", "install", args.simulator, str(app))
        try:
            run("xcrun", "simctl", "launch", args.simulator, identifier)
            container = Path(run("xcrun", "simctl", "get_app_container", args.simulator, identifier, "data"))
            result_file = container / "Documents/meta-sdk-smoke.json"
            background_requested = False
            for _ in range(40):
                if result_file.exists():
                    break
                if not background_requested and (container / "Documents/ready-for-background").exists():
                    background_requested = True
                    run("xcrun", "simctl", "launch", args.simulator, "com.apple.Preferences")
                    # The intercepted real server configuration uses a 1s
                    # session timeout. Exercise actual OS background/resume.
                    time.sleep(4)
                    run("xcrun", "simctl", "launch", args.simulator, identifier)
                time.sleep(1)
            result = json.loads(result_file.read_text())
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
            print(json.dumps(result, indent=2, sort_keys=True))
            if not result["passed"]:
                raise SystemExit(1)
        finally:
            run("xcrun", "simctl", "terminate", args.simulator, identifier)
            run("xcrun", "simctl", "uninstall", args.simulator, identifier)


if __name__ == "__main__":
    main()
