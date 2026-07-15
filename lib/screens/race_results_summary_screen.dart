import 'dart:ui';

import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/race_participant_display.dart';
import '../utils/team_race.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/celebration_confetti.dart';
import '../widgets/game_container.dart';
import '../widgets/home_chrome.dart';
import '../widgets/pill_button.dart';
import '../widgets/spinning_coin.dart';

/// Blurred-backdrop popup summarizing races that finished since the user last
/// opened the app. Reuses the daily-reward modal pattern (transparent Material
/// + [BackdropFilter] blur), pushed via a `PageRouteBuilder(opaque: false)`
/// with a ~250ms fade by the caller.
///
/// [races] are the completed-bucket race maps the user participated in. Reads
/// every field defensively: a race may come from a backend version newer or
/// older than this build.
class RaceResultsSummaryScreen extends StatelessWidget {
  const RaceResultsSummaryScreen({super.key, required this.races});

  final List<Map<String, dynamic>> races;

  @override
  Widget build(BuildContext context) {
    final single = races.length == 1;
    // Celebrate a top-3 finish — or, for team races, a real team WIN
    // (TR-807: ties and losses never confetti; race finishes are the one
    // approved confetti moment).
    final placedTop3 = races.any(raceCountsAsReviewHappyMoment);
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
              child: ColoredBox(
                color: AppColors.roofDark.withValues(alpha: 0.54),
              ),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: GameContainer(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                          frameColor: AppColors.accent,
                          surfaceColor: AppColors.parchmentLight,
                          glowColor: AppColors.coinMid,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                single ? 'RACE FINISHED' : 'RACES FINISHED',
                                textAlign: TextAlign.center,
                                style: HomeText.display(
                                  size: 28,
                                  color: HomeColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                single
                                    ? 'Here\'s how you did.'
                                    : '${races.length} of your races wrapped up.',
                                textAlign: TextAlign.center,
                                style: HomeText.body(
                                  size: 13,
                                  color: HomeColors.muted,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              for (var i = 0; i < races.length; i++) ...[
                                if (i > 0) const SizedBox(height: 10),
                                _ResultCard(race: races[i]),
                              ],
                              const SizedBox(height: 18),
                              PillButton(
                                label: 'NICE',
                                variant: PillButtonVariant.primary,
                                fullWidth: true,
                                // TODO(ads-interstitial): frequency-capped
                                // interstitial fires after this pop (see ADS_TODO.md)
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Screen-bottom trackside footer (same treatment as the
              // leaderboard/shop tabs) instead of a banner nested in the card;
              // collapses to zero size when adless.
              const AdBannerSlot(withBottomSafeArea: true),
            ],
          ),
          if (placedTop3) const Positioned.fill(child: CelebrationConfetti()),
        ],
      ),
    );
  }
}

/// One finished race: name, the user's place, winner, and payout coins.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.race});

  final Map<String, dynamic> race;

  @override
  Widget build(BuildContext context) {
    final name = race['name'] as String? ?? 'Race';
    final participantCount = (race['participantCount'] as num?)?.toInt() ?? 0;
    final myPlacement = (race['myPlacement'] as num?)?.toInt();
    final payoutCoins = (race['myPayoutCoins'] as num?)?.toInt() ?? 0;
    final winner = race['winner'] as Map<String, dynamic>?;
    final winnerName = winner?['displayName'] as String?;

    // TR-807: team-framed result. Tie = winnerTeam null on a completed team
    // race (TR-404). All reads defensive — old payloads have none of this.
    if (TeamRace.isTeamRace(race)) {
      return _buildTeamResult(payoutCoins: payoutCoins, raceName: name);
    }

    final placeText = myPlacement == null
        ? 'Did not finish'
        : participantCount > 0
        ? '${formatOrdinal(myPlacement)} of $participantCount'
        : formatOrdinal(myPlacement);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.parchmentDark,
        border: Border.all(color: AppColors.coinDark, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name,
            style: PixelText.title(size: 15, color: AppColors.textDark),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                myPlacement == 1
                    ? Icons.emoji_events_rounded
                    : Icons.flag_rounded,
                size: 18,
                color: myPlacement == 1
                    ? AppColors.coinDark
                    : AppColors.textMid,
              ),
              const SizedBox(width: 6),
              Text(
                'YOU PLACED',
                style: PixelText.body(size: 11, color: AppColors.textMid),
              ),
              const Spacer(),
              Text(
                placeText.toUpperCase(),
                style: PixelText.number(size: 14, color: AppColors.textDark),
              ),
            ],
          ),
          if (winnerName != null && winnerName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.military_tech_rounded,
                  size: 18,
                  color: AppColors.textMid,
                ),
                const SizedBox(width: 6),
                Text(
                  'WINNER',
                  style: PixelText.body(size: 11, color: AppColors.textMid),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    atName(winnerName),
                    textAlign: TextAlign.right,
                    style: PixelText.title(size: 13, color: AppColors.textDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (payoutCoins > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SpinningCoin(size: 18),
                const SizedBox(width: 6),
                Text(
                  'PAYOUT',
                  style: PixelText.body(size: 11, color: AppColors.textMid),
                ),
                const Spacer(),
                Text(
                  '+$payoutCoins',
                  style: PixelText.number(size: 14, color: AppColors.coinDark),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// TR-807: team-framed variant — outcome banner (VICTORY / DEFEAT / tie
  /// refund copy), winning team plaque + members, and the user's payout.
  Widget _buildTeamResult({required int payoutCoins, required String raceName}) {
    final winnerTeam = TeamRace.winnerTeam(race);
    final myTeam = parseRaceTeam(race['myTeam']);
    final isTie = winnerTeam == null;
    final won = !isTie && myTeam != null && myTeam == winnerTeam;

    final participants =
        (race['participants'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
    final winnerMembers = winnerTeam == null
        ? const <Map<String, dynamic>>[]
        : TeamRace.membersOf(participants, winnerTeam);

    final outcomeColor = isTie
        ? AppColors.textMid
        : won
        ? AppColors.pillGreenDark
        : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.parchmentDark,
        border: Border.all(color: AppColors.coinDark, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            raceName,
            style: PixelText.title(size: 15, color: AppColors.textDark),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                isTie
                    ? Icons.handshake_rounded
                    : won
                    ? Icons.emoji_events_rounded
                    : Icons.flag_rounded,
                size: 18,
                color: isTie ? AppColors.textMid : outcomeColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isTie ? 'It’s a tie — buy-ins refunded' : 'YOUR TEAM',
                  style: PixelText.body(size: 11, color: AppColors.textMid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isTie)
                Text(
                  won ? 'VICTORY' : 'DEFEAT',
                  style: PixelText.number(size: 14, color: outcomeColor),
                ),
            ],
          ),
          if (winnerTeam != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.military_tech_rounded,
                  size: 18,
                  color: TeamRace.colorDark(winnerTeam),
                ),
                const SizedBox(width: 6),
                Text(
                  'WINNERS',
                  style: PixelText.body(size: 11, color: AppColors.textMid),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [
                      TeamRace.teamName(race, winnerTeam).toUpperCase(),
                      if (winnerMembers.isNotEmpty)
                        winnerMembers
                            .map(
                              (m) => atName(
                                m['displayName'] as String? ?? '???',
                              ),
                            )
                            .join(', '),
                    ].join(' — '),
                    textAlign: TextAlign.right,
                    style: PixelText.title(
                      size: 12,
                      color: TeamRace.colorDark(winnerTeam),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (payoutCoins > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SpinningCoin(size: 18),
                const SizedBox(width: 6),
                Text(
                  'PAYOUT',
                  style: PixelText.body(size: 11, color: AppColors.textMid),
                ),
                const Spacer(),
                Text(
                  '+$payoutCoins',
                  style: PixelText.number(size: 14, color: AppColors.coinDark),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
