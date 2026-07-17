import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';
import '../styles.dart';

/// A parchment-framed "sponsor" card that sits near the tournament champion cap
/// on the bracket board (ESPN / March-Madness "presented by" energy), rendered
/// as a fully policy-compliant AdMob NATIVE ad.
///
/// Compliance is NOT optional: the ad is rendered through the SDK's stock native
/// template ([NativeTemplateStyle]), which draws the mandatory **"Ad" attribution
/// badge + AdChoices icon** and the required native asset views (headline, media/
/// icon, CTA, advertiser). We only add an on-brand parchment frame + a "SPONSOR"
/// eyebrow around it — we do NOT disguise it as pure chrome.
///
/// Gating & fallbacks (defensive, per the app's #1 rule):
/// - Remote kill switch OFF ([AdService.bannersEnabled] false) → renders nothing.
/// - Enabled but no fill / unsupported platform / still loading → a pure-Flutter
///   **house-ad** card (promotes the app itself), so the champion area never
///   shows a blank hole or a stray frame.
/// - Enabled + fill → the labeled native ad inside the parchment frame.
///
/// Pure-Flutter house ad renders reliably everywhere (incl. inside the board's
/// zoom/pan transform); the platform-view native ad is best-effort under that
/// transform.
class TournamentSponsorCard extends StatefulWidget {
  const TournamentSponsorCard({super.key, this.width = 220});

  /// Fixed card width so it lines up under the champion cap.
  final double width;

  @override
  State<TournamentSponsorCard> createState() => _TournamentSponsorCardState();
}

class _TournamentSponsorCardState extends State<TournamentSponsorCard> {
  NativeAd? _ad;
  bool _adLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AdService.bannersEnabled) return; // kill switch off → house ad only.
    await AdService.ensureInitialized();
    if (!mounted) return;

    final ad = NativeAd(
      adUnitId: AdService.nativeAdUnitId,
      request: const AdRequest(),
      // Stock SDK template: it owns the mandatory "Ad" badge + AdChoices +
      // asset views, so the ad is unambiguously labeled and policy-compliant.
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: AppColors.parchment,
        cornerRadius: 10,
      ),
      nativeAdOptions: NativeAdOptions(
        adChoicesPlacement: AdChoicesPlacement.topRightCorner,
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
          // No fill → fall back to the house ad below.
          debugPrint('Tournament sponsor native ad failed to load: $error');
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
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Kill switch off: show nothing at all (instant remote disable).
    if (!AdService.bannersEnabled) return const SizedBox.shrink();

    final ad = _ad;
    final showLiveAd = ad != null && _adLoaded;

    return _frame(
      child: showLiveAd
          // Small template is ~90pt tall; give it a bounded box.
          ? SizedBox(height: 90, child: AdWidget(ad: ad))
          : const _HouseAd(),
    );
  }

  Widget _frame({required Widget child}) {
    return Container(
      width: widget.width,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.parchmentBorder, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              'SPONSOR',
              style: PixelText.title(size: 9, color: AppColors.textMid),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Pure-Flutter house ad shown when there's no paid fill / the SDK is
/// unavailable. Promotes the app itself — never disguised as an external ad, and
/// it carries a small "AD" tag for honesty.
class _HouseAd extends StatelessWidget {
  const _HouseAd();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.parchmentDark.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 30)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rally your crew',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PixelText.title(size: 13, color: AppColors.textDark),
                ),
                const SizedBox(height: 2),
                Text(
                  'Invite friends into the Bracket',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PixelText.body(size: 10.5, color: AppColors.textMid),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.textMid.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'AD',
              style: PixelText.title(size: 7, color: AppColors.textMid),
            ),
          ),
        ],
      ),
    );
  }
}
