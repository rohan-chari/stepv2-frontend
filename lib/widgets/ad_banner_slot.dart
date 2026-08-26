import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';
import '../styles.dart';

/// How the banner dresses itself for its host surface.
enum AdBannerStyle {
  /// Bottom-of-screen footer on the arcade-green surfaces (race detail, shop,
  /// leaderboard, case opening): a green "trackside board" that merges with
  /// the page, holding the creative as a small framed poster.
  trackside,

  /// Inside a parchment card (race results summary): no footer bar, just the
  /// framed poster with a quiet tag, so the card keeps its own chrome.
  inCard,
}

enum AdBannerPlacement { standard, boxTop }

/// Spacing paired with a banner slot; it follows the same runtime gate so a
/// remote disable never leaves a dead strip in the host screen.
class AdBannerSpacing extends StatelessWidget {
  const AdBannerSpacing({
    super.key,
    this.height = 12,
    this.placement = AdBannerPlacement.standard,
  });

  final double height;
  final AdBannerPlacement placement;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: AdService.bannerAdsEnabledListenable,
    builder: (context, enabled, child) => SizedBox(
      height:
          enabled &&
              (placement == AdBannerPlacement.boxTop
                  ? AdService.boxTopBannerEnabled
                  : AdService.bannersEnabled)
          ? height
          : 0,
    ),
  );
}

/// Compact banner ad for the bottom of low-stakes screens. Renders NOTHING —
/// zero size — unless this build has banners enabled (iOS with the
/// ADMOB_BANNER_AD_UNIT_ID dart-define) AND the ad actually loads, so screens
/// never reserve dead space for a missing ad.
/// Part of the ad layer alongside AdService: no screen touches the ads SDK.
class AdBannerSlot extends StatefulWidget {
  const AdBannerSlot({
    super.key,
    this.withBottomSafeArea = false,
    this.hideWhenKeyboardOpen = false,
    this.style = AdBannerStyle.trackside,
    this.placement = AdBannerPlacement.standard,
    this.reserveSpaceWhileLoading = false,
    this.hidden = false,
    this.sdkInitializer,
  });

  /// For hosts whose SafeArea excludes the bottom (race detail): pad the
  /// loaded banner clear of the home indicator. Applied only when an ad is
  /// actually showing, so the collapsed state stays zero-size.
  final bool withBottomSafeArea;

  /// For hosts with a text composer above the slot (race detail chat):
  /// collapse to zero size while the keyboard is open, so the composer sits
  /// directly above the keyboard instead of the ad. The loaded ad is kept —
  /// the banner snaps back when the keyboard closes.
  final bool hideWhenKeyboardOpen;

  final AdBannerStyle style;
  final AdBannerPlacement placement;
  final bool reserveSpaceWhileLoading;

  /// Collapse to zero size while keeping any loaded ad alive, for hosts that
  /// show the slot on some tabs but not others (the shell footer hides it on
  /// the home tab). Prefer this over unmounting the slot: unmounting disposes
  /// the BannerAd, so every return trip costs a brand-new ad request. Nothing
  /// is requested until the slot is first un-hidden.
  final bool hidden;

  /// Test seam for exercising both platform bootstrap paths without creating
  /// a native SDK object. Production always uses [AdService.ensureInitialized].
  @visibleForTesting
  final Future<bool> Function()? sdkInitializer;

  @override
  State<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends State<AdBannerSlot> {
  // No-fill retry: exponential backoff, hard-capped. An uncapped 60s retry made
  // a long-lived screen (race detail, shop) issue a request a minute forever,
  // which inflates the request count AdMob divides by for match/show rate while
  // adding no inventory. Three tries covers a transient no-fill; a persistent
  // one is a supply problem no amount of retrying fixes.
  static const _retryBaseDelay = Duration(seconds: 60);
  static const _maxRetries = 3;

  BannerAd? _ad;
  bool _loaded = false;
  bool _loadStarted = false;
  int _retries = 0;
  int _loadGeneration = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    AdService.bannerAdsEnabledListenable.addListener(_onBannerGateChanged);
  }

  void _onBannerGateChanged() {
    if (!mounted) return;
    final enabled = widget.placement == AdBannerPlacement.boxTop
        ? AdService.boxTopBannerEnabled
        : AdService.bannersEnabled;
    if (!enabled) {
      _loadGeneration++;
      _retryTimer?.cancel();
      _retryTimer = null;
      _ad?.dispose();
      _ad = null;
      _loaded = false;
      _loadStarted = false;
    } else {
      _loadGeneration++;
      _loadStarted = false;
      _maybeStartLoad();
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs MediaQuery for the adaptive width, so not initState.
    _maybeStartLoad();
  }

  @override
  void didUpdateWidget(AdBannerSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    // First un-hide is what arms the slot (see [AdBannerSlot.hidden]).
    _maybeStartLoad();
  }

  void _maybeStartLoad() {
    if (_loadStarted || widget.hidden) return;
    _loadStarted = true;
    _load();
  }

  Future<void> _load() async {
    final generation = _loadGeneration;
    _retryTimer?.cancel();
    _retryTimer = null;
    final enabled = widget.placement == AdBannerPlacement.boxTop
        ? AdService.boxTopBannerEnabled
        : AdService.bannersEnabled;
    if (!enabled) return;
    bool initialized;
    try {
      initialized =
          await (widget.sdkInitializer?.call() ??
              AdService.ensureInitialized());
    } catch (error) {
      debugPrint('Ad SDK bootstrap threw: $error');
      return;
    }
    if (!initialized) {
      return;
    }
    if (!mounted ||
        generation != _loadGeneration ||
        !enabled ||
        !(widget.placement == AdBannerPlacement.boxTop
            ? AdService.boxTopBannerEnabled
            : AdService.bannersEnabled)) {
      return;
    }
    // Use the standard 320x50 banner format shared by Google demand and our
    // mediation providers. In particular, Meta Audience Network rejects
    // anchored/inline adaptive sizes, while arbitrary screen-width AdSize
    // values are not standard Google banner inventory. AdSize.banner keeps a
    // single request eligible across Google, Meta, and AppLovin.
    const size = AdSize.banner;
    BannerAd? ad;
    try {
      ad = BannerAd(
        adUnitId: widget.placement == AdBannerPlacement.boxTop
            ? AdService.boxTopBannerAdUnitId
            : AdService.bannerAdUnitId,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted && generation == _loadGeneration && enabled) {
              setState(() {
                _loaded = true;
                _retries = 0;
              });
            }
          },
          onAdFailedToLoad: (ad, error) {
            // No fill / error: stay collapsed. Common while the AdMob app is
            // new or unverified; the screen simply has no banner.
            debugPrint('Banner ad failed to load: $error');
            ad.dispose();
            if (generation != _loadGeneration) return;
            if (mounted) {
              setState(() {
                _ad = null;
                _loaded = false;
              });
              if (_retries < _maxRetries) {
                _retryTimer = Timer(_retryBaseDelay * (1 << _retries), _load);
                _retries++;
              }
            }
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (error) {
      debugPrint('Banner ad construction/load threw: $error');
      ad?.dispose();
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _ad = null;
          _loaded = false;
        });
      }
    }
  }

  @override
  void dispose() {
    AdService.bannerAdsEnabledListenable.removeListener(_onBannerGateChanged);
    _retryTimer?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  /// The creative in a hard 2px pixel frame, so it reads as a poster pinned
  /// to the board rather than a raw web view. The frame surrounds the ad
  /// without covering any of it (AdMob forbids overlaying/clipping the
  /// creative). No drop shadow: it would add dead height under the ad.
  Widget _poster(BannerAd ad, {required Color frame}) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: frame, width: 2)),
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hidden) return const SizedBox.shrink();
    final enabled = widget.placement == AdBannerPlacement.boxTop
        ? AdService.boxTopBannerEnabled
        : AdService.bannersEnabled;
    if (!enabled) return const SizedBox.shrink();
    final ad = _ad;
    if (!_loaded || ad == null) {
      if (!widget.reserveSpaceWhileLoading) return const SizedBox.shrink();
      final enabled = widget.placement == AdBannerPlacement.boxTop
          ? AdService.boxTopBannerEnabled
          : AdService.bannersEnabled;
      if (!enabled) return const SizedBox.shrink();
      return const SizedBox(height: 58, width: double.infinity);
    }
    if (widget.hideWhenKeyboardOpen &&
        MediaQuery.of(context).viewInsets.bottom > 0) {
      return const SizedBox.shrink();
    }
    final bottomPad = widget.withBottomSafeArea
        ? MediaQuery.of(context).padding.bottom
        : 0.0;

    if (widget.style == AdBannerStyle.inCard) {
      // Quiet in-card poster: the host card supplies the surface; we only add
      // the tag + frame so the ad doesn't read as part of the card content.
      return Padding(
        padding: EdgeInsets.only(top: 10, bottom: bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SPONSOR',
              style: PixelText.body(
                size: 8,
                color: AppColors.of(context).textMid,
              ),
            ),
            const SizedBox(height: 2),
            _poster(ad, frame: AppColors.of(context).parchmentBorder),
          ],
        ),
      );
    }

    // Trackside board: an opaque strip in the arcade green one step darker
    // than the page's roofLight checker, under a hard pixel keyline — the
    // same header/footer treatment the rest of the screen chrome uses — so
    // the footer belongs to the scene and only the small poster is "ad".
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.of(context).roofMid,
        border: Border(
          top: BorderSide(color: AppColors.of(context).roofEdge, width: 2),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.only(top: 3, bottom: 2 + bottomPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SPONSOR',
                style: PixelText.body(
                  size: 8,
                  color: AppColors.of(context).roofRidge,
                ),
              ),
              const SizedBox(height: 2),
              _poster(ad, frame: AppColors.of(context).roofEdge),
            ],
          ),
        ),
      ),
    );
  }
}
