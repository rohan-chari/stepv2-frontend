import 'package:flutter/material.dart';

import '../styles.dart';
import 'home_course_track.dart' show CapybaraSpriteWithAccessories;

/// Renders the top-3 racers of an active race as capybara characters, each with
/// their real equipped cosmetics and a gold/silver/bronze medal accent.
///
/// Reuses [CapybaraSpriteWithAccessories] (no changes to that widget): it
/// already renders ANY user's cosmetics from an equipped-accessory list. A
/// stealthed racer arrives from the backend with `isStealthed: true`,
/// `displayName: "???"`, and an empty accessories list, so it naturally renders
/// as a base (no-cosmetics) capybara with a "???" label.
///
/// Handles edge cases: fewer than 3 participants (renders only what's given),
/// missing cosmetics (base capybara), and null step counts (hidden).
class RaceCardCapybaraRow extends StatefulWidget {
  const RaceCardCapybaraRow({
    super.key,
    required this.top3,
    this.capybaraSize = 34,
  });

  /// Up to 3 participant maps in rank order. Each entry may contain:
  /// `rank`, `displayName`, `equippedAccessories`, `totalSteps`, `isStealthed`.
  final List<Map<String, dynamic>> top3;
  final double capybaraSize;

  @override
  State<RaceCardCapybaraRow> createState() => _RaceCardCapybaraRowState();
}

class _RaceCardCapybaraRowState extends State<RaceCardCapybaraRow>
    with SingleTickerProviderStateMixin {
  // Matches the 6-frame capybara walk sheet / 720ms cycle used elsewhere.
  static const int _frameCount = 6;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static Color _medalColor(int rank) {
    switch (rank) {
      case 1:
        return AppColors.medalGold;
      case 2:
        return AppColors.medalSilver;
      case 3:
        return AppColors.medalBronze;
      default:
        return AppColors.parchmentBorder;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.top3.take(3).toList();
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final frameIndex =
            (_controller.value * _frameCount).floor() % _frameCount;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              _buildRacer(entries[i], i, frameIndex),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRacer(
    Map<String, dynamic> entry,
    int index,
    int frameIndex,
  ) {
    final rank = (entry['rank'] as num?)?.toInt() ?? (index + 1);
    final isStealthed = entry['isStealthed'] == true;
    final displayName =
        isStealthed ? '???' : (entry['displayName'] as String? ?? 'Anonymous');
    final accessories = isStealthed
        ? const <Map<String, dynamic>>[]
        : ((entry['equippedAccessories'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              const <Map<String, dynamic>>[]);
    final totalSteps = entry['totalSteps'];
    final medal = _medalColor(rank);

    return Row(
      children: [
        // Medal-accented capybara puck.
        Container(
          width: widget.capybaraSize + 8,
          height: widget.capybaraSize + 8,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color.lerp(medal, AppColors.parchment, 0.62),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: medal, width: 2),
          ),
          child: ClipRect(
            child: CapybaraSpriteWithAccessories(
              accessories: accessories,
              capybaraSize: widget.capybaraSize,
              frameIndex: frameIndex,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '$rank.',
                    style: PixelText.body(size: 11, color: medal),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.body(
                        size: 11,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isStealthed && totalSteps is num)
                Text(
                  '${_formatSteps(totalSteps.toInt())} steps',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PixelText.body(size: 9, color: AppColors.textMid),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatSteps(int steps) {
    final s = steps.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}
