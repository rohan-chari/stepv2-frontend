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
  // Horizontal chrome of the card frame around the creative: 6px padding and
  // 2px border on each side. Subtracted from the measured slot width so the
  // ad is requested at exactly the width it will render in.
  static const double _frameInset = 16;
  // Cap the creative height so the ad sits between race rows instead of
  // dominating the list.
  static const int _maxCreativeHeight = 120;

  BannerAd? _ad;
  AdSize? _resolvedSize;
  bool _loadStarted = false;

  /// Requests an inline adaptive banner at the MEASURED slot width (from
  /// LayoutBuilder, so it's the true list-item width rather than a screen-size
  /// guess — a wrong/zero width here is what the SDK rejects with "Invalid ad
  /// width or height").
  Future<void> _loadForWidth(int width) async {
    if (_loadStarted || width <= 0) return;
    _loadStarted = true;
    if (!AdService.bannersEnabled) return;
    await AdService.ensureInitialized();
    if (!mounted) return;

    final size = AdSize.getInlineAdaptiveBannerAdSize(width, _maxCreativeHeight);
    final ad = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) async {
          // Inline adaptive: the size passed to BannerAd is a placeholder —
          // the platform resolves the real creative height at load time, so
          // the frame must be sized from getPlatformAdSize(), not `ad.size`.
          final banner = ad as BannerAd;
          final resolved = await banner.getPlatformAdSize();
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _ad = banner;
            _resolvedSize = resolved ?? banner.size;
          });
        },
        onAdFailedToLoad: (ad, error) {
          // No fill / error: stay collapsed and the list closes up normally.
          debugPrint('Inline ad failed to load (width=$width): $error');
          ad.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _resolvedSize = null;
            });
          }
        },
      ),
    );
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdService.bannersEnabled) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - _frameInset).truncate()
            : 0;
        if (!_loadStarted && slotWidth > 0) {
          // Kick off the load once real layout constraints exist; loading from
          // the build phase itself isn't allowed to call setState.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadForWidth(slotWidth);
          });
        }

        final ad = _ad;
        final size = _resolvedSize;
        if (ad == null || size == null) return const SizedBox.shrink();

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
                    width: size.width.toDouble(),
                    height: size.height.toDouble(),
                    child: AdWidget(ad: ad),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
