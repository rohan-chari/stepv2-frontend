import Flutter
import GoogleMobileAds
import UIKit
import google_mobile_ads

/// Builds the "raceFeedAd" native ad layout: a 144pt row that matches the
/// races-tab list rows (parchment background, hairline top divider, race-row
/// typography) with a 120x120 media view — the minimum size AdMob requires
/// for VIDEO creatives, which the stock small template can't reach (it caps
/// media at 25% of row width). Registered in AppDelegate; the Dart side
/// (AdInlineCard) requests this factory by id.
final class RaceFeedNativeAdFactory: NSObject, FLTNativeAdFactory {

  // App palette (lib/styles.dart AppColors).
  private enum Palette {
    static let parchment = UIColor(red: 1.0, green: 0.984, blue: 0.961, alpha: 1)  // FFFBF5
    static let parchmentLight = UIColor(red: 0.973, green: 0.949, blue: 0.906, alpha: 1)  // F8F2E7
    static let parchmentDark = UIColor(red: 0.953, green: 0.922, blue: 0.867, alpha: 1)  // F3EBDD
    static let parchmentBorder = UIColor(red: 0.816, green: 0.773, blue: 0.706, alpha: 1)  // D0C5B4
    static let textDark = UIColor(red: 0.129, green: 0.192, blue: 0.157, alpha: 1)  // 213128
    static let textMid = UIColor(red: 0.4, green: 0.475, blue: 0.435, alpha: 1)  // 66796F
    static let pillGreen = UIColor(red: 0.310, green: 0.541, blue: 0.416, alpha: 1)  // 4F8A6A
  }

  /// App fonts, loaded from the variable TTFs shipped as Flutter assets
  /// (assets/fonts/). Every accessor falls back to a system font of matching
  /// weight if asset lookup / CoreText registration fails — the ad must never
  /// render blank text.
  private enum Fonts {
    // 'wght' variation axis id (kCTFontVariationAttribute axis dictionary key).
    private static let wghtAxis = 2_003_265_652

    private static let spaceGrotesk = descriptor(forAsset: "assets/fonts/SpaceGrotesk-Variable.ttf")
    private static let dmSans = descriptor(forAsset: "assets/fonts/DMSans-Variable.ttf")

    // Space Grotesk's wght axis tops out at 700; CoreText clamps, so 800
    // (the Dart side's w800) and 700 render identically.
    static var headline: UIFont { font(spaceGrotesk, wght: 700, size: 17, fallback: .heavy) }
    static var body: UIFont { font(dmSans, wght: 600, size: 12.5, fallback: .semibold) }
    static var cta: UIFont { font(dmSans, wght: 700, size: 13, fallback: .bold) }
    static var adTag: UIFont { font(dmSans, wght: 700, size: 10, fallback: .bold) }

    private static func font(
      _ base: UIFontDescriptor?, wght: CGFloat, size: CGFloat, fallback: UIFont.Weight
    ) -> UIFont {
      guard let base else { return .systemFont(ofSize: size, weight: fallback) }
      let varied = base.addingAttributes([
        UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String):
          [NSNumber(value: wghtAxis): NSNumber(value: Double(wght))]
      ])
      return UIFont(descriptor: varied, size: size)
    }

    private static func descriptor(forAsset asset: String) -> UIFontDescriptor? {
      let key = FlutterDartProject.lookupKey(forAsset: asset)
      guard let path = Bundle.main.path(forResource: key, ofType: nil) else { return nil }
      let url = URL(fileURLWithPath: path) as CFURL
      // Best-effort registration (already-registered errors are fine); the
      // descriptor below references the file directly either way.
      CTFontManagerRegisterFontsForURL(url, .process, nil)
      guard
        let ctDescriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
        let first = ctDescriptors.first,
        let rawAttributes = CTFontDescriptorCopyAttributes(first) as? [String: Any]
      else { return nil }
      var attributes: [UIFontDescriptor.AttributeName: Any] = [:]
      for (name, value) in rawAttributes {
        attributes[UIFontDescriptor.AttributeName(rawValue: name)] = value
      }
      return UIFontDescriptor(fontAttributes: attributes)
    }
  }

  func createNativeAd(
    _ nativeAd: NativeAd,
    customOptions: [AnyHashable: Any]? = nil
  ) -> NativeAdView? {
    let adView = NativeAdView()
    adView.backgroundColor = Palette.parchmentDark

    // Top hairline in the list's divider color so the boundary with the row
    // above reads like every other row boundary.
    let hairline = UIView()
    hairline.translatesAutoresizingMaskIntoConstraints = false
    hairline.backgroundColor = Palette.parchmentBorder.withAlphaComponent(0.9)
    adView.addSubview(hairline)

    // 120x120 media view — REQUIRED size for video eligibility.
    let mediaView = MediaView()
    mediaView.translatesAutoresizingMaskIntoConstraints = false
    mediaView.layer.cornerRadius = 10
    mediaView.clipsToBounds = true
    mediaView.layer.borderWidth = 1
    mediaView.layer.borderColor = Palette.parchmentBorder.cgColor
    adView.addSubview(mediaView)

    let headlineLabel = UILabel()
    headlineLabel.translatesAutoresizingMaskIntoConstraints = false
    headlineLabel.font = Fonts.headline
    headlineLabel.textColor = Palette.textDark
    headlineLabel.numberOfLines = 2
    headlineLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    adView.addSubview(headlineLabel)

    // "AD" attribution pill — always visible.
    let adPill = UIView()
    adPill.translatesAutoresizingMaskIntoConstraints = false
    adPill.backgroundColor = Palette.parchmentLight
    adPill.layer.borderWidth = 1
    adPill.layer.borderColor = Palette.parchmentBorder.cgColor
    adPill.layer.cornerRadius = 8.5
    adView.addSubview(adPill)

    let adPillLabel = UILabel()
    adPillLabel.translatesAutoresizingMaskIntoConstraints = false
    adPillLabel.font = Fonts.adTag
    adPillLabel.textColor = Palette.textMid
    adPillLabel.text = "AD"
    adPill.addSubview(adPillLabel)

    let bodyLabel = UILabel()
    bodyLabel.translatesAutoresizingMaskIntoConstraints = false
    bodyLabel.font = Fonts.body
    bodyLabel.textColor = Palette.textMid
    bodyLabel.numberOfLines = 2
    adView.addSubview(bodyLabel)

    // CTA styled like the app's pill buttons: hard pixel shadow (0,2), no blur.
    let ctaButton = UIButton(type: .custom)
    ctaButton.translatesAutoresizingMaskIntoConstraints = false
    ctaButton.backgroundColor = Palette.pillGreen
    ctaButton.layer.cornerRadius = 10
    ctaButton.layer.shadowColor = Palette.textDark.cgColor
    ctaButton.layer.shadowOpacity = 1
    ctaButton.layer.shadowRadius = 0
    ctaButton.layer.shadowOffset = CGSize(width: 0, height: 2)
    ctaButton.titleLabel?.font = Fonts.cta
    ctaButton.setTitleColor(Palette.parchment, for: .normal)
    ctaButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
    // The SDK handles clicks via the registered callToActionView.
    ctaButton.isUserInteractionEnabled = false
    adView.addSubview(ctaButton)

    NSLayoutConstraint.activate([
      hairline.topAnchor.constraint(equalTo: adView.topAnchor),
      hairline.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
      hairline.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
      hairline.heightAnchor.constraint(equalToConstant: 1),

      mediaView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 8),
      mediaView.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
      mediaView.widthAnchor.constraint(equalToConstant: 120),
      mediaView.heightAnchor.constraint(equalToConstant: 120),

      headlineLabel.leadingAnchor.constraint(equalTo: mediaView.trailingAnchor, constant: 10),
      headlineLabel.topAnchor.constraint(equalTo: adView.topAnchor, constant: 12),
      headlineLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: adPill.leadingAnchor, constant: -6),

      adPill.topAnchor.constraint(equalTo: adView.topAnchor, constant: 12),
      adPill.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -8),
      adPill.heightAnchor.constraint(equalToConstant: 17),

      adPillLabel.leadingAnchor.constraint(equalTo: adPill.leadingAnchor, constant: 6),
      adPillLabel.trailingAnchor.constraint(equalTo: adPill.trailingAnchor, constant: -6),
      adPillLabel.centerYAnchor.constraint(equalTo: adPill.centerYAnchor),

      bodyLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
      bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 2),
      bodyLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: adView.trailingAnchor, constant: -8),

      ctaButton.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -8),
      ctaButton.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -12),
      ctaButton.topAnchor.constraint(
        greaterThanOrEqualTo: bodyLabel.bottomAnchor, constant: 4),
    ])
    adPill.setContentHuggingPriority(.required, for: .horizontal)
    adPill.setContentCompressionResistancePriority(.required, for: .horizontal)
    adPillLabel.setContentHuggingPriority(.required, for: .horizontal)

    // Register asset views, populate, then set nativeAd LAST (per SDK docs).
    adView.headlineView = headlineLabel
    adView.bodyView = bodyLabel
    adView.mediaView = mediaView
    adView.callToActionView = ctaButton

    headlineLabel.text = nativeAd.headline
    bodyLabel.text = nativeAd.body
    bodyLabel.isHidden = nativeAd.body == nil
    ctaButton.setTitle(nativeAd.callToAction, for: .normal)
    ctaButton.isHidden = nativeAd.callToAction == nil

    adView.nativeAd = nativeAd
    return adView
  }
}
