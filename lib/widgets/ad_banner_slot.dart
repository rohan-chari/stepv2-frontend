import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';
import '../styles.dart';

/// Full-width adaptive banner for the bottom of low-stakes screens (shop,
/// mystery-box opening). Renders NOTHING — zero size — unless this build has
/// banners enabled (iOS with the ADMOB_BANNER_AD_UNIT_ID dart-define) AND the
/// ad actually loads, so screens never reserve dead space for a missing ad.
/// Part of the ad layer alongside AdService: no screen touches the ads SDK.
class AdBannerSlot extends StatefulWidget {
  const AdBannerSlot({super.key, this.withBottomSafeArea = false});

  /// For hosts whose SafeArea excludes the bottom (race detail): pad the
  /// loaded banner clear of the home indicator. Applied only when an ad is
  /// actually showing, so the collapsed state stays zero-size.
  final bool withBottomSafeArea;

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
    // Full-width anchored adaptive banner: spans the screen at a compact
    // (~50pt) height. Width is inset by a small horizontal buffer (16px each
    // side) so the tappable ad never runs edge-to-edge. The non-deprecated
    // variants only offer the taller "large" size, so we keep the standard
    // anchored size here.
    final width = (MediaQuery.of(context).size.width - 32).truncate();
    // ignore: deprecated_member_use
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      width,
    );
    if (!mounted || size == null) return;
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

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    final bottomPad = widget.withBottomSafeArea
        ? MediaQuery.of(context).padding.bottom
        : 0.0;
    // Anchored footer bar: full-bleed and opaque with a single top divider, so
    // it reads as a fixed footer rather than a card floating over the screen's
    // background. The vertical padding forms a buffer that keeps the tappable
    // ad away from the content above, reducing accidental clicks.
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.parchmentLight,
        border: Border(top: BorderSide(color: AppColors.parchmentBorder)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.only(top: 10, bottom: 10 + bottomPad),
          child: Center(
            child: SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        ),
      ),
    );
  }
}
