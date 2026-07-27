import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../styles.dart';
import 'pixel_switch.dart';

/// Row toggling whether the user appears on the global leaderboard.
///
/// Lived in Settings until batch 2026-07-27 item 1 moved it onto the
/// leaderboard itself, where the setting is about the thing on screen. Listens
/// to [authService] so it reflects the latest value — including the revert when
/// the backend write fails.
class LeaderboardVisibilityToggle extends StatefulWidget {
  const LeaderboardVisibilityToggle({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LeaderboardVisibilityToggle> createState() =>
      _LeaderboardVisibilityToggleState();
}

class _LeaderboardVisibilityToggleState
    extends State<LeaderboardVisibilityToggle> {
  void _handleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.authService.addListener(_handleChanged);
  }

  @override
  void dispose() {
    widget.authService.removeListener(_handleChanged);
    super.dispose();
  }

  Future<void> _toggle(bool value) async {
    await widget.authService.updateLeaderboardVisibility(value);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.of(context).parchmentBorder,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Hide me from the global leaderboard',
              style: PixelText.body(
                size: 13,
                color: AppColors.of(context).textDark,
              ),
            ),
          ),
          const SizedBox(width: 12),
          PixelSwitch(
            value: widget.authService.hiddenFromLeaderboard,
            onChanged: _toggle,
          ),
        ],
      ),
    );
  }
}
