import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deployment handoff pins placement-specific platform defines', () {
    final deployment = File('DEPLOYMENT.md').readAsStringSync();
    for (final define in <String>[
      'ADMOB_RACE_DETAIL_EXIT_INTERSTITIAL_AD_UNIT_ID=',
      'ADMOB_RACE_RESULTS_EXIT_INTERSTITIAL_AD_UNIT_ID=',
      'ADMOB_RACE_DETAIL_EXIT_INTERSTITIAL_AD_UNIT_ID_ANDROID=',
      'ADMOB_RACE_RESULTS_EXIT_INTERSTITIAL_AD_UNIT_ID_ANDROID=',
    ]) {
      expect(deployment, contains(define));
    }
    expect(deployment, isNot(contains('ADMOB_INTERSTITIAL_AD_UNIT_ID=')));
    expect(
      deployment,
      isNot(contains('ADMOB_INTERSTITIAL_AD_UNIT_ID_ANDROID=')),
    );
    expect(
      deployment,
      contains(
        'ADMOB_RACE_DETAIL_EXIT_INTERSTITIAL_AD_UNIT_ID=ca-app-pub-4538901002392200/9584444570',
      ),
    );
    expect(
      deployment,
      contains(
        'ADMOB_RACE_RESULTS_EXIT_INTERSTITIAL_AD_UNIT_ID=ca-app-pub-4538901002392200/6032212376',
      ),
    );
    expect(deployment, contains('2 impressions/user/day'));
    expect(deployment, isNot(contains('seven complete production')));
    expect(deployment, isNot(contains('no-ID telemetry baseline')));
  });

  test('all production Race Detail pushes use the shared navigator', () {
    const productionFiles = <String>[
      'lib/screens/main_shell.dart',
      'lib/screens/tabs/races_tab.dart',
      'lib/screens/public_races_screen.dart',
      'lib/screens/tournament_detail_screen.dart',
    ];
    for (final path in productionFiles) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('=> RaceDetailScreen(')),
        reason: '$path must use RaceDetailNavigator',
      );
      expect(
        source,
        isNot(contains('builder: (_) => RaceDetailScreen(')),
        reason: '$path must use RaceDetailNavigator',
      );
    }
    expect(
      File('lib/tutorial/tutorial_real_screens.dart').readAsStringSync(),
      contains('RaceDetailScreen('),
    );
    expect(
      File('lib/demo/demo_race_host.dart').readAsStringSync(),
      contains('RaceDetailScreen('),
    );
  });

  test('only approved post-pop owners can present interstitials', () {
    final callers = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains('.presentIfReady(')) {
        callers.add(entity.path);
      }
    }
    expect(callers..sort(), <String>[
      'lib/screens/main_shell.dart',
      'lib/services/race_detail_navigation.dart',
    ]);

    for (final path in <String>[
      'lib/screens/case_opening_screen.dart',
      'lib/screens/multi_case_opening_screen.dart',
      'lib/screens/admin_powerup_shop_screen.dart',
    ]) {
      expect(
        File(path).readAsStringSync().toLowerCase(),
        isNot(contains('interstitial')),
        reason: '$path must never directly trigger the exit placement',
      );
    }
  });

  test('typed root exits and fail-closed route guards remain explicit', () {
    final race = File('lib/screens/race_detail_screen.dart').readAsStringSync();
    expect(
      RegExp(r'pop\(RaceDetailRouteResult\.stateChange\)').allMatches(race),
      hasLength(greaterThanOrEqualTo(5)),
    );
    expect(race, contains('maybePop(RaceDetailRouteResult.forwardExit)'));
    expect(
      RegExp(r'recordRewardedPresented\(\)').allMatches(race),
      hasLength(greaterThanOrEqualTo(2)),
    );

    final navigation = File(
      'lib/services/race_detail_navigation.dart',
    ).readAsStringSync();
    expect(navigation, contains('ModalRoute.of(context)?.isCurrent == true'));
    expect(navigation, isNot(contains('isCurrent ?? true')));

    final shell = File('lib/screens/main_shell.dart').readAsStringSync();
    expect(shell, contains('ModalRoute.of(context)?.isCurrent == true'));
    expect(shell, contains('AppLifecycleState.resumed'));
  });
}
