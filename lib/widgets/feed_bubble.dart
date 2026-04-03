import 'package:flutter/material.dart';
import '../styles.dart';
import 'player_avatar.dart';

const _powerupDisplayNames = {
  'LEG_CRAMP': 'Leg Cramp',
  'RED_CARD': 'Red Card',
  'SHORTCUT': 'Shortcut',
  'COMPRESSION_SOCKS': 'Compression Socks',
  'PROTEIN_SHAKE': 'Protein Shake',
  'RUNNERS_HIGH': "Runner's High",
  'SECOND_WIND': 'Second Wind',
  'STEALTH_MODE': 'Stealth Mode',
  'WRONG_TURN': 'Wrong Turn',
  'FANNY_PACK': 'Fanny Pack',
  'TRAIL_MIX': 'Trail Mix',
  'BANANA_PEEL': 'Banana Peel',
};

const _offensiveTypes = {
  'LEG_CRAMP',
  'RED_CARD',
  'WRONG_TURN',
  'BANANA_PEEL',
};

const _shieldTypes = {
  'COMPRESSION_SOCKS',
};

const _boostTypes = {
  'PROTEIN_SHAKE',
  'RUNNERS_HIGH',
  'SECOND_WIND',
  'STEALTH_MODE',
  'FANNY_PACK',
  'SHORTCUT',
  'TRAIL_MIX',
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

  Color get _accentColor {
    if (eventType == 'POWERUP_BLOCKED') return AppColors.feedShield;
    if (eventType == 'MYSTERY_BOX_EARNED' ||
        eventType == 'MYSTERY_BOX_OPENED') {
      return AppColors.feedGold;
    }
    if (eventType == 'POWERUP_USED' && powerupType != null) {
      if (_offensiveTypes.contains(powerupType)) return AppColors.feedAttack;
      if (_shieldTypes.contains(powerupType)) return AppColors.feedShield;
      if (_boostTypes.contains(powerupType)) return AppColors.feedBoost;
    }
    return AppColors.textMid.withValues(alpha: 0.4);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Actor avatar
          PlayerAvatar(
            name: actorName,
            size: 26,
            isUser: actorIsUser,
          ),
          const SizedBox(width: 8),
          // Color accent strip + description
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Colored accent bar
                Container(
                  width: 3,
                  height: 20,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: _accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                // Description text
                Expanded(child: _buildRichDescription()),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Time
          Text(
            relativeTime,
            style: PixelText.title(size: 10, color: AppColors.textMid),
          ),
        ],
      ),
    );
  }

  Widget _buildRichDescription() {
    if (powerupType != null) {
      final powerupName = _powerupDisplayNames[powerupType];
      if (powerupName != null && description.contains(powerupName)) {
        final parts = description.split(powerupName);
        final spans = <TextSpan>[];
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) {
            spans.add(TextSpan(
              text: parts[i],
              style: PixelText.body(size: 14, color: AppColors.textDark),
            ));
          }
          if (i < parts.length - 1) {
            spans.add(TextSpan(
              text: powerupName,
              style: PixelText.title(size: 13, color: _accentColor),
            ));
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
      style: PixelText.body(size: 14, color: AppColors.textDark),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
