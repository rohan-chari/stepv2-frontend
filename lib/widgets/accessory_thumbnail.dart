import 'package:flutter/material.dart';

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
  });

  final String assetKey;
  final int animationFrames;
  final ImageErrorWidgetBuilder? errorBuilder;

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

  Widget _frameZeroCrop(String assetPath, int frames) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = constraints.maxWidth;
        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.topLeft,
            child: Image.asset(
              assetPath,
              width: frameWidth * frames,
              height: constraints.maxHeight,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              errorBuilder: errorBuilder,
            ),
          ),
        );
      },
    );
  }
}
