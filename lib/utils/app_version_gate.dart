/// Pure logic behind the client force-update gate. The backend returns a
/// version policy (a supported floor + the latest version + store links); this
/// turns the running build's version into a comparable shape and decides whether
/// to hard-block, softly nudge, or do nothing.
///
/// Everything here fails OPEN: any version we can't parse (a garbled header, an
/// empty/absent policy field, an old or partial backend response) resolves to
/// [VersionGateStatus.ok] so a hiccup can never lock a user out of the app.
library;

/// Parses "1.4.2", "1.4.2+45", "1.4.2-beta.1" into [1, 4, 2]. Returns null for
/// anything without leading numeric segments (e.g. "unknown", "").
List<int>? _parseVersion(String? value) {
  if (value == null) return null;
  final core = value.trim().split(RegExp(r'[+-]')).first;
  if (core.isEmpty) return null;
  final segments = core.split('.');
  final parsed = <int>[];
  for (final segment in segments) {
    final n = int.tryParse(segment);
    if (n == null) return null;
    parsed.add(n);
  }
  return parsed.isEmpty ? null : parsed;
}

/// Returns -1 / 0 / 1 comparing [a] against [b]. Missing trailing segments count
/// as zero ("1.4" == "1.4.0"). Returns null if either side is unparseable.
int? compareVersions(String? a, String? b) {
  final left = _parseVersion(a);
  final right = _parseVersion(b);
  if (left == null || right == null) return null;

  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l < r) return -1;
    if (l > r) return 1;
  }
  return 0;
}

/// The three states the gate can resolve to for the running build.
enum VersionGateStatus {
  /// Up to date enough — let the user in with no prompt.
  ok,

  /// A newer build exists but this one is still supported — soft, dismissible.
  updateAvailable,

  /// This build is below the supported floor — hard, non-dismissible block.
  updateRequired,
}

/// The version policy as returned by GET /app-version/policy. Read defensively:
/// every field is optional so an old/partial backend (or a 404 we mapped to an
/// empty map) degrades to "no opinion" rather than crashing.
class VersionPolicy {
  const VersionPolicy({
    this.minSupportedVersion,
    this.latestVersion,
    this.iosUrl,
    this.androidUrl,
  });

  final String? minSupportedVersion;
  final String? latestVersion;
  final String? iosUrl;
  final String? androidUrl;

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  factory VersionPolicy.fromJson(Map<String, dynamic> json) {
    final updateUrl = json['updateUrl'];
    final urlMap = updateUrl is Map ? updateUrl : const {};
    return VersionPolicy(
      minSupportedVersion: _string(json['minSupportedVersion']),
      latestVersion: _string(json['latestVersion']),
      iosUrl: _string(urlMap['ios']),
      androidUrl: _string(urlMap['android']),
    );
  }
}

/// Decides the gate for [currentVersion] against [policy]. The floor is
/// INCLUSIVE — being exactly on minSupportedVersion is supported. Any comparison
/// we can't make resolves to [VersionGateStatus.ok].
VersionGateStatus evaluateVersionGate({
  required String currentVersion,
  required VersionPolicy policy,
}) {
  if (compareVersions(currentVersion, policy.minSupportedVersion) == -1) {
    return VersionGateStatus.updateRequired;
  }
  if (compareVersions(currentVersion, policy.latestVersion) == -1) {
    return VersionGateStatus.updateAvailable;
  }
  return VersionGateStatus.ok;
}
