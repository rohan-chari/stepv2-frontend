import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CoreKit starts with automatic events and advertiser ID disabled', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    for (final key in [
      'FacebookAutoLogAppEventsEnabled',
      'FacebookAdvertiserIDCollectionEnabled',
    ]) {
      expect(
        RegExp('<key>$key</key>\\s*<false\\s*/>').hasMatch(plist),
        isTrue,
        reason: '$key must be false before any SDK initialization',
      );
    }
  });

  test('uses only pinned CoreKit alongside the existing mediation adapter', () {
    final podfile = File('ios/Podfile').readAsStringSync();
    final lock = File('ios/Podfile.lock').readAsStringSync();
    expect(podfile, contains("pod 'FBSDKCoreKit', '18.1.1'"));
    expect(lock, contains('FBSDKCoreKit (18.1.1)'));
    expect(
      podfile,
      contains("pod 'GoogleMobileAdsMediationFacebook', '6.21.1.1'"),
    );
    expect(podfile, isNot(contains("pod 'FBAudienceNetwork'")));
    expect(lock, isNot(contains('FBSDKLoginKit')));
    expect(lock, isNot(contains('FBSDKShareKit')));
  });
}
