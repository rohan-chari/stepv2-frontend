import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_ask_dialog.dart';

/// The in-race notification ask.
///
/// Batch 2026-07-27 item 19 turned this from an inline `RetroCard` — which sat
/// in the race-detail scroll view and pushed the race itself down the page —
/// into an **overlay** presented over race detail after the first frame. It
/// renders nothing in the page; the host keeps mounting it exactly where it
/// mounted the card, and the presentation happens off to the side.
///
/// It reuses [NotificationAskDialog] rather than adding a third
/// notification-prompt surface. Only the copy differs: this ask fires mid-race,
/// so it leads with the finish rather than a generic "stay in the race".
///
/// **The dismissal contract is load-bearing and unchanged.** The prompt is
/// ONE-SHOT per device under [storageKey]. It is marked dismissed on NOT NOW,
/// on a barrier dismissal, and on any enable attempt — granted *or* denied. A
/// denial must not nag again inside the race (Profile stays the recovery path,
/// and iOS requires a trip to Settings after a denial anyway). An overlay that
/// reappeared on every race-detail open would be far worse than the card it
/// replaced.
///
/// The class name is deliberately unchanged: `demo_race_demo_mode_test.dart`
/// asserts by type that the demo race never mounts this widget.
class RaceAlertOptInCard extends StatefulWidget {
  const RaceAlertOptInCard({
    super.key,
    required this.onEnable,
    this.storageKey = 'race_alert_card_dismissed_v1',
  });

  /// Null means the host cannot request permission; ask nothing.
  final Future<bool> Function()? onEnable;
  final String storageKey;

  @override
  State<RaceAlertOptInCard> createState() => _RaceAlertOptInCardState();
}

class _RaceAlertOptInCardState extends State<RaceAlertOptInCard> {
  bool _presented = false;

  @override
  void initState() {
    super.initState();
    // After the first frame — never during build, which a modal route forbids.
    WidgetsBinding.instance.addPostFrameCallback((_) => _present());
  }

  Future<void> _present() async {
    final callback = widget.onEnable;
    if (callback == null || _presented || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _presented) return;
    if (prefs.getBool(widget.storageKey) ?? false) return;
    _presented = true;

    final wantsAlerts = await NotificationAskDialog.show(
      context,
      title: 'Don’t miss the finish',
      body: 'Get race invites and important match updates.',
      enableLabel: 'ENABLE NOTIFICATIONS',
    );

    // One-shot: whatever the answer, this device does not get asked again here.
    await prefs.setBool(widget.storageKey, true);
    if (!wantsAlerts) return;

    await callback();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
