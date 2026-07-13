import 'package:flutter/material.dart';

import '../config/animals.dart';
import '../styles.dart';
import 'home_course_track.dart' show CapybaraSpriteWithAccessories;

/// Shared UI primitives for the redesigned race surfaces (home active cards,
/// featured strip, race detail). Extracted so the look stays consistent and
/// the patterns aren't re-implemented per screen.

/// Canonical card decoration: parchment fill, 14px radius, 2px roofDark
/// border, and the hard-offset "game piece" shadow shared with the home tab.
BoxDecoration raceCardDecoration() => BoxDecoration(
  color: AppColors.parchment,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(
    color: AppColors.roofDark.withValues(alpha: 0.55),
    width: 2,
  ),
  boxShadow: const [
    BoxShadow(color: Color(0x66000000), offset: Offset(0, 4), blurRadius: 0),
  ],
);

/// Section title row (optional icon + title + optional trailing widget). Sits
/// above a section card.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: AppColors.pillGoldDark),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            title,
            style: PixelText.title(size: 22, color: AppColors.textDark),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// A rounded badge pill.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.background,
    this.foreground = AppColors.textDark,
    this.fontSize = 12,
  });

  final String label;
  final Color background;
  final Color foreground;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: PixelText.title(size: fontSize, color: foreground)),
    );
  }
}

/// Placement badge: medal-tinted for the podium, neutral otherwise, or a
/// fallback label (e.g. LIVE) when there's no placement yet.
class PlacementPill extends StatelessWidget {
  const PlacementPill({super.key, required this.placement, this.fallbackLabel = 'LIVE'});

  final int? placement;
  final String fallbackLabel;

  static String ordinal(int n) {
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

  @override
  Widget build(BuildContext context) {
    final p = placement;
    final (Color bg, Color fg, String label) = switch (p) {
      1 => (AppColors.medalGold, AppColors.textDark, ordinal(1)),
      2 => (AppColors.medalSilver, AppColors.textDark, ordinal(2)),
      3 => (AppColors.medalBronze, AppColors.textDark, ordinal(3)),
      null => (AppColors.parchmentDark, AppColors.textMid, fallbackLabel),
      _ => (AppColors.parchmentDark, AppColors.textMid, ordinal(p)),
    };
    return Pill(label: label, background: bg, foreground: fg, fontSize: 13);
  }
}

/// Small stat: an uppercase label above a bold value.
class StatColumn extends StatelessWidget {
  const StatColumn({
    super.key,
    required this.label,
    required this.value,
    this.alignment = CrossAxisAlignment.start,
    this.valueColor,
  });

  final String label;
  final String value;
  final CrossAxisAlignment alignment;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: PixelText.body(size: 10, color: AppColors.textMid)),
        const SizedBox(height: 2),
        Text(
          value,
          style: PixelText.title(size: 14, color: valueColor ?? AppColors.textDark),
        ),
      ],
    );
  }
}

/// A single medal-ringed capybara avatar with a parchment outer ring (so
/// overlapping avatars read as separate).
class RacerAvatar extends StatelessWidget {
  const RacerAvatar({
    super.key,
    required this.rank,
    required this.accessories,
    this.size = 40,
    this.ringColor,
    this.animal,
  });

  final int rank;
  final List<Map<String, dynamic>> accessories;
  final String? animal;
  final double size;
  final Color? ringColor;

  static Color medalColor(int rank) => switch (rank) {
    1 => AppColors.medalGold,
    2 => AppColors.medalSilver,
    3 => AppColors.medalBronze,
    _ => AppColors.parchmentBorder,
  };

  @override
  Widget build(BuildContext context) {
    final color = ringColor ?? medalColor(rank);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: AppColors.parchment,
        shape: BoxShape.circle,
      ),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color.lerp(color, AppColors.parchment, 0.62),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: ClipOval(
          child: CapybaraSpriteWithAccessories(
            accessories: accessories,
            capybaraSize: size - 12,
            frameIndex: 0,
            animal: animal,
          ),
        ),
      ),
    );
  }
}

/// Up to [maxAvatars] racers as overlapping, medal-ringed avatars. Each entry
/// may contain `rank`, `equippedAccessories`, and `isStealthed`.
class RacerAvatarStack extends StatelessWidget {
  const RacerAvatarStack({
    super.key,
    required this.entries,
    this.size = 40,
    this.step = 26,
    this.maxAvatars = 3,
  });

  final List<Map<String, dynamic>> entries;
  final double size;
  final double step;
  final int maxAvatars;

  @override
  Widget build(BuildContext context) {
    final shown = entries.take(maxAvatars).toList(growable: false);
    if (shown.isEmpty) return SizedBox(height: size);

    final stackWidth = size + (shown.length - 1) * step;
    return SizedBox(
      width: stackWidth,
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < shown.length; i++)
            Positioned(left: i * step, child: _avatar(shown[i], i + 1)),
        ],
      ),
    );
  }

  Widget _avatar(Map<String, dynamic> entry, int fallbackRank) {
    final rank = (entry['rank'] as num?)?.toInt() ?? fallbackRank;
    final isStealthed = entry['isStealthed'] == true;
    final accessories = isStealthed
        ? const <Map<String, dynamic>>[]
        : ((entry['equippedAccessories'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              const <Map<String, dynamic>>[]);
    final animal = isStealthed ? null : animalFromJson(entry['animal']);
    return RacerAvatar(
      rank: rank,
      accessories: accessories,
      size: size,
      animal: animal,
    );
  }
}
