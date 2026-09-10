"""Public native build-phase tests. All credentials below are dummy fixtures."""
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/prepare_meta_ios_plist.sh"
APP_ID = "1600882908142439"
TOKEN = "0123456789abcdef0123456789abcdef"
NEXT_TOKEN = "ffffffffffffffffffffffffffffffff"


def encoded(*values):
    return ",".join(base64.b64encode(value.encode()).decode() for value in values)


class MetaIosBuildPhaseTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="Bara build fixture ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.ios = self.root / "ios with spaces"
        self.source = self.ios / "Runner/Info.plist"
        self.source.parent.mkdir(parents=True)
        self.source_values = {
            "FacebookAppID": "", "FacebookClientToken": "", "FacebookDisplayName": "Bara",
            "FacebookAutoLogAppEventsEnabled": False, "FacebookAdvertiserIDCollectionEnabled": False,
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "GADApplicationIdentifier": "unchanged-admob",
            "CFBundleURLTypes": [{"CFBundleURLSchemes": ["unchanged-auth"]}],
            "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
        }
        self.source.write_bytes(plistlib.dumps(self.source_values))
        self.original = self.source.read_bytes()
        self.output = self.root / "Derived with spaces/BaraInfo.plist"
        self.valid = encoded(f"META_APP_ID={APP_ID}", f"META_CLIENT_TOKEN={TOKEN}")

    def invoke(self, defines=None, configuration="Release"):
        result = subprocess.run(["/bin/bash", str(SCRIPT)], capture_output=True, text=True,
          env=dict(os.environ, SRCROOT=str(self.ios), CONFIGURATION=configuration,
                   SCRIPT_INPUT_FILE_0=str(self.source), SCRIPT_OUTPUT_FILE_0=str(self.output),
                   DERIVED_FILE_DIR=str(self.output.parent), DART_DEFINES=self.valid if defines is None else defines))
        self.assertNotIn(TOKEN, result.stdout + result.stderr)
        self.assertNotIn(NEXT_TOKEN, result.stdout + result.stderr)
        self.assertEqual(self.source.read_bytes(), self.original)
        return result

    def assert_generated(self, token=TOKEN):
        actual = plistlib.loads(self.output.read_bytes())
        expected = dict(self.source_values, FacebookAppID=APP_ID if token else "", FacebookClientToken=token)
        self.assertEqual(actual, expected)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o600)

    def test_fresh_generation_preserves_source_and_only_adds_two_values(self):
        result = self.invoke(encoded("OTHER_KEY=must-not-copy", f"META_APP_ID={APP_ID}",
                                     f"META_CLIENT_TOKEN={TOKEN}", "BACKEND_BASE_URL=https://example.invalid"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_generated()
        self.assertNotIn("must-not-copy", self.output.read_text())

    def test_incremental_token_change_replaces_previous_value(self):
        self.assertEqual(self.invoke().returncode, 0)
        self.assertEqual(self.invoke(encoded(f"META_APP_ID={APP_ID}", f"META_CLIENT_TOKEN={NEXT_TOKEN}")).returncode, 0)
        self.assert_generated(NEXT_TOKEN)
        self.assertNotIn(TOKEN, self.output.read_text())

    def test_release_and_profile_reject_missing_or_partial_configuration(self):
        for configuration in ("Release", "Profile"):
            for defines in ("", encoded(f"META_APP_ID={APP_ID}"), encoded(f"META_CLIENT_TOKEN={TOKEN}")):
                with self.subTest(configuration=configuration):
                    self.assertNotEqual(self.invoke(defines, configuration).returncode, 0)

    def test_debug_invalid_or_missing_clears_both_values_after_valid_build(self):
        for defines in ("", encoded(f"META_APP_ID={APP_ID}"), encoded("META_APP_ID=wrong", f"META_CLIENT_TOKEN={TOKEN}")):
            self.assertEqual(self.invoke(configuration="Debug").returncode, 0)
            result = self.invoke(defines, "Debug")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_generated("")

    def test_duplicates_malformed_base64_and_injection_are_rejected(self):
        sentinel = self.root / "must not exist"
        malformed = [self.valid + ",not_base64!", self.valid + ",",
                     self.valid + "," + encoded(f"META_APP_ID={APP_ID}"),
                     self.valid + "," + encoded(f"META_CLIENT_TOKEN={TOKEN}"),
                     encoded("META_APP_ID=12", f"META_CLIENT_TOKEN={TOKEN}"),
                     encoded(f"META_APP_ID={APP_ID}", f"META_CLIENT_TOKEN=$(touch '{sentinel}')"),
                     encoded(f"META_APP_ID={APP_ID}", f"META_CLIENT_TOKEN={TOKEN}\n"),
                     encoded(f"META_APP_ID={APP_ID}", f"META_CLIENT_TOKEN={TOKEN}\x00"),
                     encoded(f"META_APP_ID={APP_ID}", f"META_CLIENT_TOKEN={TOKEN}; echo injected")]
        for defines in malformed:
            with self.subTest(case=malformed.index(defines)):
                self.assertNotEqual(self.invoke(defines).returncode, 0)
                self.assertFalse(sentinel.exists())

    def test_unrelated_define_shell_text_is_not_evaluated_or_copied(self):
        sentinel = self.root / "must not exist"
        result = self.invoke(self.valid + "," + encoded(f"OTHER_KEY=$(touch '{sentinel}')"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(sentinel.exists())
        self.assert_generated()

    def test_all_native_configurations_use_derived_plist_and_phase_dependencies(self):
        project = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text()
        self.assertEqual(project.count('INFOPLIST_FILE = "$(DERIVED_FILE_DIR)/BaraInfo.plist";'), 3)
        self.assertIn('"$(SRCROOT)/Runner/Info.plist",', project)
        self.assertIn('"$(DERIVED_FILE_DIR)/BaraInfo.plist",', project)
        self.assertIn("prepare_meta_ios_plist.sh", project)
        self.assertNotIn("configure_meta_ios.py", project)
        for name in ("Debug", "Release"):
            self.assertNotIn("MetaAppEvents.local.xcconfig", (ROOT / f"ios/Flutter/{name}.xcconfig").read_text())

    def test_actual_xcode_fresh_and_incremental_process_info_plist(self):
        # Minimal native application, actual committed Flutter script phase,
        # real Xcode dependency planning/ProcessInfoPlistFile, no Bara app build.
        project_text = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text()
        start = project_text.index("9740EEB61CF901F6004384FC /* Run Script */ = {")
        end = project_text.index("\n\t\t};", start) + len("\n\t\t};")
        phase = project_text[start:end]
        scripts = self.root / "scripts"
        scripts.mkdir()
        shutil.copyfile(SCRIPT, scripts / SCRIPT.name)
        flutter = self.root / "Flutter fixture"
        backend = flutter / "packages/flutter_tools/bin/xcode_backend.sh"
        backend.parent.mkdir(parents=True)
        backend.write_text("#!/bin/sh\nexit 0\n")
        (self.ios / "main.c").write_text("int main(void) { return 0; }\n")
        project = self.ios / "Runner.xcodeproj"
        project.mkdir()
        settings = ('SDKROOT = iphonesimulator; SUPPORTED_PLATFORMS = iphonesimulator; ARCHS = arm64; '
                    'IPHONEOS_DEPLOYMENT_TARGET = 14.0; CODE_SIGNING_ALLOWED = NO; '
                    'ENABLE_USER_SCRIPT_SANDBOXING = NO; PRODUCT_NAME = Runner; '
                    'PRODUCT_BUNDLE_IDENTIFIER = com.bara.fixture; '
                    'INFOPLIST_FILE = "$(DERIVED_FILE_DIR)/BaraInfo.plist";')
        pbx = '''// !$*UTF8*$!
{ archiveVersion = 1; objectVersion = 54; objects = {
 P = {isa = PBXProject; buildConfigurationList = PC; compatibilityVersion = "Xcode 14.0"; mainGroup = G; productRefGroup = PG; projectDirPath = ""; projectRoot = ""; targets = (T,); };
 G = {isa = PBXGroup; children = (F,PG,); sourceTree = "<group>";};
 PG = {isa = PBXGroup; children = (APP,); name = Products; sourceTree = "<group>";};
 F = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.c; path = main.c; sourceTree = "<group>";};
 APP = {isa = PBXFileReference; explicitFileType = wrapper.application; path = Runner.app; sourceTree = BUILT_PRODUCTS_DIR;};
 B = {isa = PBXBuildFile; fileRef = F;};
 S = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (B,); runOnlyForDeploymentPostprocessing = 0;};
 T = {isa = PBXNativeTarget; buildConfigurationList = TC; buildPhases = (9740EEB61CF901F6004384FC,S,); buildRules = (); dependencies = (); name = Runner; productName = Runner; productReference = APP; productType = "com.apple.product-type.application";};
 PC = {isa = XCConfigurationList; buildConfigurations = (PD,PR,PP,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
 TC = {isa = XCConfigurationList; buildConfigurations = (TD,TR,TP,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
 PD = {isa = XCBuildConfiguration; buildSettings = {}; name = Debug;};
 PR = {isa = XCBuildConfiguration; buildSettings = {}; name = Release;};
 PP = {isa = XCBuildConfiguration; buildSettings = {}; name = Profile;};
'''
        for key, name in (("TD", "Debug"), ("TR", "Release"), ("TP", "Profile")):
            pbx += f'{key} = {{isa = XCBuildConfiguration; buildSettings = {{{settings}}}; name = {name};}};\n'
        pbx += phase + "\n}; rootObject = P; }\n"
        (project / "project.pbxproj").write_text(pbx)
        build = self.root / "Built products"

        def build_metadata(configuration, defines):
            result = subprocess.run(["xcodebuild", "-project", str(project), "-target", "Runner",
                "-configuration", configuration, "-sdk", "iphonesimulator", "build",
                f"SYMROOT={build}", f"FLUTTER_ROOT={flutter}", f"DART_DEFINES={defines}"],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, (result.stdout + result.stderr)[-5000:])
            self.assertEqual(self.source.read_bytes(), self.original)
            output = build / f"{configuration}-iphonesimulator/Runner.app/Info.plist"
            return plistlib.loads(output.read_bytes())

        first = build_metadata("Release", self.valid)
        self.assertEqual(first["FacebookClientToken"], TOKEN)
        self.assertEqual(first["FacebookAppID"], APP_ID)
        self.assertEqual(first["CFBundleIdentifier"], "com.bara.fixture")
        self.assertEqual(first["FacebookDisplayName"], "Bara")
        self.assertIs(first["FacebookAutoLogAppEventsEnabled"], False)
        self.assertIs(first["FacebookAdvertiserIDCollectionEnabled"], False)
        next_values = encoded(f"META_APP_ID={APP_ID}", f"META_CLIENT_TOKEN={NEXT_TOKEN}")
        self.assertEqual(build_metadata("Release", next_values)["FacebookClientToken"], NEXT_TOKEN)
        self.assertEqual(build_metadata("Profile", self.valid)["FacebookClientToken"], TOKEN)
        self.assertEqual(build_metadata("Debug", "")["FacebookClientToken"], "")


if __name__ == "__main__":
    unittest.main()
