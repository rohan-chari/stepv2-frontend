import unittest
from verify_android_bundle import validate_manifest, validate_signature_output

BASE = """<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.rohanchari.steptracker" android:versionName="2.3.13" android:versionCode="203132"><uses-permission android:name="com.android.vending.BILLING"/><application><meta-data android:name="com.google.android.play.billingclient.version" android:value="8.3.0"/></application></manifest>"""

class BundleManifestTest(unittest.TestCase):
    def check(self, xml):
        return validate_manifest(xml, "com.rohanchari.steptracker", "2.3.13", "203132")
    def test_complete(self):
        self.assertEqual(self.check(BASE)["billing_client"], "8.3.0")
    def test_reject_missing_permission(self):
        with self.assertRaises(ValueError): self.check(BASE.replace("com.android.vending.BILLING", "missing"))
    def test_reject_wrong_package_or_version(self):
        for old, new in [("com.rohanchari.steptracker", "com.rohanchari.steptracker.staging"), ("203132", "203131"), ("2.3.13", "2.3.12")]:
            with self.subTest(old=old), self.assertRaises(ValueError): self.check(BASE.replace(old, new))
    def test_reject_missing_sdk(self):
        with self.assertRaises(ValueError): self.check(BASE.replace("com.google.android.play.billingclient.version", "missing"))

class SignatureTest(unittest.TestCase):
    def test_valid_self_signed_upload_certificate(self):
        validate_signature_output("jar verified.\nWarning: This jar contains entries whose certificate chain is invalid.")
    def test_unsigned_entries_rejected(self):
        with self.assertRaises(ValueError):
            validate_signature_output("jar verified.\nThis jar contains unsigned entries which have not been integrity-checked.")
    def test_unverified_rejected(self):
        with self.assertRaises(ValueError): validate_signature_output("jar is unsigned.")

if __name__ == "__main__": unittest.main()
