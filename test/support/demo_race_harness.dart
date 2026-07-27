import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/auth_service.dart';

/// Shared scaffolding for the demo-race widget tests.
///
/// The demo renders the REAL `RaceDetailScreen`, which self-loads
/// asynchronously and runs infinite animations (spinning coins, pulses, course
/// drift), so we never `pumpAndSettle` — we pump fixed durations.

/// A real [AuthService] seeded the way a signed-in user's is. The demo wraps
/// this in `DemoAuthService`, which proxies its reads and no-ops its writes.
class SeededAuthService extends AuthService {
  SeededAuthService({
    String userId = 'usr_real_1',
    String displayName = 'Wandering Otter42',
    int coins = 1840,
  }) {
    applyBackendUser({
      'id': userId,
      'displayName': displayName,
      'profilePhotoUrl': null,
      'coins': coins,
    });
  }

  @override
  String? get authToken => 'seeded-token';

  /// A brand-new user's state: the onboarding revamp is on, which is exactly
  /// the configuration that makes the race screen fetch the starter reward and
  /// render `RaceAlertOptInCard`.
  @override
  bool get onboardingV2Enabled => true;

  @override
  bool get onboardingV3Enabled => true;

  int coinUpdates = 0;

  /// The real method reaches the network; stubbed so the win-card path does
  /// not hang on an HTTP call inside the test zone. Counted so "granted once,
  /// ever" stays assertable.
  int tutorialRewardClaims = 0;

  @override
  Future<bool> claimTutorialReward() async {
    tutorialRewardClaims += 1;
    return true;
  }

  @override
  Future<void> updateCoins(int coins) async {
    coinUpdates += 1;
    await super.updateCoins(coins);
  }
}

SeededAuthService seededRealAuthService({
  String userId = 'usr_real_1',
  String displayName = 'Wandering Otter42',
  int coins = 1840,
}) => SeededAuthService(
  userId: userId,
  displayName: displayName,
  coins: coins,
);

/// Pumps enough frames for the seeded futures to resolve and the coach mark to
/// settle, without ever waiting for an animation that never ends.
Future<void> settleDemo(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
