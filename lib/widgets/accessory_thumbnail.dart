import 'package:flutter/material.dart';

import '../services/remote_asset_cache.dart';
import 'remote_or_bundled_accessory_image.dart';

/// Static thumbnail for an accessory PNG (shop rows, reward tiles, spinners).
///
/// Animated accessories are horizontal frame sheets
/// (`renderMetadata.animationFrames` equal-width frames), so rendering the raw
/// asset shows every frame side by side. This crops to frame 0. Needs bounded
/// constraints — wrap in a SizedBox when the parent is unbounded.
class AccessoryThumbnail extends StatelessWidget {
  const AccessoryThumbnail({
    super.key,
    required this.assetKey,
    this.animationFrames = 1,
    this.errorBuilder,
    this.assetPath,
    this.remoteKind = RemoteAssetKind.accessories,
  });

  final String assetKey;
  final int animationFrames;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Which CDN manifest section [assetKey] belongs to when the art isn't
  /// bundled. Character tiles pass [RemoteAssetKind.characters].
  final RemoteAssetKind remoteKind;

  /// Full asset path override for sheets that don't live under
  /// assets/images/accessories/ (e.g. base-character walk cycles).
  final String? assetPath;

  /// Reads `renderMetadata.animationFrames` off a shop-item map, defaulting
  /// to 1 (older backends may not send it).
  static int framesOf(Map<String, dynamic>? item) {
    final meta = item?['renderMetadata'];
    if (meta is! Map) return 1;
    final value = meta['animationFrames'];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 1;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final assetPath =
        this.assetPath ?? 'assets/images/accessories/$assetKey.png';
    final frames = animationFrames < 1 ? 1 : animationFrames;

    // CDN-served art ships no bundled `_thumb.png` to try, so skip straight to
    // the resolver (an Image.asset miss here would just cost a frame and log a
    // bundle error). Everything bundled keeps the thumb-first path below.
    if (!RemoteOrBundledAccessoryImage.isBundledPath(assetPath)) {
      if (frames == 1) return _remoteImage(assetPath, fit: BoxFit.contain);
      return _frameZeroCrop(assetPath, frames);
    }

    // A bundled `<name>_thumb.png` — the art content-cropped out of its
    // canvas (frame 0 for animation sheets) — always wins when present. It
    // both fills the tile properly for art that floats in a padded canvas
    // AND keeps sheets rendering correctly even if the backend's
    // renderMetadata.animationFrames was lost (tuner-wipe incident): without
    // it, an unknown sheet renders as every frame side by side.
    final thumbPath = assetPath.replaceFirst(RegExp(r'\.png$'), '_thumb.png');
    return Image.asset(
      thumbPath,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      errorBuilder: (context, error, stackTrace) => frames == 1
          ? Image.asset(
              assetPath,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              errorBuilder: errorBuilder,
            )
          : _frameZeroCrop(assetPath, frames),
    );
  }

  /// The art itself — bundled `Image.asset` or CDN-served cached file.
  Widget _remoteImage(String assetPath, {BoxFit? fit}) {
    return RemoteOrBundledAccessoryImage(
      assetPath: assetPath,
      remoteKey: assetKey,
      kind: remoteKind,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }

  /// Crops a horizontal frame sheet down to frame 0 and centers it.
  ///
  /// The sheet is laid out at its INTRINSIC size and clipped to its first
  /// 1/frames slice ([Align.widthFactor] shrink-wraps to that slice), so the
  /// crop is exact for any sheet aspect ratio. The surrounding [FittedBox] then
  /// scales that single frame to the tile and [Center] centers it.
  ///
  /// The previous version stretched the sheet into a `frameWidth * frames` box
  /// with `BoxFit.contain`; whenever the tile's aspect ratio didn't happen to
  /// match the sheet's, `contain` letterboxed it and the top-left crop sliced
  /// the letterbox instead of the frame — which is why the corgi and turtle sat
  /// off-center in the shop.
  Widget _frameZeroCrop(String assetPath, int frames) {
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1 / frames,
            child: _remoteImage(assetPath),
          ),
        ),
      ),
    );
  }
}
