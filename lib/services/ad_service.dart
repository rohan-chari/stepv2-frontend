import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gma_mediation_unity/unity_privacy_api.g.dart';
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

/// Narrow rewarded-ad contract for the combined race-payout bonus.
///
/// Its load method accepts the immutable server offer ID, preventing this
/// placement from accidentally reusing the date-shaped extra-spin wire format.
abstract class RacePayoutDoubleAdController {
  bool get isSupported;
  bool get isReady;

  Future<void> loadForRacePayoutDouble({
    required String userId,
    required String offerId,
  });

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
class AdService implements ExtraSpinAdController, RacePayoutDoubleAdController {
  AdService({String? adUnitId, String? customDataPrefix})
    : _adUnitIdOverride = adUnitId,
      _customDataPrefix = customDataPrefix;

  static const _metaAdsChannel = MethodChannel('com.steptracker/meta_ads');

  /// Ceiling on how long load() blocks its caller waiting for the SDK.
  static const _loadTimeout = Duration(seconds: 30);

  /// A rewarded ad normally dismisses within the creative's duration. Do not
  /// leave every caller's action spinner up forever if the SDK loses its
  /// fullscreen callback during an app/network transition.
  static const _showTimeout = Duration(minutes: 3);

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

  // Rewarded unit for the mystery-box reroll (batch 2026-08-08, item 11).
  // A dedicated define per platform with NO fallback (review fix 5): the
  // extra-spin unit's SSV rewards a spin, not a reroll, so borrowing it would
  // grant the wrong thing. Absent the define, [boxRerollSupported] is false
  // and the reroll button is compiled out.
  //
  // PROD-ONLY by convention — staging builds omit the define (see
  // DEPLOYMENT.md). Reroll therefore ships iOS-first, exactly like the
  // extra-spin ad, because that is where the prod defines live today.
  static const _envBoxRerollAdUnitId = String.fromEnvironment(
    'ADMOB_BOX_REROLL_AD_UNIT_ID',
  );
  static const _envBoxRerollAdUnitIdAndroid = String.fromEnvironment(
    'ADMOB_BOX_REROLL_AD_UNIT_ID_ANDROID',
  );

  // Dedicated rewarded units for the combined race-payout bonus. There is
  // deliberately NO fallback: another placement's signed SSV callback must
  // never be consumable for a variable-value race award.
  static const _envRacePayoutDoubleAdUnitId = String.fromEnvironment(
    'ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID',
  );
  static const _envRacePayoutDoubleAdUnitIdAndroid = String.fromEnvironment(
    'ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID_ANDROID',
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

  static final ValueNotifier<bool> _bannerAdsEnabledNotifier =
      ValueNotifier<bool>(true);
  static bool? _testStandardBannerUnitAvailable;
  static bool? _testBoxTopBannerUnitAvailable;
  static bool? _testNativeUnitAvailable;

  static ValueListenable<bool> get bannerAdsEnabledListenable =>
      _bannerAdsEnabledNotifier;

  static bool get bannerAdsRuntimeEnabled => _bannerAdsEnabledNotifier.value;

  static void setBannerAdsEnabled(bool enabled) {
    if (_bannerAdsEnabledNotifier.value == enabled) return;
    _bannerAdsEnabledNotifier.value = enabled;
  }

  @visibleForTesting
  static void setBannerUnitAvailabilityForTesting({
    bool? standard,
    bool? boxTop,
    bool? native,
  }) {
    _testStandardBannerUnitAvailable = standard;
    _testBoxTopBannerUnitAvailable = boxTop;
    _testNativeUnitAvailable = native;
  }

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

  /// Resolved rewarded unit for the mystery-box reroll (item 11).
  ///
  /// NO FALLBACK, deliberately — unlike [powerupUnlockAdUnitId]. When this
  /// platform has no dedicated box-reroll define baked in, this returns '' and
  /// [boxRerollSupported] is false, so the controller never loads and the
  /// REROLL button never appears. Two reasons:
  ///  * it enforces the spec's platform stance (the define is PROD-only, so
  ///    reroll is iOS-first and staging simply doesn't have the feature)
  ///    rather than silently borrowing another surface's unit;
  ///  * borrowing the extra-spin unit would blend two placements' impressions
  ///    and eCPM into one line of AdMob reporting.
  static String get boxRerollAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isIOS) return _envBoxRerollAdUnitId;
    if (Platform.isAndroid) return _envBoxRerollAdUnitIdAndroid;
    return '';
  }

  /// Whether this build can show the box-reroll ad at all. False without the
  /// define — the caller must not offer the button.
  static bool get boxRerollSupported => boxRerollAdUnitId.isNotEmpty;

  /// Dedicated unit for this platform, or an empty string when this build did
  /// not bake one in. Never falls back to a test or unrelated live unit.
  static String get racePayoutDoubleAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isIOS) return _envRacePayoutDoubleAdUnitId;
    if (Platform.isAndroid) return _envRacePayoutDoubleAdUnitIdAndroid;
    return '';
  }

  static bool get racePayoutDoubleSupported =>
      racePayoutDoubleAdUnitId.isNotEmpty;

  static String get _platformBannerUnitId {
    if (kIsWeb) return '';
    if (_testStandardBannerUnitAvailable == true) return 'test-banner-unit';
    if (_testStandardBannerUnitAvailable == false) return '';
    if (Platform.isIOS) return _envBannerAdUnitId;
    if (Platform.isAndroid) return _envBannerAdUnitIdAndroid;
    return '';
  }

  static String get _platformBoxTopBannerUnitId {
    if (kIsWeb) return '';
    if (_testBoxTopBannerUnitAvailable == true) return 'test-box-top-unit';
    if (_testBoxTopBannerUnitAvailable == false) return '';
    if (Platform.isIOS) return _envBoxTopBannerAdUnitId;
    if (Platform.isAndroid) return _envBoxTopBannerAdUnitIdAndroid;
    return '';
  }

  static String get _platformNativeUnitId {
    if (kIsWeb) return '';
    if (_testNativeUnitAvailable == true) return 'test-native-unit';
    if (_testNativeUnitAvailable == false) return '';
    if (Platform.isIOS) return _envNativeAdUnitId;
    if (Platform.isAndroid) return _envNativeAdUnitIdAndroid;
    return '';
  }

  /// Banner rollout is permanent. A banner renders only when this build baked
  /// in a real unit id for the current platform. iOS uses
  /// ADMOB_BANNER_AD_UNIT_ID; Android uses
  /// ADMOB_BANNER_AD_UNIT_ID_ANDROID. Builds that omit their platform's define
  /// (and web) show nothing at all. When off, [AdBannerSlot] collapses to zero
  /// size.
  static bool get bannersEnabled =>
      bannerAdsRuntimeEnabled && !kIsWeb && _platformBannerUnitId.isNotEmpty;

  static bool get boxTopBannerEnabled =>
      bannerAdsRuntimeEnabled &&
      !kIsWeb &&
      _platformBoxTopBannerUnitId.isNotEmpty;

  static bool get nativeAdsEnabled =>
      bannerAdsRuntimeEnabled && !kIsWeb && _platformNativeUnitId.isNotEmpty;

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
    // This app currently has no UMP/consent-provider integration. Explicitly
    // pass the conservative no-consent values before any mediated request;
    // ATT authorization is not GDPR/US-state consent and must not be reused
    // for it. A future consent flow can replace these values at this single
    // mediation boundary before SDK initialization.
    // Use the generated API directly because the package's convenience
    // wrapper does not await its platform-channel calls in 1.9.0.
    final unityPrivacy = UnityPrivacyApi();
    await unityPrivacy.setGDPRConsent(false);
    await unityPrivacy.setCCPAConsent(false);
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

  /// Namespaces this controller's SSV `customData` (batch 2026-08-08, item 11).
  ///
  /// The backend maps customData PREFIXES to reward kinds and falls back to
  /// `extra_daily_spin` for a bare date. So a new rewarded surface that sent a
  /// bare date would mint extra-spin grants, and the two features would eat
  /// each other's credits. With a prefix set, customData becomes
  /// `<prefix>:<userId>:<localDate>` (e.g. `box_reroll:u123:2026-08-08`),
  /// which the backend matches with its own regex + kind.
  final String? _customDataPrefix;
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
    await _loadRewarded(
      userId: userId,
      customData: _customDataFor(userId, localDate),
    );
  }

  @override
  Future<void> loadForRacePayoutDouble({
    required String userId,
    required String offerId,
  }) async {
    await _loadRewarded(
      userId: userId,
      customData: 'race_payout_double:$userId:$offerId',
    );
  }

  Future<void> _loadRewarded({
    required String userId,
    required String customData,
  }) async {
    if (!isSupported || _loading || _ad != null) return;
    _loading = true;
    try {
      await ensureInitialized().timeout(_loadTimeout);

      final completer = Completer<void>();
      await RewardedAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            // The callback type is void, so an async callback's exception
            // would otherwise be unhandled and leave [completer] pending.
            unawaited(() async {
              try {
                // SSV identity: the callback Google sends us echoes these
                // back as user_id / custom_data.
                await ad.setServerSideOptions(
                  ServerSideVerificationOptions(
                    userId: userId,
                    customData: customData,
                  ),
                );
                _ad = ad;
              } catch (error) {
                debugPrint('Rewarded ad setup failed: $error');
                ad.dispose();
              } finally {
                if (!completer.isCompleted) completer.complete();
              }
            }());
          },
          onAdFailedToLoad: (error) {
            debugPrint('Rewarded ad failed to load: $error');
            completer.complete();
          },
        ),
      ).timeout(_loadTimeout);
      // Neither callback firing would wedge _loading true forever, and with it
      // every later load() on this controller (the guard above returns early).
      // Time out instead: a slow fill that lands after this still populates
      // _ad via onAdLoaded, it just doesn't block the caller.
      await completer.future.timeout(
        _loadTimeout,
        onTimeout: () => debugPrint('Rewarded ad load timed out'),
      );
    } on TimeoutException {
      debugPrint('Rewarded ad load timed out');
    } catch (error) {
      debugPrint('Rewarded ad load threw: $error');
    } finally {
      _loading = false;
    }
  }

  /// Bare date for the extra spin (unchanged wire format for the existing
  /// surface); `<prefix>:<userId>:<localDate>` for any namespaced surface.
  String _customDataFor(String userId, String localDate) {
    final prefix = _customDataPrefix;
    if (prefix == null || prefix.isEmpty) return localDate;
    return '$prefix:$userId:$localDate';
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
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
    } catch (error) {
      debugPrint('Rewarded ad show threw: $error');
      ad.dispose();
      if (!completer.isCompleted) completer.complete(false);
    }

    return completer.future.timeout(
      _showTimeout,
      onTimeout: () {
        debugPrint('Rewarded ad fullscreen callback timed out');
        ad.dispose();
        return false;
      },
    );
  }

  @override
  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
