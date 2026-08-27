import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'declares official Unity and Liftoff adapters without changing AdMob',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(pubspec, contains('google_mobile_ads: ^9.0.0'));
      expect(pubspec, contains('gma_mediation_unity: ^1.9.0'));
      expect(pubspec, contains('gma_mediation_liftoffmonetize: 1.5.2'));

      final lockfile = File('pubspec.lock').readAsStringSync();
      expect(lockfile, contains('version: "1.9.0"'));
      expect(lockfile, contains('gma_mediation_liftoffmonetize:'));
      expect(lockfile, contains('version: "1.5.2"'));
    },
  );

  test('preserves mediation dependencies and required SKAdNetwork IDs', () {
    final podfile = File('ios/Podfile').readAsStringSync();
    final androidBuild = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final podLockfile = File('ios/Podfile.lock').readAsStringSync();

    expect(
      podfile,
      contains("pod 'GoogleMobileAdsMediationFacebook', '6.21.1.1'"),
    );
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
    expect(infoPlist, contains('gta9lk7p23.skadnetwork'));
    expect(infoPlist, contains('7953jerfzd.skadnetwork'));
    expect(podLockfile, contains('GoogleMobileAdsMediationUnity (4.19.0.1)'));
    expect(podLockfile, contains('UnityAds (4.19.0)'));
    expect(podLockfile, contains('GoogleMobileAdsMediationVungle (7.7.6.0)'));
    expect(podLockfile, contains('VungleAds (7.7.6)'));
  });

  test('release shrinker accepts optional OkHttp TLS providers', () {
    final androidBuild = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final proguardRules = File(
      'android/app/proguard-rules.pro',
    ).readAsStringSync();

    expect(
      androidBuild,
      contains('getDefaultProguardFile("proguard-android-optimize.txt")'),
    );
    expect(androidBuild, contains('proguard-rules.pro'));
    for (final optionalProvider in [
      'org.bouncycastle.jsse.**',
      'org.conscrypt.**',
      'org.openjsse.**',
    ]) {
      expect(proguardRules, contains('-dontwarn $optionalProvider'));
    }
  });
}
