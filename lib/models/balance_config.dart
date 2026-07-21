/// Client-side types for the admin balance-config API (spec §5.2).
///
/// Every field is read defensively: the backend serving this build may be an
/// older or newer version than the build expects, so an absent or wrong-typed
/// key must degrade rather than throw.
library;

/// A soft-bound violation reported by the backend (`422`) or detected locally
/// from the `bounds` block served by `GET /admin/balance-config`.
class BalanceBoundWarning {
  const BalanceBoundWarning({
    required this.path,
    this.value,
    this.bound,
    required this.message,
  });

  final String path;
  final dynamic value;

  /// `[min, max]` when the backend sent one; null when it did not.
  final List<double>? bound;
  final String message;

  static BalanceBoundWarning? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    if (path is! String || path.isEmpty) return null;
    final message = raw['message'];
    return BalanceBoundWarning(
      path: path,
      value: raw['value'],
      bound: parseBoundPair(raw['bound']),
      message: message is String && message.isNotEmpty
          ? message
          : '$path is outside its sane range',
    );
  }
}

/// `[min, max]` from a raw JSON list, or null when absent/malformed.
List<double>? parseBoundPair(dynamic raw) {
  if (raw is! List || raw.length != 2) return null;
  final min = raw[0];
  final max = raw[1];
  if (min is! num || max is! num) return null;
  if (!min.isFinite || !max.isFinite) return null;
  return [min.toDouble(), max.toDouble()];
}

/// The active balance config plus the code-defined soft bounds the UI uses to
/// warn BEFORE submitting (spec D11/D12).
class AdminBalanceConfig {
  const AdminBalanceConfig({
    required this.version,
    required this.config,
    this.note,
    this.createdBy,
    this.boundOverride = false,
    this.createdAt,
    this.bounds = const {},
  });

  final int version;
  final Map<String, dynamic> config;
  final String? note;
  final String? createdBy;
  final bool boundOverride;
  final String? createdAt;

  /// Bound paths → `[min, max]`. Keys may contain `*` wildcards and either
  /// dotted or bracketed index notation (`upgradeCosts.byRarity.*[3]`).
  final Map<String, List<double>> bounds;

  static AdminBalanceConfig? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final version = raw['version'];
    final config = raw['config'];
    if (version is! num || config is! Map) return null;

    final bounds = <String, List<double>>{};
    final rawBounds = raw['bounds'];
    if (rawBounds is Map) {
      rawBounds.forEach((key, value) {
        final pair = parseBoundPair(value);
        if (key is String && key.isNotEmpty && pair != null) {
          bounds[key] = pair;
        }
      });
    }

    return AdminBalanceConfig(
      version: version.toInt(),
      config: Map<String, dynamic>.from(config),
      note: raw['note'] is String ? raw['note'] as String : null,
      createdBy: raw['createdBy'] is String ? raw['createdBy'] as String : null,
      boundOverride: raw['boundOverride'] == true,
      createdAt: raw['createdAt'] is String ? raw['createdAt'] as String : null,
      bounds: bounds,
    );
  }
}

/// One row of `GET /admin/balance-config/versions`.
class BalanceConfigVersion {
  const BalanceConfigVersion({
    required this.version,
    this.note,
    this.createdBy,
    this.boundOverride = false,
    this.createdAt,
    this.active = false,
  });

  final int version;
  final String? note;
  final String? createdBy;
  final bool boundOverride;
  final String? createdAt;
  final bool active;

  static BalanceConfigVersion? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final version = raw['version'];
    if (version is! num) return null;
    return BalanceConfigVersion(
      version: version.toInt(),
      note: raw['note'] is String ? raw['note'] as String : null,
      createdBy: raw['createdBy'] is String ? raw['createdBy'] as String : null,
      boundOverride: raw['boundOverride'] == true,
      createdAt: raw['createdAt'] is String ? raw['createdAt'] as String : null,
      active: raw['active'] == true,
    );
  }
}

enum BalanceConfigSaveStatus {
  /// `201` — the new version is active.
  saved,

  /// `409` — someone else wrote first. NEVER auto-merged (spec D10).
  conflict,

  /// `422` — soft-bound warnings pending an explicit acknowledgement.
  boundWarnings,

  /// `400` hard validation, `403`, transport failure, or an unrecognised
  /// status. Always terminal for this attempt.
  error,
}

/// Outcome of a `PUT`/rollback. Modelled as data rather than an exception so
/// the editor can branch on 409/422 without string-matching an error message.
class BalanceConfigSaveResult {
  const BalanceConfigSaveResult({
    required this.status,
    this.version,
    this.config,
    this.currentVersion,
    this.warnings = const [],
    this.message,
  });

  const BalanceConfigSaveResult.saved({required int version})
    : this(status: BalanceConfigSaveStatus.saved, version: version);

  const BalanceConfigSaveResult.conflict({
    required int currentVersion,
    Map<String, dynamic>? config,
  }) : this(
         status: BalanceConfigSaveStatus.conflict,
         currentVersion: currentVersion,
         config: config,
       );

  const BalanceConfigSaveResult.boundWarnings(
    List<BalanceBoundWarning> warnings,
  ) : this(
        status: BalanceConfigSaveStatus.boundWarnings,
        warnings: warnings,
      );

  const BalanceConfigSaveResult.failed(String message)
    : this(status: BalanceConfigSaveStatus.error, message: message);

  final BalanceConfigSaveStatus status;
  final int? version;

  /// On `conflict`: the CURRENT server config, so the editor can re-diff
  /// without a second request.
  final Map<String, dynamic>? config;
  final int? currentVersion;
  final List<BalanceBoundWarning> warnings;
  final String? message;
}
