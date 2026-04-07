import 'package:flutter/material.dart';

import '../styles.dart';
import 'retro_card.dart';

class FeatureHighlightsRow extends StatelessWidget {
  const FeatureHighlightsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _FeatureCard(
            icon: Icons.directions_walk_rounded,
            label: 'TRACK',
            description: 'Daily steps',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _FeatureCard(
            icon: Icons.emoji_events_rounded,
            label: 'COMPETE',
            description: 'Weekly challenges',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _FeatureCard(
            icon: Icons.handshake_rounded,
            label: 'STAKE',
            description: 'Raise the stakes',
          ),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;

  static const double _tileHeight = 108;
  static const double _iconSlotHeight = 24;
  static const double _labelSlotHeight = 16;

  const _FeatureCard({
    required this.icon,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _tileHeight,
      child: RetroCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: _iconSlotHeight,
              child: Center(
                child: Icon(icon, size: 24, color: AppColors.accent),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: _labelSlotHeight,
              child: Center(
                child: Text(
                  label,
                  style: PixelText.title(size: 12, color: AppColors.textDark),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: Center(
                child: Text(
                  description,
                  style: PixelText.body(size: 10, color: AppColors.textMid),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
