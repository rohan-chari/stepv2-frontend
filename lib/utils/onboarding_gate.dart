/// The single source of truth for "is this user still in onboarding".
///
/// This used to live inline in four places in `main_shell.dart`, and three of
/// the copies had drifted — they omitted `tutorialOnboardingSeen` from the v1
/// branch, so a share-link drain or an inviter-race offer could fire while the
/// user was still sitting on the tutorial step. Every caller now routes through
/// here, and a structural test asserts the expression is declared exactly once.
///
/// Read every input defensively: an absent backend field resolves to the value
/// that reproduces today's behavior, never to "onboarding is done".
library;

/// Returns true while the user is still behind an onboarding gate.
///
/// * v3 — the health gate (satisfied by authorization *or* the escape hatch),
///   the onboarding **teaching step**, and the first-race step. Notifications
///   are no longer a gate; the ask moved to the first mystery-box open (§5.4),
///   so a user sitting on a gate the flow no longer renders can't get stuck.
///
/// `tutorialOnboardingSeen` keeps its name — it is the wire field, and renaming
/// it would break every frozen client — but under the demo-race spec (§5.8) it
/// means **"cleared the onboarding teaching step"**, satisfied by any of:
/// completing the demo race, skipping it, or (legacy) having completed the old
/// spotlight tutorial before this build. Replaying the spotlight tutorial from
/// Profile → Settings deliberately does NOT set it.
/// * v2 — health and the first-race step only.
/// * v1 — health, notifications, tutorial, first race.
bool isOnboardingGate({
  required bool onboardingV3Enabled,
  required bool onboardingV2Enabled,
  required bool healthAuthorized,
  required bool escapedHealthGate,
  required bool? notificationsState,
  required bool tutorialOnboardingSeen,
  required bool firstRaceOnboardingSeen,
}) {
  if (onboardingV3Enabled) {
    final healthGateSatisfied = healthAuthorized || escapedHealthGate;
    return !healthGateSatisfied ||
        !tutorialOnboardingSeen ||
        !firstRaceOnboardingSeen;
  }
  if (onboardingV2Enabled) {
    return !healthAuthorized || !firstRaceOnboardingSeen;
  }
  return !healthAuthorized ||
      notificationsState == null ||
      !tutorialOnboardingSeen ||
      !firstRaceOnboardingSeen;
}
