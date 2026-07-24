import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  static const _metaAdsChannel = MethodChannel('com.steptracker/meta_ads');

  // Ad unit IDs are per-platform in AdMob. iOS uses the original defines;
  // Android uses the parallel `_ANDROID` defines (added so Android can reach
  // full parity without changing the iOS ids). An absent/empty id for a surface
  // disables that surface on this platform (see the *Enabled getters below).
  static const _envAdUnitId = String.fromEnvironment(
    'ADMOB_EXTRA_SPIN_AD_UNIT_ID',
  );
  static const _envAdUnitIdAndroid = String.fromEnvironment(
    'ADMOB_EXTRA_SPIN_AD_UNIT_ID_ANDROID',
  );
  // Google's documented test rewarded ad units.
  static const _testAdUnitAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testAdUnitIos = 'ca-app-pub-3940256099942544/1712485313';

  // Rewarded unit for the shop "watch ads to unlock a powerup" flow. A
  // dedicated unit is preferred so its SSV callback can be scoped to this flow,
  // but when the define is absent we fall back to the extra-spin rewarded unit
  // (and, absent that, Google's test unit) so the feature is never blocked on
  // Rohan creating the unit. iOS uses the base define; Android the `_ANDROID`.
  static const _envPowerupUnlockAdUnitId = String.fromEnvironment(
    'ADMOB_POWERUP_UNLOCK_AD_UNIT_ID',
  );
  static const _envPowerupUnlockAdUnitIdAndroid = String.fromEnvironment(
    'ADMOB_POWERUP_UNLOCK_AD_UNIT_ID_ANDROID',
  );

  // Banner placements (shop, race mystery-box overlay) are display-only: no
  // SSV, no reward, no backend. Like the rewarded unit, the real banner unit is
  // baked in per-build via --dart-define; absent, we fall back to Google's
  // public test banner so dev/staging shows a placeholder ad, never a real one.
  static const _envBannerAdUnitId = String.fromEnvironment(
    'ADMOB_BANNER_AD_UNIT_ID',
  );
  static const _envBannerAdUnitIdAndroid = String.fromEnvironment(
    'ADMOB_BANNER_AD_UNIT_ID_ANDROID',
  );
  static const _envBoxTopBannerAdUnitId = String.fromEnvironment(
    'ADMOB_BOX_TOP_BANNER_AD_UNIT_ID',
  );
  static const _envBoxTopBannerAdUnitIdAndroid = String.fromEnvironment(
    'ADMOB_BOX_TOP_BANNER_AD_UNIT_ID_ANDROID',
  );
  static const _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';

  // Native in-feed placement (races tab list row). Same deal as the banner
  // unit: real id baked in per-build via --dart-define, Google's public
  // "native advanced" test unit otherwise. Gated by the SAME bannersEnabled
  // switch — natives are just a better-dressed banner, not a new ad surface.
  static const _envNativeAdUnitId = String.fromEnvironment(
    'ADMOB_NATIVE_AD_UNIT_ID',
  );
  static const _envNativeAdUnitIdAndroid = String.fromEnvironment(
    'ADMOB_NATIVE_AD_UNIT_ID_ANDROID',
  );
  static const _testNativeIos = 'ca-app-pub-3940256099942544/3986624511';
  static const _testNativeAndroid = 'ca-app-pub-3940256099942544/2247696110';

  /// The real (injected) rewarded/banner/native unit id for the CURRENT
  /// platform, or '' when this platform has no id baked in (which disables the
  /// surface). Web has no ads SDK, so always ''.
  static String get _platformExtraSpinUnitId {
    if (kIsWeb) return '';
    if (Platform.isIOS) return _envAdUnitId;
    if (Platform.isAndroid) return _envAdUnitIdAndroid;
    return '';
  }

  /// Resolved rewarded unit for the powerup-unlock flow: the dedicated define
  /// for this platform when baked in, else the extra-spin real unit, else ''
  /// (which makes [AdService] fall back to Google's public test unit). Pass to
  /// `AdService(adUnitId: AdService.powerupUnlockAdUnitId)`.
  static String get powerupUnlockAdUnitId {
    if (kIsWeb) return '';
    final id = Platform.isIOS
        ? _envPowerupUnlockAdUnitId
        : Platform.isAndroid
        ? _envPowerupUnlockAdUnitIdAndroid
        : '';
    return id.isNotEmpty ? id : _platformExtraSpinUnitId;
  }

  static String get _platformBannerUnitId {
    if (kIsWeb) return '';
    if (Platform.isIOS) return _envBannerAdUnitId;
    if (Platform.isAndroid) return _envBannerAdUnitIdAndroid;
    return '';
  }

  static String get _platformBoxTopBannerUnitId {
    if (kIsWeb) return '';
    if (Platform.isIOS) return _envBoxTopBannerAdUnitId;
    if (Platform.isAndroid) return _envBoxTopBannerAdUnitIdAndroid;
    return '';
  }

  static String get _platformNativeUnitId {
    if (kIsWeb) return '';
    if (Platform.isIOS) return _envNativeAdUnitId;
    if (Platform.isAndroid) return _envNativeAdUnitIdAndroid;
    return '';
  }

  /// Remote kill switch, set from the backend's `featureFlags.bannerAdsEnabled`
  /// (AuthService mirrors it here on restore and on every /auth/me sync, and it
  /// is toggleable from Admin → Settings without an app release). Defaults OFF:
  /// no flag from the backend means no banners.
  static bool remoteBannersEnabled = false;

  /// Additive box-only rollout switch. Missing/null server values stay off.
  static bool remoteDualBoxBannersEnabled = false;

  /// Banners render ONLY when the backend flag is on AND this build baked in a
  /// real banner unit id for the current platform — the unit id is compile-time
  /// (keep passing the dart-define in prod builds so the remote switch can turn
  /// banners back on later). iOS uses ADMOB_BANNER_AD_UNIT_ID; Android uses
  /// ADMOB_BANNER_AD_UNIT_ID_ANDROID. Builds that omit their platform's define
  /// (and web) show nothing at all. When off, [AdBannerSlot] collapses to zero
  /// size.
  static bool get bannersEnabled =>
      remoteBannersEnabled && !kIsWeb && _platformBannerUnitId.isNotEmpty;

  static bool get boxTopBannerEnabled =>
      remoteBannersEnabled &&
      remoteDualBoxBannersEnabled &&
      !kIsWeb &&
      _platformBoxTopBannerUnitId.isNotEmpty;

  /// Ad unit for [AdBannerSlot]. The real unit when injected at build time,
  /// otherwise Google's public test banner for this platform (only reached in
  /// dev, since [bannersEnabled] is false without the define).
  static String get bannerAdUnitId {
    final id = _platformBannerUnitId;
    if (id.isNotEmpty) return id;
    return (!kIsWeb && Platform.isAndroid)
        ? _testBannerAndroid
        : _testBannerIos;
  }

  static String get boxTopBannerAdUnitId {
    final id = _platformBoxTopBannerUnitId;
    if (id.isNotEmpty) return id;
    return (!kIsWeb && Platform.isAndroid)
        ? _testBannerAndroid
        : _testBannerIos;
  }

  /// Ad unit for [AdInlineCard]'s native in-feed ad. The real unit when
  /// injected at build time, otherwise Google's public test native unit for
  /// this platform (only reached in dev, since [bannersEnabled] is false
  /// without the banner define).
  static String get nativeAdUnitId {
    final id = _platformNativeUnitId;
    if (id.isNotEmpty) return id;
    return (!kIsWeb && Platform.isAndroid)
        ? _testNativeAndroid
        : _testNativeIos;
  }

  /// Initialize the ads SDK once (with an iOS ATT prompt on first run). Shared
  /// by the rewarded-ad path and [AdBannerSlot] so neither owns SDK setup.
  /// Safe to call repeatedly.
  static Future<void> ensureInitialized() async {
    if (_sdkInitialized) return;
    // ATT first (iOS): with tracking denied the SDK serves non-personalized
    // ads, which is fine — the reward/banner flows are identical.
    if (!kIsWeb && Platform.isIOS) {
      try {
        var status = await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          status = await AppTrackingTransparency.requestTrackingAuthorization();
        }
        // Meta Audience Network requires this explicit flag before AdMob
        // initializes. Never infer consent: only ATT "authorized" maps to true.
        await _metaAdsChannel.invokeMethod<void>(
          'setAdvertiserTrackingEnabled',
          status == TrackingStatus.authorized,
        );
      } catch (_) {
        // ATT or the optional Meta bridge is unavailable — proceed without
        // personalized tracking rather than blocking every ad source.
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
    final id = _platformExtraSpinUnitId;
    if (id.isNotEmpty) return id;
    return (!kIsWeb && Platform.isAndroid)
        ? _testAdUnitAndroid
        : _testAdUnitIos;
  }

  @override
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

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
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    return completer.future;
  }

  @override
  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
