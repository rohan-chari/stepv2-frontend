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
  const AdBannerSlot({super.key});

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
    // (~50pt) height. Width is inset by the parchment card's margin (8*2) +
    // padding (6*2) so the ad fits inside the panel. The non-deprecated
    // variants only offer the taller "large" size, so we keep the standard
    // anchored size here.
    final width = (MediaQuery.of(context).size.width - 28).truncate();
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
    // Wrap the ad in a parchment card so it reads as a deliberate panel rather
    // than a transparent ad floating over the screen's background.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.parchmentBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: Center(child: AdWidget(ad: ad)),
      ),
    );
  }
}
