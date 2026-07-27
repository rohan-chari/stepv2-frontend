import 'package:shared_preferences/shared_preferences.dart';

/// Which moment is asking for notification permission.
enum NotificationAskTrigger {
  /// The primary trigger: the first mystery box the user ever opens.
  boxOpen,

  /// The backstop, for users who never open a box: the third app session.
  session,
}

/// Device-scoped onboarding bookkeeping: the health-gate attempt ladder, the
/// degraded "steps not connected" state, the relocated notification ask, the
/// rename chip, the app-session counter, and the just-in-time tip seen-set.
///
/// Every read defaults to the value that reproduces the pre-v3 behavior, so an
/// upgrade-in-place user is never worse off when a key is absent. Every key is
/// listed in [allKeys] and cleared by `AuthService.signOut()` — this is
/// device-scoped state that must not leak across accounts (the same reason the
/// health-authorization flag is cleared there).
class OnboardingStateService {
  static const keyHealthAttemptCount = 'health_attempt_count';
  static const keyHealthEscapedGate = 'health_escaped_gate';
  static const keyHealthProbeInconclusive = 'health_probe_inconclusive';
  static const keyHealthProbeArmedAt = 'health_probe_armed_at';
  static const keyOnboardingSessionId = 'onboarding_session_id';
  static const keyNotifAskCount = 'notif_ask_count';
  static const keyNotifAskedAfterBox = 'notif_asked_after_box';
  static const keyAppSessionCount = 'app_session_count';
  static const keyRenameChipShownCount = 'rename_chip_shown_count';
  static const keyRenameChipDismissed = 'rename_chip_dismissed';
  static const keyCoachTipsSeen = 'coach_tips_seen';

  static const allKeys = <String>[
    keyHealthAttemptCount,
    keyHealthEscapedGate,
    keyHealthProbeInconclusive,
    keyHealthProbeArmedAt,
    keyOnboardingSessionId,
    keyNotifAskCount,
    keyNotifAskedAfterBox,
    keyAppSessionCount,
    keyRenameChipShownCount,
    keyRenameChipDismissed,
    keyCoachTipsSeen,
  ];

  /// Total notification asks allowed per install. "Not now" in-app leaves the
  /// OS permission undetermined, so without a cap the backstop could nag
  /// forever; Settings stays the permanent path either way.
  static const int maxNotificationAsks = 2;

  /// The session on which the backstop fires for a user who never opened a box.
  static const int backstopSession = 3;

  /// The rename chip stops offering itself after this many appearances.
  static const int maxRenameChipShows = 3;

  /// How long an inconclusive iOS probe stays latent before the degraded banner
  /// appears. A 6am signup with a legitimately empty step history must not be
  /// told their health is broken seconds after onboarding.
  static const Duration probeArmingDelay = Duration(hours: 6);

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // -- health gate ----------------------------------------------------------

  Future<int> healthAttemptCount() async =>
      (await _prefs).getInt(keyHealthAttemptCount) ?? 0;

  /// Records one *completed* permission attempt and returns the new count.
  /// `needsHealthConnect` is deliberately not an attempt — it already sends the
  /// user to the Play Store and is a legitimate retry.
  Future<int> bumpHealthAttemptCount() async {
    final prefs = await _prefs;
    final next = (prefs.getInt(keyHealthAttemptCount) ?? 0) + 1;
    await prefs.setInt(keyHealthAttemptCount, next);
    return next;
  }

  Future<bool> escapedHealthGate() async =>
      (await _prefs).getBool(keyHealthEscapedGate) ?? false;

  Future<void> setEscapedHealthGate(bool value) async {
    final prefs = await _prefs;
    if (value) {
      await prefs.setBool(keyHealthEscapedGate, true);
    } else {
      await prefs.remove(keyHealthEscapedGate);
    }
  }

  Future<bool> probeInconclusive() async =>
      (await _prefs).getBool(keyHealthProbeInconclusive) ?? false;

  Future<int?> probeArmedAtMs() async =>
      (await _prefs).getInt(keyHealthProbeArmedAt);

  /// Arms the latent degraded state. Idempotent on the timestamp: re-probing an
  /// already-armed user must not push the 6h window out again.
  Future<void> armProbeInconclusive() async {
    final prefs = await _prefs;
    await prefs.setBool(keyHealthProbeInconclusive, true);
    if (prefs.getInt(keyHealthProbeArmedAt) == null) {
      await prefs.setInt(
        keyHealthProbeArmedAt,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  Future<void> clearProbeInconclusive() async {
    final prefs = await _prefs;
    await prefs.remove(keyHealthProbeInconclusive);
    await prefs.remove(keyHealthProbeArmedAt);
  }

  /// Whether the degraded banner should be visible right now, given the live
  /// authorization state. Escapes are visible immediately (the user chose it);
  /// an inconclusive probe waits out [probeArmingDelay] first.
  static bool degradedBannerVisible({
    required bool onboardingV3Enabled,
    required bool healthAuthorized,
    required bool escapedHealthGate,
    required bool probeInconclusive,
    required int? probeArmedAtMs,
    DateTime? now,
  }) {
    if (!onboardingV3Enabled) return false;
    if (escapedHealthGate && !healthAuthorized) return true;
    if (!probeInconclusive || probeArmedAtMs == null) return false;
    final elapsed =
        (now ?? DateTime.now()).millisecondsSinceEpoch - probeArmedAtMs;
    return elapsed >= probeArmingDelay.inMilliseconds;
  }

  // -- notification ask -----------------------------------------------------

  Future<int> notificationAskCount() async =>
      (await _prefs).getInt(keyNotifAskCount) ?? 0;

  /// The relocated ask (§5.4). Only an undetermined OS permission qualifies —
  /// a previous grant or denial is never re-nagged in-app.
  Future<bool> shouldAskForNotifications({
    required NotificationAskTrigger trigger,
    required bool? permissionState,
  }) async {
    if (permissionState != null) return false;
    final prefs = await _prefs;
    if ((prefs.getInt(keyNotifAskCount) ?? 0) >= maxNotificationAsks) {
      return false;
    }
    switch (trigger) {
      case NotificationAskTrigger.boxOpen:
        return !(prefs.getBool(keyNotifAskedAfterBox) ?? false);
      case NotificationAskTrigger.session:
        return (prefs.getInt(keyAppSessionCount) ?? 0) >= backstopSession;
    }
  }

  Future<void> recordNotificationAsk(NotificationAskTrigger trigger) async {
    final prefs = await _prefs;
    await prefs.setInt(
      keyNotifAskCount,
      (prefs.getInt(keyNotifAskCount) ?? 0) + 1,
    );
    if (trigger == NotificationAskTrigger.boxOpen) {
      await prefs.setBool(keyNotifAskedAfterBox, true);
    }
  }

  // -- sessions -------------------------------------------------------------

  Future<int> bumpSessionCount() async {
    final prefs = await _prefs;
    final next = (prefs.getInt(keyAppSessionCount) ?? 0) + 1;
    await prefs.setInt(keyAppSessionCount, next);
    return next;
  }

  // -- rename chip ----------------------------------------------------------

  Future<bool> shouldShowRenameChip() async {
    final prefs = await _prefs;
    if (prefs.getBool(keyRenameChipDismissed) ?? false) return false;
    return (prefs.getInt(keyRenameChipShownCount) ?? 0) < maxRenameChipShows;
  }

  Future<void> recordRenameChipShown() async {
    final prefs = await _prefs;
    await prefs.setInt(
      keyRenameChipShownCount,
      (prefs.getInt(keyRenameChipShownCount) ?? 0) + 1,
    );
  }

  Future<void> dismissRenameChip() async =>
      (await _prefs).setBool(keyRenameChipDismissed, true);

  // -- sign-out -------------------------------------------------------------

  /// Drops every device-scoped onboarding key. Called from
  /// `AuthService.signOut()` alongside the health-authorization clear.
  static Future<void> clearPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in allKeys) {
      await prefs.remove(key);
    }
  }
}
