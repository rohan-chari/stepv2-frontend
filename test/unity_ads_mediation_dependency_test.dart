import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('declares the official Unity Ads adapter without changing AdMob', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('google_mobile_ads: ^9.0.0'));
    expect(pubspec, contains('gma_mediation_unity: ^1.9.0'));

    final lockfile = File('pubspec.lock').readAsStringSync();
    expect(lockfile, contains('version: "1.9.0"'));
  });

  test('preserves existing mediation dependencies and Unity SKAdNetwork ID', () {
    final podfile = File('ios/Podfile').readAsStringSync();
    final androidBuild = File('android/app/build.gradle.kts').readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final podLockfile = File('ios/Podfile.lock').readAsStringSync();

    expect(podfile, contains("pod 'GoogleMobileAdsMediationFacebook', '6.21.1.1'"));
    expect(
      podfile,
      contains("pod 'GoogleMobileAdsMediationAppLovin', '13.6.3.0'"),
    );
    expect(
      podfile,
      contains("pod 'GoogleMobileAdsMediationIronSource', '9.4.1.0.1'"),
    );
    expect(
      androidBuild,
      contains('com.google.ads.mediation:ironsource:9.4.2.0'),
    );
    expect(infoPlist, contains('4dzt52r2t5.skadnetwork'));
    expect(podLockfile, contains('GoogleMobileAdsMediationUnity (4.19.0.1)'));
    expect(podLockfile, contains('UnityAds (4.19.0)'));
  });
}
