import '../services/auth_service.dart';

/// A read-through, write-nowhere wrapper around the user's real [AuthService]
/// (spec §5.5b, gap-pass finding G1).
///
/// The demo must render as **the user's own race** — real display name, real
/// user id, real coin balance — because `_myUserId` on the race screen resolves
/// to `authService.userId`, and the engine's participant list has to contain it
/// or `TeamRace.offensiveTargets` cannot exclude the user from their own target
/// picker and beat 7 breaks.
///
/// But the real screen also *writes* through the auth service:
///
/// * `_usePowerup` → `authService.updateCoins(coins - coinsSpent)`
///   (`race_detail_screen.dart:1508-1511`)
/// * `_refreshWallet` → `fetchMe` then `updateCoins`
///   (`race_detail_screen.dart:800-805`)
///
/// Passing the real service would let demo actions decrement the user's
/// displayed balance. So every read proxies and **every write is a no-op.**
/// (Belt and braces: `DemoRaceEngine` also reports `coinsSpent: 0`, so even a
/// leaked write moves nothing.)
class DemoAuthService extends AuthService {
  DemoAuthService(this.real) {
    // Mirror the real service so a coin badge repaints when the underlying
    // balance changes for reasons outside the demo.
    real.addListener(notifyListeners);
  }

  final AuthService real;

  @override
  void dispose() {
    real.removeListener(notifyListeners);
    super.dispose();
  }

  // -- Reads: proxied ---------------------------------------------------------

  @override
  String? get authToken => real.authToken;

  @override
  String? get identityToken => real.identityToken;

  @override
  String? get sessionToken => real.sessionToken;

  @override
  String? get userId => real.userId;

  @override
  String? get displayName => real.displayName;

  @override
  String? get profilePhotoUrl => real.profilePhotoUrl;

  @override
  int get coins => real.coins;

  @override
  int get heldCoins => real.heldCoins;

  @override
  bool get isAdmin => false;

  @override
  bool get isSignedIn => real.isSignedIn;

  @override
  bool get hasSessionToken => real.hasSessionToken;

  @override
  bool get teamRacesEnabled => real.teamRacesEnabled;

  /// Deliberately false. `onboardingV2Enabled` is the flag that makes the race
  /// screen fetch the starter reward and render `RaceAlertOptInCard` — the
  /// sharpest edge in this spec (G3). `demoMode` suppresses both independently;
  /// this is the second lock on the same door.
  @override
  bool get onboardingV2Enabled => false;

  @override
  bool get onboardingV3Enabled => false;

  /// The invite-code step is v3-only, so this is a second lock on the same
  /// door — and it matters more than it looks: the flag FAILS OPEN on the real
  /// service (a kill switch must), so inheriting it would leave the demo host
  /// one `onboardingV3Enabled` change away from rendering an onboarding step
  /// and firing a `/referrals/me` fetch inside a network-guarded demo.
  @override
  bool get onboardingInviteCodeEnabled => false;

  /// The demo never provisions an account, so there is no attribution to read.
  @override
  String? get referredByCode => null;

  /// No ads inside the demo (§5.6). The banner slots are hidden by `demoMode`
  /// too; this keeps the flag itself from arming an ad request.
  @override
  bool get bannerAdsEnabled => false;

  @override
  bool get dualBoxBannersEnabled => false;

  // -- Writes: no-ops ---------------------------------------------------------

  @override
  Future<void> updateCoins(int coins) async {}

  @override
  Future<void> updateHeldCoins(int heldCoins) async {}

  @override
  Future<void> updateAdminAccess(bool isAdmin) async {}

  @override
  void applyBackendUser(Map<String, dynamic> backendUser) {}

  @override
  Future<void> markTutorialOnboardingSeen() async {}

  @override
  Future<bool> claimTutorialReward() async => false;

  @override
  Future<void> markFirstRaceOnboardingSeenLocally() async {}
}
