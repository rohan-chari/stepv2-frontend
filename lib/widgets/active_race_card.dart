import 'dart:async';

import 'package:flutter/material.dart';

import '../styles.dart';
import 'race_card_capybara_row.dart';
import 'retro_card.dart';

/// Portrait card for a single ACTIVE race the user is in. Shows the race name,
/// a ticking "ENDS IN …" countdown, the top-3 racers as capybaras (via
/// [RaceCardCapybaraRow]), and a "YOU: Nth" placement badge. Tapping opens the
/// race detail.
///
/// Designed to live inside a horizontally-scrollable row on the home page.
class ActiveRaceCard extends StatefulWidget {
  const ActiveRaceCard({
    super.key,
    required this.raceId,
    required this.raceName,
    required this.endsAt,
    required this.top3,
    this.userPlacement,
    this.onTap,
    this.width = 200,
  });

  final String raceId;
  final String raceName;

  /// May be null if the backend omitted endsAt (older/missing field). The
  /// countdown is hidden in that case rather than crashing.
  final DateTime? endsAt;

  /// Up to 3 participants in rank order.
  final List<Map<String, dynamic>> top3;

  /// 1-based placement of the viewer in this race, or null if unknown.
  final int? userPlacement;

  final VoidCallback? onTap;
  final double width;

  @override
  State<ActiveRaceCard> createState() => _ActiveRaceCardState();
}

class _ActiveRaceCardState extends State<ActiveRaceCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.endsAt != null) {
      // Tick once a second so the countdown stays live, like races_tab /
      // public_races_screen.
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTimeLeft(DateTime endsAt) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return 'soon';
    if (remaining.inDays > 0) {
      return '${remaining.inDays}d ${remaining.inHours.remainder(24)}h';
    }
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
    }
    if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}m ${remaining.inSeconds.remainder(60)}s';
    }
    return '${remaining.inSeconds}s';
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  Color _placementColor(int? placement) {
    switch (placement) {
      case 1:
        return AppColors.medalGold;
      case 2:
        return AppColors.medalSilver;
      case 3:
        return AppColors.medalBronze;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final endsAt = widget.endsAt;
    final placement = widget.userPlacement;
    final placementColor = _placementColor(placement);

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.width,
        child: RetroCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.raceName.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PixelText.title(size: 13, color: AppColors.textDark),
              ),
              const SizedBox(height: 4),
              if (endsAt != null)
                Row(
                  children: [
                    Text(
                      'ENDS IN ',
                      style: PixelText.body(size: 9, color: AppColors.textMid),
                    ),
                    Text(
                      _formatTimeLeft(endsAt),
                      style: PixelText.body(
                        size: 10,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              RaceCardCapybaraRow(top3: widget.top3),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Color.lerp(placementColor, AppColors.parchment, 0.78),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: placementColor, width: 1.5),
                ),
                child: Text(
                  placement != null ? 'YOU: ${_ordinal(placement)}' : 'YOU: —',
                  textAlign: TextAlign.center,
                  style: PixelText.button(size: 11, color: AppColors.textDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
