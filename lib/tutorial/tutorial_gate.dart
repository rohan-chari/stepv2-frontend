import 'package:shared_preferences/shared_preferences.dart';

/// Batch 2026-08-09 item 9 — the local safety valve for the mandatory tutorial.
///
/// `tutorialMandatoryEnabled` (backend) can be flipped off without an App Store
/// cycle, but a user who is ALREADY wedged — a `DemoRaceHost` that throws on
/// every entry, a spotlight anchor that never mounts — cannot wait a week for
/// a phased rollout. So the client keeps its own count of tutorial entries that
/// were started and never completed. After [kTutorialAbandonLimit] of them the
/// skip control comes back regardless of the flag.
///
/// Deliberately local-only and deliberately cheap: no backend field, no sync.
/// Losing the counter (sign-out clears prefs) only means a wedged user has to
/// bounce three more times, which is the same guarantee a fresh install gets.
const int kTutorialAbandonLimit = 3;

const String _kAbandonCountKey = 'tutorial_abandon_count_v1';

/// How many tutorial entries have been started without a completion since the
/// last completed run. Never throws — a broken prefs read counts as zero, i.e.
/// mandatory mode stays on, which is the flag's own default posture.
Future<int> tutorialAbandonCount() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kAbandonCountKey) ?? 0;
  } catch (_) {
    return 0;
  }
}

/// Records that the user is entering the tutorial. Called BEFORE the tutorial
/// route is pushed so an entry that crashes on its first frame — or an app kill
/// mid-tutorial, which reaches no callback at all — is still counted.
Future<void> recordTutorialEntry() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_kAbandonCountKey) ?? 0) + 1;
    await prefs.setInt(_kAbandonCountKey, next);
  } catch (_) {}
}

/// Clears the counter. Called on a COMPLETED run — the entry was not abandoned,
/// and a user who has finished once is not wedged.
Future<void> clearTutorialAbandons() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAbandonCountKey);
  } catch (_) {}
}

/// Whether the tutorial's skip affordances should render.
///
/// The single decision point for every escape hatch in item 9, so the intro
/// button, the in-tutorial control and the back handler can never disagree.
bool tutorialSkippable({
  required bool mandatoryEnabled,
  required int abandonCount,
}) => !mandatoryEnabled || abandonCount >= kTutorialAbandonLimit;
