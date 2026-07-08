import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';
import '../styles.dart';

/// In-feed ad row for list surfaces (races tab): a card-framed inline
/// adaptive banner with an "AD" tag, sized to sit between race rows. Renders
/// NOTHING — zero size — unless this build has banners enabled AND the ad
/// loads, so lists never show a gap or stray divider for a missing ad.
/// Part of the ad layer alongside AdService: no screen touches the ads SDK.
class AdInlineCard extends StatefulWidget {
  const AdInlineCard({super.key});

  @override
  State<AdInlineCard> createState() => _AdInlineCardState();
}

class _AdInlineCardState extends State<AdInlineCard> {
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
    // Inline adaptive banner sized to the card's inner width (list padding +
    // card frame insets), so the creative fills the frame without clipping.
    final width = (MediaQuery.of(context).size.width - 52).truncate();
    final size = AdSize.getInlineAdaptiveBannerAdSize(width, 120);
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
          // No fill / error: stay collapsed and the list closes up normally.
          debugPrint('Inline ad failed to load: $error');
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.parchmentDark,
          border: Border.all(color: AppColors.parchmentBorder, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'AD',
              style: PixelText.body(size: 9, color: AppColors.textMid),
            ),
            const SizedBox(height: 4),
            Center(
              child: SizedBox(
                width: ad.size.width.toDouble(),
                height: ad.size.height.toDouble(),
                child: AdWidget(ad: ad),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
