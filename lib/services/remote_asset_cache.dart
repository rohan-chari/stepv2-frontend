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
    for (final kind in RemoteAssetKind.values) kind: <String, RemoteAssetEntry>{},
  };

  /// Filenames present in [_cacheDir], so [cachedFile] answers without a
  /// syscall on every frame.
  final Set<String> _onDisk = <String>{};
  final Set<String> _inFlight = <String>{};

  Directory? _cacheDir;
  RemoteAssetFetcher? _fetcher;
  bool _initialized = false;

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

  bool get hasEntries =>
      _registry.values.any((entries) => entries.isNotEmpty);

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
  Future<File?> fetch(RemoteAssetKind kind, String key) async {
    final dir = _cacheDir;
    final entry = _registry[kind]![key];
    if (dir == null || entry == null) return null;

    final name = _fileNameFor(kind, key, entry.version);
    if (_onDisk.contains(name)) return File('${dir.path}/$name');
    if (_inFlight.contains(name)) return null;
    _inFlight.add(name);
    try {
      final uri = Uri.tryParse(entry.url);
      if (uri == null) return null;
      final bytes = await (_fetcher ?? _httpFetch)(uri, const {});
      if (bytes == null || bytes.isEmpty) return null;

      if (!dir.existsSync()) await dir.create(recursive: true);
      // Atomic publish: a half-written file must never be visible under the
      // name the renderer reads.
      final tmp = File('${dir.path}/$name.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      final target = File('${dir.path}/$name');
      await tmp.rename(target.path);
      _onDisk.add(name);
      await _deleteStaleSiblings(dir, kind, key, keep: name);
      return target;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(name);
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
      if (section is! Map) continue;
      final parsed = <String, RemoteAssetEntry>{};
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
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
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
    bool keepRegistry = false,
  }) async {
    _initialized = true;
    _cacheDir = cacheDir ?? _cacheDir;
    _bundledAssets = bundledAssets ?? (keepRegistry ? _bundledAssets : <String>{});
    _fetcher = fetcher ?? (keepRegistry ? _fetcher : null);
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
