import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/backend_config.dart';

/// Which family of art a key belongs to. The kind is part of the on-disk
/// filename, so an accessory and a powerup that happen to share a key can
/// never collide in the flat cache directory.
enum RemoteAssetKind { accessories, characters, powerups }

/// One manifest row: an immutable, versioned URL plus (for characters) the
/// walk-sheet metadata that used to be compiled into `kAnimalSprites`.
@immutable
class RemoteAssetEntry {
  const RemoteAssetEntry({
    required this.url,
    this.animationFrames,
    this.baselineOffset,
  });

  final String url;

  /// Frames in a horizontal sheet. Null = the backend didn't say; callers keep
  /// their own default rather than inventing one.
  final int? animationFrames;

  /// Vertical ground-line correction as a fraction of the frame size.
  final double? baselineOffset;

  /// The immutable version stamped into the filename (`<key>@<version>.png`).
  /// The filename IS the cache key, so a new version is simply a new file.
  String get version {
    final segment = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
    final match = RegExp(r'@([A-Za-z0-9]+)\.[A-Za-z0-9]+$').firstMatch(segment);
    if (match != null) return match.group(1)!;
    // Unversioned URL (shouldn't happen — the backend always stamps one).
    // Derive something stable so the file still caches and still busts when
    // the URL changes.
    return url.hashCode.toUnsigned(32).toRadixString(16);
  }
}

/// Downloads [uri] and returns its bytes, or null when the response wasn't a
/// 200. The seam exists so tests never touch the network; production wires it
/// to the same `dart:io` HttpClient pattern the API service uses.
typedef RemoteAssetFetcher =
    Future<List<int>?> Function(Uri uri, Map<String, String> headers);

/// Registry + disk cache for CDN-served art.
///
/// Bundled art is untouched: [isBundled] answers synchronously off the compiled
/// AssetManifest, and an EMPTY manifest set (pre-[init], or any widget test
/// that never calls it) reports everything as bundled — so the legacy
/// `Image.asset` path is the default, never a regression risk.
class RemoteAssetCache {
  RemoteAssetCache._();

  static final RemoteAssetCache instance = RemoteAssetCache._();

  static const String manifestPrefsKey = 'remote_asset_manifest_v1';
  static const String _cacheDirName = 'remote_assets';
  static const int _prefetchConcurrency = 4;

  Set<String> _bundledAssets = <String>{};
  final Map<RemoteAssetKind, Map<String, RemoteAssetEntry>> _registry = {
    for (final kind in RemoteAssetKind.values)
      kind: <String, RemoteAssetEntry>{},
  };

  /// Filenames present in [_cacheDir], so [cachedFile] answers without a
  /// syscall on every frame.
  final Set<String> _onDisk = <String>{};

  /// One logical asset request per `(kind, key)`. A manifest refresh can
  /// change the versioned filename while a download is pending; callers still
  /// share one request, which retries against the replacement manifest entry
  /// before publishing anything visible to a renderer.
  final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};

  Directory? _cacheDir;
  RemoteAssetFetcher? _fetcher;
  bool _initialized = false;

  // This binary advertises `remote_asset_preferred`, so a valid manifest row
  // wins over a same-key bundle asset. Frozen binaries retain their compiled
  // bundled-first resolver; the mutable test seam documents that compatibility
  // boundary without ever requiring a backend flag at render time.
  bool _remoteAssetPreferred = true;

  bool get remoteAssetPreferred => _remoteAssetPreferred;

  /// Loads the compiled asset manifest, the on-disk cache index and the last
  /// known remote manifest. Awaited once from `main()`. Never throws: every
  /// failure degrades to "everything is bundled", i.e. today's behavior.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _bundledAssets = manifest.listAssets().toSet();
    } catch (_) {
      _bundledAssets = <String>{};
    }
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/$_cacheDirName');
      if (!dir.existsSync()) await dir.create(recursive: true);
      _cacheDir = dir;
      await _scanCacheDir();
    } catch (_) {
      _cacheDir = null;
    }
    await _restorePersistedManifest();
  }

  // ---------------------------------------------------------------------
  // Registry
  // ---------------------------------------------------------------------

  /// True when [assetPath] ships inside this binary. An empty manifest set
  /// (pre-init) deliberately answers true for everything.
  bool isBundled(String assetPath) =>
      _bundledAssets.isEmpty || _bundledAssets.contains(assetPath);

  RemoteAssetEntry? entry(RemoteAssetKind kind, String key) =>
      _registry[kind]![key];

  bool get hasEntries => _registry.values.any((entries) => entries.isNotEmpty);

  /// Character keys the manifest knows about (used by the tuner's animal
  /// picker alongside the bundled ones).
  Iterable<String> keysOf(RemoteAssetKind kind) => _registry[kind]!.keys;

  // ---------------------------------------------------------------------
  // Disk cache
  // ---------------------------------------------------------------------

  /// The already-downloaded file for [key], or null when it isn't cached at
  /// the version the manifest currently advertises. Synchronous by design so
  /// a warm cache renders on the first frame with no flicker.
  File? cachedFile(RemoteAssetKind kind, String key) {
    final dir = _cacheDir;
    final entry = _registry[kind]![key];
    if (dir == null || entry == null) return null;
    final name = _fileNameFor(kind, key, entry.version);
    if (!_onDisk.contains(name)) return null;
    return File('${dir.path}/$name');
  }

  /// Downloads [key] into the cache and returns the file. Returns null on any
  /// failure — callers render their existing placeholder rather than crash.
  Future<File?> fetch(RemoteAssetKind kind, String key) {
    final dir = _cacheDir;
    if (dir == null || _registry[kind]![key] == null) {
      return Future<File?>.value();
    }

    final requestKey = '${kind.name}-${_sanitize(key)}';
    final inFlight = _inFlight[requestKey];
    if (inFlight != null) return inFlight;

    late final Future<File?> request;
    request = _fetchCurrent(dir: dir, kind: kind, key: key).whenComplete(() {
      if (identical(_inFlight[requestKey], request)) {
        _inFlight.remove(requestKey);
      }
    });
    _inFlight[requestKey] = request;
    return request;
  }

  Future<File?> _fetchCurrent({
    required Directory dir,
    required RemoteAssetKind kind,
    required String key,
  }) async {
    // A fetched entry can be superseded by a manifest refresh at any await.
    // Do not publish the obsolete bytes; keep the same Future alive and retry
    // with the entry that current renderers resolve.
    while (true) {
      final entry = _registry[kind]![key];
      if (entry == null) return null;
      final name = _fileNameFor(kind, key, entry.version);
      if (_onDisk.contains(name)) return File('${dir.path}/$name');

      final bytes = await _fetchBytes(entry);
      if (!_isCurrentEntry(kind, key, entry)) continue;
      if (bytes == null || bytes.isEmpty) return null;

      try {
        if (!dir.existsSync()) await dir.create(recursive: true);
        if (!_isCurrentEntry(kind, key, entry)) continue;
        // Atomic publish: a half-written file must never be visible under the
        // name the renderer reads.
        final tmp = File('${dir.path}/$name.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        if (!_isCurrentEntry(kind, key, entry)) {
          try {
            await tmp.delete();
          } catch (_) {}
          continue;
        }
        final target = File('${dir.path}/$name');
        await tmp.rename(target.path);
        _onDisk.add(name);
        if (!_isCurrentEntry(kind, key, entry)) continue;
        await _deleteStaleSiblings(dir, kind, key, keep: name);
        if (!_isCurrentEntry(kind, key, entry)) continue;
        return target;
      } catch (_) {
        return null;
      }
    }
  }

  bool _isCurrentEntry(
    RemoteAssetKind kind,
    String key,
    RemoteAssetEntry entry,
  ) => identical(_registry[kind]![key], entry);

  Future<List<int>?> _fetchBytes(RemoteAssetEntry entry) async {
    try {
      final uri = Uri.tryParse(entry.url);
      if (uri == null) return null;
      return await (_fetcher ?? _httpFetch)(uri, const {});
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteStaleSiblings(
    Directory dir,
    RemoteAssetKind kind,
    String key, {
    required String keep,
  }) async {
    final prefix = '${kind.name}-${_sanitize(key)}@';
    for (final name in _onDisk.toList()) {
      if (name == keep || !name.startsWith(prefix)) continue;
      _onDisk.remove(name);
      try {
        await File('${dir.path}/$name').delete();
      } catch (_) {}
    }
  }

  Future<void> _scanCacheDir() async {
    final dir = _cacheDir;
    _onDisk.clear();
    if (dir == null || !dir.existsSync()) return;
    for (final item in dir.listSync()) {
      if (item is! File) continue;
      final name = item.path.split(Platform.pathSeparator).last;
      if (name.endsWith('.tmp')) {
        // Leftover from an interrupted write.
        try {
          item.deleteSync();
        } catch (_) {}
        continue;
      }
      _onDisk.add(name);
    }
  }

  String _fileNameFor(RemoteAssetKind kind, String key, String version) =>
      '${kind.name}-${_sanitize(key)}@$version.png';

  static String _sanitize(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  // ---------------------------------------------------------------------
  // Manifest
  // ---------------------------------------------------------------------

  /// Pulls `/assets/manifest`, registers it, persists it and warms the cache.
  /// Best-effort: a failure (offline, or a backend too old to serve the route)
  /// leaves the previous registry in place.
  Future<void> refreshManifest({String releaseChannel = 'prod'}) async {
    // Before init() there is nowhere to cache and nothing to resolve against;
    // this also keeps widget tests (which never init) off the network.
    if (!_initialized) return;
    try {
      final uri = Uri.parse('${BackendConfig.baseUrl}/assets/manifest');
      final bytes = await (_fetcher ?? _httpFetch)(uri, {
        'X-Release-Channel': releaseChannel,
      });
      if (bytes == null || bytes.isEmpty) return;
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return;
      applyManifest(Map<String, dynamic>.from(decoded));
      await _persistManifest(decoded);
      unawaited(prefetchMissing());
    } catch (_) {
      // Older backend / offline / malformed payload — keep today's art.
    }
  }

  /// Replaces the registry from a manifest payload. Every field is read
  /// defensively: an unknown shape drops the row instead of poisoning it.
  void applyManifest(Map<String, dynamic>? json) {
    if (json == null) return;
    for (final kind in RemoteAssetKind.values) {
      final section = json[kind.name];
      final parsed = <String, RemoteAssetEntry>{};
      if (section is Map) {
        section.forEach((key, value) {
          if (key is! String || value is! Map) return;
          final url = value['url'];
          if (url is! String || url.isEmpty) return;
          parsed[key] = RemoteAssetEntry(
            url: url,
            animationFrames: _asInt(value['animationFrames']),
            baselineOffset: _asDouble(value['baselineOffset']),
          );
        });
      }
      _registry[kind]!
        ..clear()
        ..addAll(parsed);
    }
  }

  /// Downloads everything the registry knows about that isn't cached yet.
  /// Fire-and-forget; small files, bounded concurrency.
  Future<void> prefetchMissing() async {
    final pending = <MapEntry<RemoteAssetKind, String>>[];
    for (final kind in RemoteAssetKind.values) {
      for (final key in _registry[kind]!.keys) {
        if (cachedFile(kind, key) == null) pending.add(MapEntry(kind, key));
      }
    }
    var index = 0;
    Future<void> worker() async {
      while (index < pending.length) {
        final item = pending[index++];
        await fetch(item.key, item.value);
      }
    }

    await Future.wait([
      for (var i = 0; i < _prefetchConcurrency && i < pending.length; i++)
        worker(),
    ]);
  }

  Future<void> _persistManifest(Object json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(manifestPrefsKey, jsonEncode(json));
    } catch (_) {}
  }

  Future<void> _restorePersistedManifest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(manifestPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) applyManifest(Map<String, dynamic>.from(decoded));
    } catch (_) {}
  }

  static Future<List<int>?> _httpFetch(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl('GET', uri);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final chunks = await response.toList();
      return chunks.expand((chunk) => chunk).toList(growable: false);
    } finally {
      client.close(force: true);
    }
  }

  static int? _asInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  // ---------------------------------------------------------------------
  // Test seams
  // ---------------------------------------------------------------------

  @visibleForTesting
  Future<void> debugConfigure({
    Directory? cacheDir,
    Set<String>? bundledAssets,
    RemoteAssetFetcher? fetcher,
    bool? remoteAssetPreferred,
    bool keepRegistry = false,
  }) async {
    _initialized = true;
    _cacheDir = cacheDir ?? _cacheDir;
    _bundledAssets =
        bundledAssets ?? (keepRegistry ? _bundledAssets : <String>{});
    _fetcher = fetcher ?? (keepRegistry ? _fetcher : null);
    _remoteAssetPreferred = remoteAssetPreferred ?? true;
    if (!keepRegistry) {
      for (final entries in _registry.values) {
        entries.clear();
      }
    }
    await _scanCacheDir();
  }

  @visibleForTesting
  void debugApplyManifest(Map<String, dynamic>? json) => applyManifest(json);

  @visibleForTesting
  Future<void> debugRescan() => _scanCacheDir();

  @visibleForTesting
  Future<void> debugRestorePersistedManifest() => _restorePersistedManifest();

  @visibleForTesting
  void debugReset() {
    _initialized = false;
    _remoteAssetPreferred = true;
    _cacheDir = null;
    _fetcher = null;
    _bundledAssets = <String>{};
    _onDisk.clear();
    _inFlight.clear();
    for (final entries in _registry.values) {
      entries.clear();
    }
  }
}
