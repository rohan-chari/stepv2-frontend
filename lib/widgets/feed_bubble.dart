import 'package:flutter/material.dart';
import '../styles.dart';
import 'player_avatar.dart';
import '../utils/powerup_feed_presentation.dart';

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

  Color _colorForMention(BuildContext context, PowerupFeedMention mention) {
    final colors = AppColors.of(context);
    return switch (mention.valence) {
      PowerupFeedValence.harmful => colors.feedAttack,
      PowerupFeedValence.beneficial => colors.feedPositive,
      PowerupFeedValence.neutral =>
        mention.type == 'MYSTERY_POTION' ? colors.feedGold : colors.textMid,
    };
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
    final mentions = PowerupFeedPresentation.mentionsIn(
      description,
      hintedType: powerupType,
    );
    if (mentions.isNotEmpty) {
      final spans = <TextSpan>[];
      var cursor = 0;
      for (final mention in mentions) {
        if (mention.start > cursor) {
          spans.add(
            TextSpan(
              text: description.substring(cursor, mention.start),
              style: PixelText.body(size: 16, color: colors.textDark),
            ),
          );
        }
        spans.add(
          TextSpan(
            text: description.substring(mention.start, mention.end),
            style: PixelText.title(
              size: 15,
              color: _colorForMention(context, mention),
            ),
          ),
        );
        cursor = mention.end;
      }
      if (cursor < description.length) {
        spans.add(
          TextSpan(
            text: description.substring(cursor),
            style: PixelText.body(size: 16, color: colors.textDark),
          ),
        );
      }
      return RichText(text: TextSpan(children: spans));
    }

    return Text(
      description,
      style: PixelText.body(size: 16, color: colors.textDark),
    );
  }
}
