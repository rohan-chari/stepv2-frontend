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

  @override
  State<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends State<AdBannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs MediaQuery for the adaptive width, so not initState.
    if (!_loadStarted) {
      _loadStarted = true;
      _load();
    }
  }

  Future<void> _load() async {
    if (!AdService.bannersEnabled) return;
    await AdService.ensureInitialized();
    if (!mounted) return;
    // Meta Audience Network doesn't support anchored-adaptive banners. Keep
    // the near-full-width treatment, but use Meta's supported flexible-width,
    // fixed-height banner format. The small inset keeps the tappable creative
    // off the screen edges and leaves room for the 2px poster frame.
    final width = (MediaQuery.of(context).size.width - 16).truncate();
    final size = AdSize(width: width, height: 50);
    final ad = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() => _loaded = true);
          }
        },
        onAdFailedToLoad: (ad, error) {
          // No fill / error: stay collapsed. Common while the AdMob app is
          // new or unverified; the screen simply has no banner.
          debugPrint('Banner ad failed to load: $error');
          ad.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
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
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
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
              style: PixelText.body(size: 8, color: AppColors.textMid),
            ),
            const SizedBox(height: 2),
            _poster(ad, frame: AppColors.parchmentBorder),
          ],
        ),
      );
    }

    // Trackside board: an opaque strip in the arcade green one step darker
    // than the page's roofLight checker, under a hard pixel keyline — the
    // same header/footer treatment the rest of the screen chrome uses — so
    // the footer belongs to the scene and only the small poster is "ad".
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.roofMid,
        border: Border(top: BorderSide(color: AppColors.roofEdge, width: 2)),
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
                style: PixelText.body(size: 8, color: AppColors.roofRidge),
              ),
              const SizedBox(height: 2),
              _poster(ad, frame: AppColors.roofEdge),
            ],
          ),
        ),
      ),
    );
  }
}
