import 'dart:async';

import 'package:flutter/material.dart';

import '../models/giveaway.dart';
import '../styles.dart';
import 'home_course_track.dart';
import 'home_hero_scene.dart';
import 'pill_button.dart';
import 'referral_contest_chrome.dart';

class ReferralContestOverview extends StatefulWidget {
  const ReferralContestOverview({
    super.key,
    required this.contest,
    required this.onJoin,
    required this.onRules,
    this.equippedAccessories = const [],
    this.equippedAnimal,
  });

  final GiveawayContest contest;
  final VoidCallback onJoin;
  final VoidCallback onRules;
  final List<Map<String, dynamic>> equippedAccessories;
  final String? equippedAnimal;

  @override
  State<ReferralContestOverview> createState() =>
      _ReferralContestOverviewState();
}

class _ReferralContestOverviewState extends State<ReferralContestOverview> {
  Timer? _minuteTicker;

  @override
  void initState() {
    super.initState();
    _minuteTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minuteTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final canJoin =
        widget.contest.status == GiveawayStatus.active &&
        widget.contest.endsAt.isAfter(DateTime.now().toUtc());
    final joinLabel = canJoin
        ? 'JOIN CONTEST'
        : widget.contest.status == GiveawayStatus.scheduled
        ? 'COMING SOON'
        : 'CONTEST ENDED';
    return SingleChildScrollView(
      key: const Key('giveaway-global-overview-scroll'),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PrizeCard(contest: widget.contest),
          const SizedBox(height: 16),
          _RaceHeroArtwork(
            equippedAccessories: widget.equippedAccessories,
            equippedAnimal: widget.equippedAnimal,
          ),
          const SizedBox(height: 20),
          const _SectionTitle(label: 'HOW IT WORKS'),
          const SizedBox(height: 8),
          const _HowItWorks(),
          const SizedBox(height: 20),
          PillButton(
            key: const Key('contest-overview-join'),
            label: joinLabel,
            variant: PillButtonVariant.secondary,
            fontSize: 21,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            onPressed: canJoin ? widget.onJoin : null,
          ),
          const SizedBox(height: 20),
          const _HowToWin(),
          const SizedBox(height: 4),
          Semantics(
            link: true,
            label: 'Official Rules',
            child: TextButton(
              key: const Key('contest-overview-official-rules'),
              onPressed: widget.onRules,
              style: TextButton.styleFrom(
                foregroundColor: colors.pillGold,
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(
                'Official Rules',
                style: PixelText.body(
                  size: 17,
                  color: colors.pillGold,
                ).copyWith(decoration: TextDecoration.underline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrizeCard extends StatelessWidget {
  const _PrizeCard({required this.contest});

  final GiveawayContest contest;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      key: const Key('contest-overview-prize-card'),
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: referralContestPanelDecoration(context),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Transform.scale(
              scale: 1.35,
              child: Image.asset(
                'assets/images/referral/pixel_trophy.png',
                width: 48,
                height: 48,
                filterQuality: FilterQuality.none,
                excludeFromSemantics: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 58),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    '${formatReferralContestCoins(contest.prize.coins)} COINS',
                    style: PixelText.title(
                      size: 19.5,
                      color: colors.pillGoldDark,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    formatReferralContestTimeLeft(contest),
                    style: PixelText.title(size: 19.5, color: colors.textDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RaceHeroArtwork extends StatelessWidget {
  const _RaceHeroArtwork({
    required this.equippedAccessories,
    required this.equippedAnimal,
  });

  final List<Map<String, dynamic>> equippedAccessories;
  final String? equippedAnimal;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2.25,
      child: Container(
        key: const Key('contest-overview-race-hero'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: AppColors.of(context).roofDark.withValues(alpha: .72),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0xB0183021),
              offset: Offset(0, 6),
              blurRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: HomeHeroScene(
            groundHeight: 50,
            groundScrollSpeed: 24,
            excludeBackgroundSemantics: true,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 50 - 115 * .22,
                  child: Center(
                    child: Semantics(
                      label: 'Your animated Bara',
                      image: true,
                      child: AnimatedCapybaraWithAccessories(
                        accessories: equippedAccessories,
                        animal: equippedAnimal,
                        size: 115,
                        stepDuration: const Duration(milliseconds: 480),
                        animate: !MediaQuery.disableAnimationsOf(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('✦', style: TextStyle(color: colors.pillGold, fontSize: 14)),
        const SizedBox(width: 10),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: PixelText.title(size: 16, color: colors.textLight),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('✦', style: TextStyle(color: colors.pillGold, fontSize: 14)),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: SingleChildScrollView(
        key: const PageStorageKey('contest-how-it-works-carousel'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final step in _steps)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width * .42,
                  child: _StepCard(step: step),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _StepIcon { invite, friend, race, win }

typedef _ContestStep = ({int number, _StepIcon type, String label});

const _steps = <_ContestStep>[
  (number: 1, type: _StepIcon.invite, label: 'SHARE YOUR\nINVITE'),
  (number: 2, type: _StepIcon.friend, label: 'FRIEND\nSIGNS UP'),
  (
    number: 3,
    type: _StepIcon.race,
    label: 'FRIEND FINISHES\nA QUALIFYING\nRACE',
  ),
  (number: 4, type: _StepIcon.win, label: 'MOST VERIFIED\nREFERRALS\nWINS'),
];

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step});

  final _ContestStep step;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      height: 90,
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
      decoration: referralContestPanelDecoration(context),
      child: Stack(
        children: [
          Positioned(
            left: 1,
            top: 1,
            child: Text(
              '${step.number}',
              style: PixelText.title(size: 11, color: colors.grassDark),
            ),
          ),
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(child: _stepIcon()),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: Text(
                      step.label,
                      maxLines: 3,
                      textAlign: TextAlign.center,
                      style: PixelText.title(
                        size: 8.8,
                        color: colors.textDark,
                      ).copyWith(height: .94),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepIcon() => switch (step.type) {
    _StepIcon.invite => Image.asset(
      'assets/images/referral/how_it_works_invite.png',
      width: 36,
      height: 36,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
    ),
    _StepIcon.friend => const CapybaraSpriteWithAccessories(
      accessories: [],
      capybaraSize: 40,
      frameIndex: 0,
    ),
    _StepIcon.race => Image.asset(
      'assets/images/referral/checkered_finish_flag.png',
      width: 36,
      height: 36,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
    ),
    _StepIcon.win => Transform.scale(
      scale: 1.35,
      child: Image.asset(
        'assets/images/referral/pixel_trophy.png',
        width: 36,
        height: 36,
        filterQuality: FilterQuality.none,
      ),
    ),
  };
}

class _HowToWin extends StatelessWidget {
  const _HowToWin();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      key: const Key('contest-overview-how-to-win'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: referralContestPanelDecoration(context),
      child: Row(
        children: [
          Image.asset(
            'assets/images/referral/pixel_star.png',
            width: 38,
            height: 38,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HOW TO WIN',
                  style: PixelText.title(size: 14, color: colors.grassDark),
                ),
                const SizedBox(height: 4),
                Text(
                  'The entrant with the most verified completed referrals wins. Ties go to whoever reached the final count first.',
                  style: PixelText.body(size: 13, color: colors.textDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
