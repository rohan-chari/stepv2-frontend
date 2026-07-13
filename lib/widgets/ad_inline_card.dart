import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';

/// In-feed ad row for the races tab: a NATIVE ad rendered by the custom iOS
/// NativeAdFactory registered as 'raceFeedAd' (ios/Runner/
/// RaceFeedNativeAdFactory.swift), styled to read as another row in the race
/// list — parchment background, hairline top divider, race-row typography,
/// "AD" attribution pill in the native layout. The factory's 120x120pt media
/// view meets AdMob's minimum for VIDEO creatives (the stock small template
/// capped media at ~25% width, below the bar), so video stays ON for this ad
/// unit in the AdMob console. Space Grotesk / DM Sans ship as flutter assets
/// (assets/fonts/) and are registered natively at ad-build time. Renders
/// NOTHING — zero size — unless this build has banners enabled AND the ad
/// loads, so lists never show a gap or stray divider for a missing ad. Part
/// of the ad layer alongside AdService: no screen touches the ads SDK.
class AdInlineCard extends StatefulWidget {
  const AdInlineCard({super.key});

  @override
  State<AdInlineCard> createState() => _AdInlineCardState();
}

class _AdInlineCardState extends State<AdInlineCard> {
  // Total row height built by the native factory: 120pt media + 12pt
  // vertical insets on each side. Must match RaceFeedNativeAdFactory.swift.
  static const double _rowHeight = 144;

  NativeAd? _ad;
  bool _adLoaded = false;

  Future<void> _load() async {
    if (!AdService.bannersEnabled) return;
    await AdService.ensureInitialized();
    if (!mounted) return;

    final ad = NativeAd(
      adUnitId: AdService.nativeAdUnitId,
      request: const AdRequest(),
      // Custom layout registered in AppDelegate — replaces the stock
      // NativeTemplateStyle so the media view can be 120x120 (video-eligible)
      // and the row blends with the race list.
      factoryId: 'raceFeedAd',
      nativeAdOptions: NativeAdOptions(
        adChoicesPlacement: AdChoicesPlacement.topRightCorner,
        videoOptions: VideoOptions(startMuted: true),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _adLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          // No fill / error: stay collapsed and the list closes up normally.
          debugPrint('Inline native ad failed to load: $error');
          ad.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _adLoaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void initState() {
    super.initState();
    // A factory-built native ad doesn't need a measured slot width to
    // request — kick off the load immediately.
    _load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdService.bannersEnabled) return const SizedBox.shrink();

    final ad = _ad;
    if (ad == null || !_adLoaded) return const SizedBox.shrink();

    // Edge-to-edge: all chrome (background, divider, insets, AD pill) lives
    // in the native layout so the row sits flush in the section card.
    return SizedBox(
      width: double.infinity,
      height: _rowHeight,
      child: AdWidget(ad: ad),
    );
  }
}
