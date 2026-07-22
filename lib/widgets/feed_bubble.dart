import 'package:flutter/material.dart';
import '../styles.dart';
import 'player_avatar.dart';
import '../constants/powerup_copy.dart';

const _offensiveTypes = {
  'LEG_CRAMP',
  'RED_CARD',
  'WRONG_TURN',
  'BANANA_PEEL',
  'DETOUR_SIGN',
  // IMPOSTER targets a rival (swaps their leaderboard display); classify it with
  // the offensive/targeted feed accent.
  'IMPOSTER',
  // RAINSTORM debuffs every other racer at once — offensive accent.
  'RAINSTORM',
  // SIGNAL_JAMMER stops a rival from using powerups for 1 hour — offensive.
  'SIGNAL_JAMMER',
};

const _shieldTypes = {'COMPRESSION_SOCKS', 'MIRROR'};

const _boostTypes = {
  'PROTEIN_SHAKE',
  'RUNNERS_HIGH',
  'SECOND_WIND',
  'STEALTH_MODE',
  'FANNY_PACK',
  'SHORTCUT',
  'TRAIL_MIX',
  // CLEANSE is a positive/utility self-powerup (clears opponent debuffs); treat
  // it as a boost so the feed renders it with the positive accent color.
  'CLEANSE',
};

/// A feed entry with avatar, color-coded accent, and rich text.
class FeedBubble extends StatelessWidget {
  final String eventType;
  final String? powerupType;
  final String description;
  final String actorName;
  final String relativeTime;
  final bool actorIsUser;

  const FeedBubble({
    super.key,
    required this.eventType,
    this.powerupType,
    required this.description,
    required this.actorName,
    required this.relativeTime,
    this.actorIsUser = false,
  });

  Color _accentColor(BuildContext context) {
    final colors = AppColors.of(context);
    if (eventType == 'POWERUP_BLOCKED' || eventType == 'POWERUP_REFLECTED') {
      return colors.feedShield;
    }
    if (eventType == 'MYSTERY_BOX_EARNED' ||
        eventType == 'MYSTERY_BOX_OPENED') {
      return colors.feedGold;
    }
    if (eventType == 'POWERUP_USED' && powerupType != null) {
      if (_offensiveTypes.contains(powerupType)) return colors.feedAttack;
      if (_shieldTypes.contains(powerupType)) return colors.feedShield;
      if (_boostTypes.contains(powerupType)) return colors.feedBoost;
    }
    return colors.textMid.withValues(alpha: colors.isDark ? 0.9 : 0.4);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Actor avatar
          PlayerAvatar(name: actorName, size: 26, isUser: actorIsUser),
          const SizedBox(width: 8),
          // Description
          Expanded(child: _buildRichDescription(context)),
          const SizedBox(width: 8),
          // Time
          Text(
            relativeTime,
            style: PixelText.title(
              size: 12,
              color: AppColors.of(context).textMid,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichDescription(BuildContext context) {
    final colors = AppColors.of(context);
    if (powerupType != null) {
      // Highlights the powerup's name inside the server-authored description.
      // Resolves through the consolidated copy source so a backend copy change
      // keeps matching the sentence the backend sent.
      final powerupName = PowerupCopy.nameFor(powerupType);
      if (powerupName.isNotEmpty && description.contains(powerupName)) {
        final parts = description.split(powerupName);
        final spans = <TextSpan>[];
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) {
            spans.add(
              TextSpan(
                text: parts[i],
                style: PixelText.body(size: 16, color: colors.textDark),
              ),
            );
          }
          if (i < parts.length - 1) {
            spans.add(
              TextSpan(
                text: powerupName,
                style: PixelText.title(size: 15, color: _accentColor(context)),
              ),
            );
          }
        }
        return RichText(
          text: TextSpan(children: spans),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        );
      }
    }

    return Text(
      description,
      style: PixelText.body(size: 16, color: colors.textDark),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
