#!/usr/bin/env python3
"""Verify the actual signed Play upload, not the source AndroidManifest.xml."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ANDROID = '{http://schemas.android.com/apk/res/android}'


def validate_manifest(xml, package, version, code):
    root = ET.fromstring(xml)
    for label, actual, expected in [
        ('package', root.get('package'), package),
        ('versionName', root.get(ANDROID + 'versionName'), version),
        ('versionCode', root.get(ANDROID + 'versionCode'), str(code)),
    ]:
        if actual != expected:
            raise ValueError(f'{label}: expected {expected}, found {actual}')
    permissions = {item.get(ANDROID + 'name') for item in root.findall('uses-permission')}
    if 'com.android.vending.BILLING' not in permissions:
        raise ValueError('Compiled bundle is missing com.android.vending.BILLING')
    metadata = {item.get(ANDROID + 'name'): item.get(ANDROID + 'value')
                for item in root.findall('application/meta-data')}
    billing = metadata.get('com.google.android.play.billingclient.version')
    if not billing:
        raise ValueError('Compiled bundle has no Play Billing client metadata')
    return dict(package=package, version=version, version_code=str(code), billing_client=billing)


def validate_signature_output(output):
    # jarsigner exits successfully for partly signed JARs too. A self-signed
    # upload certificate is normal; unsigned bundle entries are never allowed.
    if 'jar verified.' not in output or 'unsigned entries' in output.lower():
        raise ValueError('AAB is unverified or contains unsigned entries')


def run(args):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--bundletool', required=True, type=Path)
    parser.add_argument('--java-home', required=True, type=Path)
    parser.add_argument('--package', default='com.rohanchari.steptracker')
    parser.add_argument('--version', required=True)
    parser.add_argument('--code', required=True)
    parser.add_argument('--expected-sha256-cert', required=True,
                        help='Upload certificate fingerprint from the trusted signing key')
    args = parser.parse_args()
    bin_dir = args.java_home / 'bin'
    manifest = run([str(bin_dir / 'java'), '-jar', str(args.bundletool), 'dump',
                    'manifest', f'--bundle={args.bundle}', '--module=base'])
    report = validate_manifest(manifest, args.package, args.version, args.code)
    verification = run([str(bin_dir / 'jarsigner'), '-J-Duser.language=en', '-verify', str(args.bundle)])
    validate_signature_output(verification)
    certificate = run([str(bin_dir / 'keytool'), '-J-Duser.language=en', '-printcert', '-jarfile', str(args.bundle)])
    fingerprints = re.findall(r'SHA256:\s*([0-9A-Fa-f:]+)', certificate)
    normalize = lambda value: value.replace(':', '').upper()
    if not fingerprints or any(normalize(value) != normalize(args.expected_sha256_cert) for value in fingerprints):
        raise ValueError('AAB upload certificate does not match the trusted signing key')
    report.update(bundle=str(args.bundle.resolve()), sha256=hashlib.sha256(args.bundle.read_bytes()).hexdigest(),
                  upload_certificate_sha256=fingerprints[0], signature_verified=True)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
