import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Contract the daily-reward screen talks to for the rewarded-ad extra spin,
/// so widget tests inject a fake and no screen ever imports google_mobile_ads
/// directly (keeps a future mediation swap — e.g. AppLovin MAX — inside this
/// file). See AD_REWARD_DESIGN.md.
abstract class ExtraSpinAdController {
  /// False on platforms without the ads SDK (macOS, web, tests).
  bool get isSupported;

  /// True when a rewarded ad is loaded and can be shown right now.
  bool get isReady;

  /// Preload the rewarded ad. [userId]/[localDate] ride along as AdMob
  /// server-side-verification userId/customData, so the SSV callback can mint
  /// the grant for the right user and day. Safe to call repeatedly.
  Future<void> load({required String userId, required String localDate});

  /// Show the loaded ad. Resolves true only if the user earned the reward
  /// (watched through), false if they closed early or the show failed.
  Future<bool> showAndAwaitReward();

  void dispose();
}

/// AdMob rewarded ad for the extra daily box spin.
///
/// The earned-reward callback here is UX-only (it lets the screen proceed to
/// the claim); the actual entitlement is minted server-side by AdMob's SSV
/// callback hitting /ads/ssv. The default ad-unit IDs are Google's public
/// TEST units — real per-flavor IDs are injected with --dart-define like
/// BACKEND_BASE_URL (see DEPLOYMENT.md).
class AdService implements ExtraSpinAdController {
  AdService({String? adUnitId}) : _adUnitIdOverride = adUnitId;

  static const _envAdUnitId = String.fromEnvironment('ADMOB_EXTRA_SPIN_AD_UNIT_ID');
  // Google's documented test rewarded ad units.
  static const _testAdUnitAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testAdUnitIos = 'ca-app-pub-3940256099942544/1712485313';

  // Banner placements (shop, race mystery-box overlay) are display-only: no
  // SSV, no reward, no backend. Like the rewarded unit, the real banner unit is
  // baked in per-build via --dart-define; absent, we fall back to Google's
  // public test banner so dev/staging shows a placeholder ad, never a real one.
  static const _envBannerAdUnitId =
      String.fromEnvironment('ADMOB_BANNER_AD_UNIT_ID');
  static const _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';

  /// Remote kill switch, set from the backend's `featureFlags.bannerAdsEnabled`
  /// (AuthService mirrors it here on restore and on every /auth/me sync, and it
  /// is toggleable from Admin → Settings without an app release). Defaults OFF:
  /// no flag from the backend means no banners.
  static bool remoteBannersEnabled = false;

  /// Banners render ONLY when the backend flag is on AND this is an iOS build
  /// that baked in a real ADMOB_BANNER_AD_UNIT_ID — the unit id is compile-time
  /// (keep passing the dart-define in prod builds so the remote switch can turn
  /// banners back on later). Android (no AdMob app registered) and
  /// misconfigured builds show nothing at all. When off, [AdBannerSlot]
  /// collapses to zero size.
  static bool get bannersEnabled =>
      remoteBannersEnabled &&
      !kIsWeb &&
      Platform.isIOS &&
      _envBannerAdUnitId.isNotEmpty;

  /// Ad unit for [AdBannerSlot]. The real unit when injected at build time,
  /// otherwise Google's public test banner (only reached in dev, since
  /// [bannersEnabled] is false without the define).
  static String get bannerAdUnitId =>
      _envBannerAdUnitId.isNotEmpty ? _envBannerAdUnitId : _testBannerIos;

  /// Initialize the ads SDK once (with an iOS ATT prompt on first run). Shared
  /// by the rewarded-ad path and [AdBannerSlot] so neither owns SDK setup.
  /// Safe to call repeatedly.
  static Future<void> ensureInitialized() async {
    if (_sdkInitialized) return;
    // ATT first (iOS): with tracking denied the SDK serves non-personalized
    // ads, which is fine — the reward/banner flows are identical.
    if (!kIsWeb && Platform.isIOS) {
      try {
        final status =
            await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          await AppTrackingTransparency.requestTrackingAuthorization();
        }
      } catch (_) {
        // ATT unavailable (simulator/old iOS) — proceed without it.
      }
    }
    // Debug builds only: mark our own devices as AdMob test devices so we can
    // watch the REAL ad units without generating invalid traffic (impressions/
    // clicks Google would otherwise penalize). The value is the hashed
    // identifier the SDK prints to the console ("testDeviceIdentifiers = …"),
    // NOT the raw IDFA. Stripped from release builds by kDebugMode, so real
    // users are never flagged as test — for release/TestFlight testing,
    // register the device's IDFA in the AdMob console instead.
    if (kDebugMode) {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: ['9e7526f59bde4aeb8cdc4910cf702487'], // Rohan iPhone
        ),
      );
    }
    await MobileAds.instance.initialize();
    _sdkInitialized = true;
  }

  final String? _adUnitIdOverride;
  RewardedAd? _ad;
  bool _loading = false;
  static bool _sdkInitialized = false;

  String get _adUnitId {
    if (_adUnitIdOverride != null && _adUnitIdOverride.isNotEmpty) {
      return _adUnitIdOverride;
    }
    if (_envAdUnitId.isNotEmpty) return _envAdUnitId;
    return Platform.isAndroid ? _testAdUnitAndroid : _testAdUnitIos;
  }

  @override
  bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  bool get isReady => _ad != null;

  @override
  Future<void> load({required String userId, required String localDate}) async {
    if (!isSupported || _loading || _ad != null) return;
    _loading = true;
    try {
      await ensureInitialized();

      final completer = Completer<void>();
      await RewardedAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) async {
            // SSV identity: the callback Google sends us echoes these back as
            // user_id / custom_data.
            await ad.setServerSideOptions(
              ServerSideVerificationOptions(
                userId: userId,
                customData: localDate,
              ),
            );
            _ad = ad;
            completer.complete();
          },
          onAdFailedToLoad: (error) {
            debugPrint('Rewarded ad failed to load: $error');
            completer.complete();
          },
        ),
      );
      await completer.future;
    } finally {
      _loading = false;
    }
  }

  @override
  Future<bool> showAndAwaitReward() async {
    final ad = _ad;
    if (ad == null) return false;
    _ad = null;

    final completer = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Rewarded ad failed to show: $error');
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await ad.show(
      onUserEarnedReward: (_, _) => earned = true,
    );
    return completer.future;
  }

  @override
  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
