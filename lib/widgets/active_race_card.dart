import 'dart:async';

import 'package:flutter/material.dart';

import '../styles.dart';
import 'race_card_capybara_row.dart';

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
        return AppColors.of(context).medalGold;
      case 2:
        return AppColors.of(context).medalSilver;
      case 3:
        return AppColors.of(context).medalBronze;
      default:
        return AppColors.of(context).accent;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.raceName.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(
                size: 14,
                color: AppColors.of(context).textLight,
              ),
            ),
            if (endsAt != null) ...[
              const SizedBox(height: 3),
              Text(
                '${_formatTimeLeft(endsAt)} LEFT',
                style: PixelText.body(
                  size: 11,
                  color: AppColors.of(
                    context,
                  ).textLight.withValues(alpha: 0.75),
                ),
              ),
            ],
            const SizedBox(height: 14),
            RaceCardCapybaraRow(top3: widget.top3),
            const Spacer(),
            Row(
              children: [
                if (placement != null) ...[
                  Icon(
                    Icons.military_tech_rounded,
                    size: 14,
                    color: placementColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_ordinal(placement).toUpperCase()} PLACE',
                    style: PixelText.title(
                      size: 12,
                      color: AppColors.of(context).textLight,
                    ),
                  ),
                ] else
                  Text(
                    'NOT RANKED',
                    style: PixelText.body(
                      size: 11,
                      color: AppColors.of(
                        context,
                      ).textLight.withValues(alpha: 0.7),
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
