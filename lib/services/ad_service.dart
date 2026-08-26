import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gma_mediation_unity/unity_privacy_api.g.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

enum RewardedAdPlacement {
  extraSpin,
  getCoins,
  powerupUnlock,
  cosmeticUnlock,
  boxReroll,
  racePayoutDouble,
}

@immutable
class RewardedAdContext {
  const RewardedAdContext({
    required this.placement,
    required this.userId,
    required this.customData,
    this.localDate,
  });

  factory RewardedAdContext.extraSpin({
    required String userId,
    required String localDate,
  }) => RewardedAdContext(
    placement: RewardedAdPlacement.extraSpin,
    userId: userId,
    customData: localDate,
    localDate: localDate,
  );

  factory RewardedAdContext.getCoins({
    required String userId,
    required String localDate,
  }) => RewardedAdContext(
    placement: RewardedAdPlacement.getCoins,
    userId: userId,
    customData: 'coins:$localDate',
    localDate: localDate,
  );

  factory RewardedAdContext.powerupUnlock({
    required String userId,
    required String sku,
    required String localDate,
  }) => RewardedAdContext(
    placement: RewardedAdPlacement.powerupUnlock,
    userId: userId,
    customData: 'powerup_unlock:$userId:$sku',
    localDate: localDate,
  );

  factory RewardedAdContext.cosmeticUnlock({
    required String userId,
    required String sku,
    required String localDate,
  }) => RewardedAdContext(
    placement: RewardedAdPlacement.cosmeticUnlock,
    userId: userId,
    customData: 'shop_unlock:$userId:$sku',
    localDate: localDate,
  );

  factory RewardedAdContext.boxReroll({
    required String userId,
    required String localDate,
  }) => RewardedAdContext(
    placement: RewardedAdPlacement.boxReroll,
    userId: userId,
    customData: 'box_reroll:$userId:$localDate',
    localDate: localDate,
  );

  factory RewardedAdContext.racePayoutDouble({
    required String userId,
    required String offerId,
  }) => RewardedAdContext(
    placement: RewardedAdPlacement.racePayoutDouble,
    userId: userId,
    customData: 'race_payout_double:$userId:$offerId',
  );

  final RewardedAdPlacement placement;
  final String userId;
  final String customData;
  final String? localDate;

  @override
  bool operator ==(Object other) =>
      other is RewardedAdContext &&
      placement == other.placement &&
      userId == other.userId &&
      customData == other.customData &&
      localDate == other.localDate;

  @override
  int get hashCode => Object.hash(placement, userId, customData, localDate);
}

abstract class ContextBoundRewardedAdController {
  Future<void> warm(RewardedAdContext context);
  bool isReadyFor(RewardedAdContext context);
  Future<bool> showAndAwaitRewardFor(RewardedAdContext context);
  void disposeContext(RewardedAdContext context);
}

extension ContextBoundExtraSpinAdController on ExtraSpinAdController {
  Future<void> warm(RewardedAdContext context) {
    final controller = this;
    if (controller is ContextBoundRewardedAdController) {
      final contextual = controller as ContextBoundRewardedAdController;
      return contextual.warm(context);
    }
    final legacyData = context.placement == RewardedAdPlacement.boxReroll
        ? context.localDate ?? context.customData
        : context.customData;
    return load(userId: context.userId, localDate: legacyData);
  }

  bool isReadyFor(RewardedAdContext context) {
    final controller = this;
    if (controller is ContextBoundRewardedAdController) {
      final contextual = controller as ContextBoundRewardedAdController;
      return contextual.isReadyFor(context);
    }
    return isReady;
  }

  Future<bool> showAndAwaitRewardFor(RewardedAdContext context) {
    final controller = this;
    if (controller is ContextBoundRewardedAdController) {
      final contextual = controller as ContextBoundRewardedAdController;
      return contextual.showAndAwaitRewardFor(context);
    }
    return showAndAwaitReward();
  }

  void disposeContext(RewardedAdContext context) {
    final controller = this;
    if (controller is ContextBoundRewardedAdController) {
      final contextual = controller as ContextBoundRewardedAdController;
      contextual.disposeContext(context);
    } else {
      dispose();
    }
  }
}

extension ContextBoundRacePayoutAdController on RacePayoutDoubleAdController {
  Future<void> warm(RewardedAdContext context) {
    final controller = this;
    if (controller is ContextBoundRewardedAdController) {
      final contextual = controller as ContextBoundRewardedAdController;
      return contextual.warm(context);
    }
    final prefix = 'race_payout_double:${context.userId}:';
    if (!context.customData.startsWith(prefix)) return Future.value();
    return loadForRacePayoutDouble(
      userId: context.userId,
      offerId: context.customData.substring(prefix.length),
    );
  }

  bool isReadyFor(RewardedAdContext context) {
    final controller = this;
    if (controller is ContextBoundRewardedAdController) {
      final contextual = controller as ContextBoundRewardedAdController;
      return contextual.isReadyFor(context);
    }
    return isReady;
  }

  Future<bool> showAndAwaitRewardFor(RewardedAdContext context) {
    final controller = this;
    if (controller is ContextBoundRewardedAdController) {
      final contextual = controller as ContextBoundRewardedAdController;
      return contextual.showAndAwaitRewardFor(context);
    }
    return showAndAwaitReward();
  }

  void disposeContext(RewardedAdContext context) {
    final controller = this;
    if (controller is ContextBoundRewardedAdController) {
      final contextual = controller as ContextBoundRewardedAdController;
      contextual.disposeContext(context);
    } else {
      dispose();
    }
  }
}

abstract class RewardedAdNativeHandle {
  Future<bool> showAndAwaitReward({required Duration timeout});
  void dispose();
}

typedef RewardedAdLoader =
    Future<RewardedAdNativeHandle?> Function({
      required String adUnitId,
      required String userId,
      required String customData,
    });

class RewardedAdSdkInitializer {
  RewardedAdSdkInitializer(this._initialize);

  final Future<bool> Function() _initialize;
  Future<bool>? _inFlight;
  bool _initialized = false;

  Future<bool> ensureInitialized() {
    if (_initialized) return Future.value(true);
    final existing = _inFlight;
    if (existing != null) return existing;

    late final Future<bool> flight;
    flight = Future<bool>.sync(_initialize)
        .then((initialized) {
          if (initialized) _initialized = true;
          return initialized;
        })
        .whenComplete(() {
          if (identical(_inFlight, flight)) _inFlight = null;
        });
    _inFlight = flight;
    return flight;
  }
}

/// Independently guarded SDK bootstrap seams. Privacy/configuration failures
/// must never prevent the app shell or later independent steps from loading.
/// Mobile Ads itself is the terminal capability check: its failure returns
/// false so no caller constructs SDK ad objects or exposes an unusable CTA.
@visibleForTesting
class AdSdkInitializationSteps {
  const AdSdkInitializationSteps({
    required this.isIos,
    required this.resolveTrackingAuthorization,
    required this.setMetaTrackingEnabled,
    required this.setUnityGdprConsent,
    required this.setUnityCcpaConsent,
    required this.updateRequestConfiguration,
    required this.initializeMobileAds,
  });

  final bool isIos;
  final Future<bool> Function() resolveTrackingAuthorization;
  final Future<void> Function(bool enabled) setMetaTrackingEnabled;
  final Future<void> Function() setUnityGdprConsent;
  final Future<void> Function() setUnityCcpaConsent;
  final Future<void> Function() updateRequestConfiguration;
  final Future<void> Function() initializeMobileAds;

  Future<bool> run() async {
    var trackingAuthorized = false;
    if (isIos) {
      try {
        trackingAuthorized = await resolveTrackingAuthorization();
      } catch (error) {
        debugPrint('ATT initialization failed: $error');
      }
      try {
        await setMetaTrackingEnabled(trackingAuthorized);
      } catch (error) {
        debugPrint('Meta privacy initialization failed: $error');
      }
    }
    try {
      await setUnityGdprConsent();
    } catch (error) {
      debugPrint('Unity GDPR initialization failed: $error');
    }
    try {
      await setUnityCcpaConsent();
    } catch (error) {
      debugPrint('Unity CCPA initialization failed: $error');
    }
    try {
      await updateRequestConfiguration();
    } catch (error) {
      debugPrint('Ad request configuration failed: $error');
    }
    try {
      await initializeMobileAds();
      return true;
    } catch (error) {
      debugPrint('Mobile Ads initialization failed: $error');
      return false;
    }
  }
}

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
/// callback hitting /ads/ssv. Real per-platform IDs are injected with
/// --dart-define like BACKEND_BASE_URL (see DEPLOYMENT.md); an absent rewarded
/// unit disables that placement instead of silently using a test unit.
class AdService
    implements
        ExtraSpinAdController,
        RacePayoutDoubleAdController,
        ContextBoundRewardedAdController {
  AdService({
    String? adUnitId,
    String? customDataPrefix,
    bool requireConfiguredAdUnit = true,
    bool? supportedOverride,
    RewardedAdSdkInitializer? sdkInitializer,
    RewardedAdLoader? rewardedAdLoader,
    DateTime Function()? now,
    Duration maxCacheAge = const Duration(minutes: 45),
  }) : _adUnitIdOverride = adUnitId,
       _customDataPrefix = customDataPrefix,
       _requireConfiguredAdUnit = requireConfiguredAdUnit,
       _supportedOverride = supportedOverride,
       _sdkInitializer = sdkInitializer ?? _productionSdkInitializer,
       _rewardedAdLoader = rewardedAdLoader ?? _loadGoogleRewardedAd,
       _now = now ?? DateTime.now,
       _maxCacheAge = maxCacheAge;

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
  // Rewarded unit for the shop "watch ads to unlock a powerup" flow. A
  // dedicated unit is preferred so its SSV callback can be scoped to this flow,
  // but when the define is absent we fall back only to the real extra-spin
  // rewarded unit. iOS uses the base define; Android the `_ANDROID`.
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
  static bool _sdkOperational = true;
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
  /// (which leaves the placement unsupported). Pass to
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
      _sdkOperational &&
      bannerAdsRuntimeEnabled &&
      !kIsWeb &&
      _platformBannerUnitId.isNotEmpty;

  static bool get boxTopBannerEnabled =>
      _sdkOperational &&
      bannerAdsRuntimeEnabled &&
      !kIsWeb &&
      _platformBoxTopBannerUnitId.isNotEmpty;

  static bool get nativeAdsEnabled =>
      _sdkOperational &&
      bannerAdsRuntimeEnabled &&
      !kIsWeb &&
      _platformNativeUnitId.isNotEmpty;

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
  static final RewardedAdSdkInitializer _productionSdkInitializer =
      RewardedAdSdkInitializer(_initializeProductionSdk);

  static Future<bool> ensureInitialized() async {
    if (!_sdkOperational) return false;
    final initialized = await _productionSdkInitializer.ensureInitialized();
    if (!initialized && _sdkOperational) {
      _sdkOperational = false;
      // Every banner/native surface listens to this gate and disposes or
      // collapses immediately when SDK bootstrap is unavailable.
      _bannerAdsEnabledNotifier.value = false;
    }
    return initialized;
  }

  static Future<bool> _initializeProductionSdk() async {
    final unityPrivacy = UnityPrivacyApi();
    return AdSdkInitializationSteps(
      isIos: !kIsWeb && Platform.isIOS,
      resolveTrackingAuthorization: () async {
        var status = await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          status = await AppTrackingTransparency.requestTrackingAuthorization();
        }
        return status == TrackingStatus.authorized;
      },
      setMetaTrackingEnabled: (enabled) => _metaAdsChannel.invokeMethod<void>(
        'setAdvertiserTrackingEnabled',
        enabled,
      ),
      setUnityGdprConsent: () => unityPrivacy.setGDPRConsent(false),
      setUnityCcpaConsent: () => unityPrivacy.setCCPAConsent(false),
      updateRequestConfiguration: () async {
        if (!kDebugMode) return;
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(
            testDeviceIds: ['9e7526f59bde4aeb8cdc4910cf702487'],
          ),
        );
      },
      initializeMobileAds: () async {
        await MobileAds.instance.initialize();
      },
    ).run();
  }

  final String? _adUnitIdOverride;
  final bool _requireConfiguredAdUnit;
  final bool? _supportedOverride;
  final RewardedAdSdkInitializer _sdkInitializer;
  final RewardedAdLoader _rewardedAdLoader;
  final DateTime Function() _now;
  final Duration _maxCacheAge;

  /// Namespaces this controller's SSV `customData` (batch 2026-08-08, item 11).
  ///
  /// The backend maps customData PREFIXES to reward kinds and falls back to
  /// `extra_daily_spin` for a bare date. So a new rewarded surface that sent a
  /// bare date would mint extra-spin grants, and the two features would eat
  /// each other's credits. With a prefix set, customData becomes
  /// `<prefix>:<userId>:<localDate>` (e.g. `box_reroll:u123:2026-08-08`),
  /// which the backend matches with its own regex + kind.
  final String? _customDataPrefix;
  RewardedAdNativeHandle? _ad;
  RewardedAdContext? _adContext;
  DateTime? _loadedAt;
  RewardedAdContext? _activeContext;
  RewardedAdContext? _desiredContext;
  Future<void>? _loadLoop;
  int _generation = 0;
  bool _disposed = false;
  bool _sdkAvailable = true;

  String get _adUnitId {
    final override = _adUnitIdOverride;
    if (override != null) return override;
    return _platformExtraSpinUnitId;
  }

  @override
  bool get isSupported {
    final platformSupported =
        _supportedOverride ??
        (!kIsWeb && (Platform.isAndroid || Platform.isIOS));
    if (!platformSupported || !_sdkAvailable) return false;
    return !_requireConfiguredAdUnit || _adUnitId.isNotEmpty;
  }

  @override
  bool get isReady {
    final context = _adContext;
    return context != null && isReadyFor(context);
  }

  @override
  Future<void> load({required String userId, required String localDate}) async {
    final customData = _customDataFor(userId, localDate);
    final placement = switch (_customDataPrefix) {
      'box_reroll' => RewardedAdPlacement.boxReroll,
      _ when customData.startsWith('coins:') => RewardedAdPlacement.getCoins,
      _ when customData.startsWith('powerup_unlock:') =>
        RewardedAdPlacement.powerupUnlock,
      _ when customData.startsWith('shop_unlock:') =>
        RewardedAdPlacement.cosmeticUnlock,
      _ => RewardedAdPlacement.extraSpin,
    };
    await warm(
      RewardedAdContext(
        placement: placement,
        userId: userId,
        customData: customData,
        localDate:
            placement == RewardedAdPlacement.extraSpin ||
                placement == RewardedAdPlacement.boxReroll
            ? localDate
            : null,
      ),
    );
  }

  @override
  Future<void> loadForRacePayoutDouble({
    required String userId,
    required String offerId,
  }) async {
    await warm(
      RewardedAdContext.racePayoutDouble(userId: userId, offerId: offerId),
    );
  }

  @override
  Future<void> warm(RewardedAdContext context) {
    if (_disposed ||
        !isSupported ||
        context.userId.trim().isEmpty ||
        context.customData.isEmpty) {
      return Future.value();
    }
    if (isReadyFor(context)) return Future.value();
    if (_ad != null) _disposeReadyAd();

    final active = _activeContext;
    final running = _loadLoop;
    if (running != null) {
      if (active == context && _desiredContext == null) return running;
      if (_desiredContext != context) {
        _desiredContext = context;
        _generation++;
      }
      return running;
    }

    _desiredContext = context;
    late final Future<void> loop;
    loop = _runLoadLoop().whenComplete(() {
      if (identical(_loadLoop, loop)) _loadLoop = null;
    });
    _loadLoop = loop;
    return loop;
  }

  Future<void> _runLoadLoop() async {
    while (!_disposed) {
      final target = _desiredContext;
      if (target == null) return;
      _desiredContext = null;
      _activeContext = target;
      final generation = ++_generation;
      await _loadOne(target, generation);
      _activeContext = null;
    }
  }

  Future<void> _loadOne(RewardedAdContext context, int generation) async {
    if (isReadyFor(context)) return;
    try {
      final initialized = await _sdkInitializer.ensureInitialized().timeout(
        _loadTimeout,
      );
      if (!initialized) {
        _sdkAvailable = false;
        _disposeReadyAd();
        return;
      }
      if (!_accepts(context, generation)) return;

      final loadFuture = _rewardedAdLoader(
        adUnitId: _adUnitId,
        userId: context.userId,
        customData: context.customData,
      );
      RewardedAdNativeHandle? handle;
      try {
        handle = await loadFuture.timeout(_loadTimeout);
      } on TimeoutException {
        unawaited(
          loadFuture
              .then<void>((lateHandle) => lateHandle?.dispose())
              .catchError((_) {}),
        );
        debugPrint('Rewarded ad load timed out');
        return;
      }
      if (handle == null) return;
      if (!_accepts(context, generation)) {
        handle.dispose();
        return;
      }
      _disposeReadyAd();
      _ad = handle;
      _adContext = context;
      _loadedAt = _now();
    } on TimeoutException {
      debugPrint('Rewarded ad SDK initialization timed out');
    } catch (error) {
      debugPrint('Rewarded ad load threw: $error');
    }
  }

  bool _accepts(RewardedAdContext context, int generation) =>
      !_disposed &&
      generation == _generation &&
      _activeContext == context &&
      (_desiredContext == null || _desiredContext == context);

  @override
  bool isReadyFor(RewardedAdContext context) {
    _evictStale();
    return !_disposed && _ad != null && _adContext == context;
  }

  void _evictStale() {
    final loadedAt = _loadedAt;
    if (_ad == null || loadedAt == null) return;
    if (_now().difference(loadedAt) >= _maxCacheAge) _disposeReadyAd();
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
    final context = _adContext;
    if (context == null) return false;
    return showAndAwaitRewardFor(context);
  }

  @override
  Future<bool> showAndAwaitRewardFor(RewardedAdContext context) async {
    if (!isReadyFor(context)) return false;
    final ad = _ad;
    _ad = null;
    _adContext = null;
    _loadedAt = null;
    if (ad == null) return false;
    try {
      return await ad.showAndAwaitReward(timeout: _showTimeout);
    } catch (error) {
      debugPrint('Rewarded ad show threw: $error');
      ad.dispose();
      return false;
    }
  }

  @override
  void disposeContext(RewardedAdContext context) {
    if (_adContext == context) _disposeReadyAd();
    if (_activeContext == context || _desiredContext == context) {
      _generation++;
      if (_desiredContext == context) _desiredContext = null;
    }
  }

  void _disposeReadyAd() {
    _ad?.dispose();
    _ad = null;
    _adContext = null;
    _loadedAt = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _desiredContext = null;
    _disposeReadyAd();
  }
}

Future<RewardedAdNativeHandle?> _loadGoogleRewardedAd({
  required String adUnitId,
  required String userId,
  required String customData,
}) async {
  final completer = Completer<RewardedAdNativeHandle?>();
  await RewardedAd.load(
    adUnitId: adUnitId,
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: (ad) {
        unawaited(() async {
          try {
            await ad.setServerSideOptions(
              ServerSideVerificationOptions(
                userId: userId,
                customData: customData,
              ),
            );
            if (!completer.isCompleted) {
              completer.complete(_GoogleRewardedAdHandle(ad));
            } else {
              ad.dispose();
            }
          } catch (error) {
            debugPrint('Rewarded ad setup failed: $error');
            ad.dispose();
            if (!completer.isCompleted) completer.complete(null);
          }
        }());
      },
      onAdFailedToLoad: (error) {
        debugPrint('Rewarded ad failed to load: $error');
        if (!completer.isCompleted) completer.complete(null);
      },
    ),
  );
  return completer.future;
}

class _GoogleRewardedAdHandle implements RewardedAdNativeHandle {
  _GoogleRewardedAdHandle(this._ad);

  final RewardedAd _ad;

  @override
  Future<bool> showAndAwaitReward({required Duration timeout}) async {
    final completer = Completer<bool>();
    var earned = false;
    _ad.fullScreenContentCallback = FullScreenContentCallback(
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
      await _ad.show(onUserEarnedReward: (_, _) => earned = true);
    } catch (error) {
      debugPrint('Rewarded ad show threw: $error');
      _ad.dispose();
      if (!completer.isCompleted) completer.complete(false);
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        debugPrint('Rewarded ad fullscreen callback timed out');
        _ad.dispose();
        return false;
      },
    );
  }

  @override
  void dispose() => _ad.dispose();
}
