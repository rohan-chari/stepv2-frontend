import '../services/backend_api_service.dart';

/// B3 — maps powerup redeem/use rejection codes to friendly copy.
///
/// The backend's redeem pre-flight (and Rainstorm's per-caster use guard) now
/// return a machine-readable `code` alongside the human `error` string. New
/// clients dress the known codes in the app's voice; anything else — an unknown
/// code, or an OLDER backend that sends no `code` at all — falls back to the
/// server-provided message so we never swallow it or show a raw code.
String powerupUseErrorCopy(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'SIGNAL_JAMMED':
        return 'Powerups are jammed in this race right now — sit tight!';
      case 'RAINSTORM_ACTIVE':
        return 'Your Rainstorm is already active in this race.';
      case 'NO_ELIGIBLE_TARGETS':
        return "Nobody else is out running to rain on right now.";
      default:
        // Unknown/absent code: show whatever the backend said (old-backend
        // compat — its message is already user-facing).
        return error.message;
    }
  }
  return error.toString();
}
