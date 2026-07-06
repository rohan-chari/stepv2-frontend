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
      if (!_sdkInitialized) {
        // ATT first (iOS): with tracking denied the SDK serves
        // non-personalized ads, which is fine — the reward flow is identical.
        if (Platform.isIOS) {
          try {
            final status = await AppTrackingTransparency.trackingAuthorizationStatus;
            if (status == TrackingStatus.notDetermined) {
              await AppTrackingTransparency.requestTrackingAuthorization();
            }
          } catch (_) {
            // ATT unavailable (simulator/old iOS) — proceed without it.
          }
        }
        await MobileAds.instance.initialize();
        _sdkInitialized = true;
      }

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
