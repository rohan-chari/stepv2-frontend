import 'dart:io';

import 'package:flutter/material.dart';

import '../services/remote_asset_cache.dart';

/// Draws a piece of art that may ship in the binary OR be served from the CDN.
///
/// The bundled path is byte-identical to what the app did before CDN art
/// existed — a plain [Image.asset], resolving synchronously to an [AssetImage]
/// (several suites assert exactly that). Only a key the binary does NOT bundle
/// takes the remote path: cached file first (synchronous, no flicker), then a
/// one-shot download, then the caller's [errorBuilder] — which everywhere in
/// this app is the existing CustomPaint / fallback-tile placeholder.
class RemoteOrBundledAccessoryImage extends StatelessWidget {
  const RemoteOrBundledAccessoryImage({
    super.key,
    required this.assetPath,
    required this.remoteKey,
    this.kind = RemoteAssetKind.accessories,
    this.width,
    this.height,
    this.fit,
    this.filterQuality = FilterQuality.none,
    this.errorBuilder,
  });

  /// The bundled asset path, or null for art that can only ever be remote
  /// (e.g. a powerup type this build has no icon for).
  final String? assetPath;

  /// Manifest key: the accessory/character `assetKey`, or the UPPERCASE
  /// powerup type.
  final String remoteKey;

  final RemoteAssetKind kind;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// True when [assetPath] ships in this binary (or when the manifest hasn't
  /// loaded yet, in which case everything stays on the bundled path).
  static bool isBundledPath(String? assetPath) =>
      assetPath != null && RemoteAssetCache.instance.isBundled(assetPath);

  @override
  Widget build(BuildContext context) {
    final path = assetPath;
    if (isBundledPath(path)) {
      return Image.asset(
        path!,
        width: width,
        height: height,
        fit: fit,
        filterQuality: filterQuality,
        errorBuilder: errorBuilder,
      );
    }

    final cache = RemoteAssetCache.instance;
    final cached = cache.cachedFile(kind, remoteKey);
    if (cached != null) return _fileImage(cached);

    if (cache.entry(kind, remoteKey) == null) return _placeholder(context);

    return FutureBuilder<File?>(
      future: cache.fetch(kind, remoteKey),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Transparent hole while the art lands; the surrounding layout math
          // is unchanged, so nothing shifts when it arrives.
          return SizedBox(width: width, height: height);
        }
        final file = snapshot.data;
        if (file == null) return _placeholder(context);
        return _fileImage(file);
      },
    );
  }

  Widget _fileImage(File file) => Image.file(
    file,
    width: width,
    height: height,
    fit: fit,
    filterQuality: filterQuality,
    errorBuilder: errorBuilder,
  );

  Widget _placeholder(BuildContext context) {
    final builder = errorBuilder;
    if (builder == null) return SizedBox(width: width, height: height);
    return builder(context, _RemoteAssetUnavailable(remoteKey), null);
  }
}

class _RemoteAssetUnavailable implements Exception {
  const _RemoteAssetUnavailable(this.key);

  final String key;

  @override
  String toString() => 'Remote asset unavailable: $key';
}

/// Renders a walk-cycle sheet that may be bundled or CDN-served. Bundled
/// sprites keep their [Image.asset]/[AssetImage] identity so the baseline and
/// frame-count suites keep measuring the same widget.
Widget animalSpriteImage({
  required String asset,
  required File? file,
  double? width,
  double? height,
  BoxFit? fit,
  FilterQuality filterQuality = FilterQuality.none,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  if (file != null) {
    return Image.file(
      file,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      errorBuilder: errorBuilder,
    );
  }
  return Image.asset(
    asset,
    width: width,
    height: height,
    fit: fit,
    filterQuality: filterQuality,
    errorBuilder: errorBuilder,
  );
}
