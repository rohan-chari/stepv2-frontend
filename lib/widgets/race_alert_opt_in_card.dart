import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../styles.dart';
import 'pill_button.dart';
import 'retro_card.dart';

class RaceAlertOptInCard extends StatefulWidget {
  const RaceAlertOptInCard({
    super.key,
    required this.onEnable,
    this.storageKey = 'race_alert_card_dismissed_v1',
  });

  /// Null means the host cannot request permission; render nothing.
  final Future<bool> Function()? onEnable;
  final String storageKey;

  @override
  State<RaceAlertOptInCard> createState() => _RaceAlertOptInCardState();
}

class _RaceAlertOptInCardState extends State<RaceAlertOptInCard> {
  bool _loading = true;
  bool _hidden = false;
  bool _enabling = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hidden = prefs.getBool(widget.storageKey) ?? false;
      _loading = false;
    });
  }

  Future<void> _dismiss() async {
    setState(() => _hidden = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(widget.storageKey, true);
  }

  Future<void> _enable() async {
    final callback = widget.onEnable;
    if (callback == null || _enabling) return;
    setState(() => _enabling = true);
    final granted = await callback();
    if (!mounted) return;
    setState(() {
      _enabling = false;
      // A denial should not nag again inside the race. Profile remains the
      // recovery path and iOS may require Settings after a denial.
      _hidden = true;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(widget.storageKey, true);
    if (!granted) return;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _hidden || widget.onEnable == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: RetroCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: AppColors.pillGoldDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'DON’T MISS THE FINISH',
                    style: PixelText.title(size: 13, color: AppColors.textDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              'Get race invites and important match updates. Bara won’t ask the system until you tap below.',
              style: PixelText.body(size: 12.5, color: AppColors.textMid),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const Key('race-alerts-not-now'),
                    onPressed: _dismiss,
                    child: const Text('Not now'),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: PillButton(
                    key: const Key('enable-race-alerts'),
                    label: _enabling ? 'ENABLING...' : 'ENABLE RACE ALERTS',
                    fontSize: 10,
                    onPressed: _enabling ? null : _enable,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
