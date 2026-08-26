import 'package:flutter/material.dart';

import '../models/race_payouts.dart';
import '../models/race_prize_pool.dart';
import '../styles.dart';
import 'spinning_coin.dart';

enum RacePayoutMode { none, even, graded, podium }

@immutable
class RacePayoutPresentation {
  const RacePayoutPresentation({
    required this.durationDays,
    required this.buyInAmount,
    required this.legacyPotCoins,
    required this.pool,
    required this.tiers,
    required this.mode,
    required this.payoutPreset,
    required this.acceptedCount,
    required this.viewerPlacement,
    required this.isTeamRace,
    required this.payoutAvailable,
  });

  factory RacePayoutPresentation.fromRace(
    Map<String, dynamic>? race, {
    int? viewerPlacement,
    bool isTeamRace = false,
  }) {
    int safeInt(Object? value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return value is String ? int.tryParse(value) ?? fallback : fallback;
    }

    final tiers = parsePayoutTiers(race);
    final preset = race?['payoutPreset'] is String
        ? race!['payoutPreset'] as String
        : null;
    final pool = RacePrizePool.fromRace(race);
    final hasLegacyPot =
        race?['projectedPotCoins'] is num ||
        (race?['projectedPotCoins'] is String &&
            int.tryParse(race?['projectedPotCoins'] as String) != null);
    final hasLegacyBuyIn =
        race?['buyInAmount'] is num ||
        (race?['buyInAmount'] is String &&
            int.tryParse(race?['buyInAmount'] as String) != null);
    // The details payload's `participants` may be a server-side PAGE
    // (race-details participants pagination), so counting it under-reports the
    // field and prints the wrong "of N" cut line. The additive `acceptedCount`
    // is the true total; fall back to the array scan only when it is absent
    // (older backend), which is exactly today's behaviour.
    final acceptedFromSummary = safeInt(race?['acceptedCount'], fallback: -1);
    final accepted = acceptedFromSummary >= 0
        ? acceptedFromSummary
        : race?['participants'] is List
        ? (race!['participants'] as List)
              .where((entry) => entry is Map && entry['status'] == 'ACCEPTED')
              .length
        : 0;
    final even =
        tiers.length >= 2 &&
        tiers.every((tier) => tier.amount == tiers.first.amount);
    final graded =
        tiers.length >= 2 &&
        const {'TOP_HALF', 'ALL_BUT_LAST'}.contains(preset) &&
        pool?.funded == true &&
        !even;
    return RacePayoutPresentation(
      durationDays: safeInt(race?['maxDurationDays'], fallback: 7),
      buyInAmount: safeInt(race?['buyInAmount']),
      legacyPotCoins: safeInt(race?['projectedPotCoins']),
      pool: pool,
      tiers: tiers,
      mode: tiers.isEmpty
          ? RacePayoutMode.none
          : even
          ? RacePayoutMode.even
          : graded
          ? RacePayoutMode.graded
          : RacePayoutMode.podium,
      payoutPreset: preset,
      acceptedCount: accepted,
      viewerPlacement: viewerPlacement,
      isTeamRace: isTeamRace,
      payoutAvailable:
          pool != null || hasLegacyPot || hasLegacyBuyIn || tiers.isNotEmpty,
    );
  }

  final int durationDays;
  final int buyInAmount;
  final int legacyPotCoins;
  final RacePrizePool? pool;
  final List<PayoutTier> tiers;
  final RacePayoutMode mode;
  final String? payoutPreset;
  final int acceptedCount;
  final int? viewerPlacement;
  final bool isTeamRace;
  final bool payoutAvailable;

  bool get hasFundedPool => pool != null && (pool!.funded || pool!.coins > 0);
  bool get hasPrize => hasFundedPool || buyInAmount > 0;
  int get prizeCoins => pool?.coins ?? legacyPotCoins;
  int get paidPlaces => tiers.length;
  int? get viewerAmount {
    final placement = viewerPlacement;
    if (placement == null) return null;
    for (final tier in tiers) {
      if (tier.placement == placement) return tier.amount;
    }
    return null;
  }

  String get statusTag => pool?.atMax == true
      ? 'MAX'
      : pool?.projected == true
      ? 'PROJECTED'
      : '';
  String get paidCutValue => acceptedCount > 0
      ? '$paidPlaces OF $acceptedCount'
      : '$paidPlaces PLACES';
  String get secondaryLabel => switch (mode) {
    RacePayoutMode.even => 'EACH PAID',
    RacePayoutMode.graded => '1ST PLACE',
    RacePayoutMode.podium => tiers.length == 1 ? 'WINNER' : '1ST PLACE',
    RacePayoutMode.none => '',
  };
  String get secondaryValue =>
      tiers.isEmpty ? '' : formatPrizeCoins(tiers.first.amount);

  String? get viewerLine {
    final placement = viewerPlacement;
    if (placement == null || tiers.isEmpty) return null;
    final amount = viewerAmount;
    if (amount != null) {
      return 'YOU: ${payoutPlacementLabel(placement)} · ${formatPrizeCoins(amount)} PROJECTED';
    }
    return 'YOU: ${payoutPlacementLabel(placement)} · OUTSIDE CUT';
  }

  String? get viewerSentence {
    final placement = viewerPlacement;
    if (placement == null || tiers.isEmpty) return null;
    final amount = viewerAmount;
    final ordinal = payoutPlacementLabel(placement).toLowerCase();
    if (amount != null) {
      return mode == RacePayoutMode.graded
          ? 'You’re $ordinal. ${formatPrizeCoins(amount)} coins projected'
          : 'You’re $ordinal. In the money';
    }
    final distance = placement - paidPlaces;
    return 'You’re $ordinal. $distance ${distance == 1 ? 'place' : 'places'} from the cut';
  }

  String get modeHeadline => switch (mode) {
    RacePayoutMode.even =>
      payoutPreset == 'ALL_BUT_LAST'
          ? 'Everyone but last splits the pool evenly'
          : payoutPreset == 'TOP_HALF'
          ? 'Top half splits the pool evenly'
          : 'The top $paidPlaces split the pool evenly',
    RacePayoutMode.graded =>
      payoutPreset == 'ALL_BUT_LAST'
          ? 'Everyone but last wins. Bigger prizes up top'
          : payoutPreset == 'TOP_HALF'
          ? 'Top half wins. Bigger prizes up top'
          : 'The top $paidPlaces win. Bigger prizes up top',
    RacePayoutMode.podium => 'Podium payouts',
    RacePayoutMode.none => '',
  };

  String? get callout {
    if (isTeamRace) return 'The winning team splits the whole pool evenly.';
    if (pool?.atMax == true) return 'This pool has reached its maximum.';
    if (pool?.projected == true) {
      return 'Projected payouts settle from runners who actually walked.';
    }
    return null;
  }
}

class RacePayoutScorecard extends StatelessWidget {
  const RacePayoutScorecard({
    super.key,
    required this.presentation,
    required this.onOpenPayouts,
  });

  final RacePayoutPresentation presentation;
  final VoidCallback? onOpenPayouts;

  @override
  Widget build(BuildContext context) {
    final p = presentation;
    final colors = AppColors.of(context);
    return Column(
      key: p.mode == RacePayoutMode.even
          ? const Key('race-payout-summary')
          : p.mode == RacePayoutMode.graded
          ? const Key('race-graded-payout-summary')
          : const Key('race-payout-scorecard'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _Metric(
                label: 'DURATION',
                value:
                    '${p.durationDays} ${p.durationDays == 1 ? 'DAY' : 'DAYS'}',
              ),
            ),
            if (p.hasFundedPool)
              Expanded(
                child: _Metric(
                  key: const Key('race-info-prize-pool'),
                  label: 'PRIZE POOL',
                  value: formatPrizeCoins(p.prizeCoins),
                  valueColor: colors.coinDark,
                  tag: p.statusTag,
                ),
              )
            else if (p.pool != null)
              Expanded(
                child: _Metric(
                  key: const Key('race-info-prize-pool'),
                  label: 'PRIZE POOL',
                  value: formatPrizeCoins(p.prizeCoins),
                  valueColor: colors.coinDark,
                  tag: p.statusTag,
                ),
              )
            else if (p.buyInAmount > 0) ...[
              Expanded(
                child: _Metric(
                  label: 'BUY-IN',
                  value: formatPrizeCoins(p.buyInAmount),
                  valueColor: colors.coinDark,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'POT',
                  value: formatPrizeCoins(p.legacyPotCoins),
                  valueColor: colors.coinDark,
                ),
              ),
            ] else if (p.payoutAvailable)
              Expanded(
                child: _Metric(
                  key: const Key('race-info-legacy-payout'),
                  label: 'PRIZE POOL',
                  value: formatPrizeCoins(p.legacyPotCoins),
                  valueColor: colors.coinDark,
                ),
              )
            else
              const Expanded(
                child: _Metric(
                  key: Key('race-payout-unavailable'),
                  label: 'PAYOUT',
                  value: 'UNAVAILABLE',
                ),
              ),
            if (p.hasPrize) ...[
              SizedBox(
                height: 38,
                child: VerticalDivider(
                  width: 10,
                  thickness: 1,
                  color: colors.parchmentBorder,
                ),
              ),
              Semantics(
                button: true,
                label: 'Open payout details',
                child: InkWell(
                  key: const Key('race-payouts-open'),
                  onTap: onOpenPayouts,
                  borderRadius: BorderRadius.circular(6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 64,
                      minHeight: 44,
                    ),
                    child: Center(
                      child: Text(
                        'PAYOUTS ›',
                        maxLines: 1,
                        style: PixelText.title(
                          size: 9.5,
                          color: colors.textMid,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (p.hasPrize && p.tiers.isNotEmpty && !p.isTeamRace) ...[
          const SizedBox(height: 10),
          Divider(height: 1, color: colors.parchmentBorder),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'TOP CUT PAID',
                  value: p.paidCutValue,
                  compact: true,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: p.secondaryLabel,
                  value: p.secondaryValue,
                  compact: true,
                  valueColor: colors.coinDark,
                ),
              ),
            ],
          ),
          if (p.viewerLine != null) ...[
            const SizedBox(height: 5),
            Text(
              p.viewerLine!,
              key: const Key('race-payout-viewer-status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: PixelText.title(size: 10, color: colors.coinDark),
            ),
          ],
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.tag = '',
    this.compact = false,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final String tag;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              maxLines: 1,
              style: PixelText.body(
                size: compact ? 9.5 : 10.5,
                color: AppColors.of(context).textMid,
              ),
            ),
            if (tag.isNotEmpty) ...[
              const SizedBox(width: 4),
              Container(
                key: tag == 'PROJECTED'
                    ? const Key('race-prize-pool-projected')
                    : const Key('race-prize-pool-max'),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.of(context).coinDark,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  tag,
                  style: PixelText.title(size: 7, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        textAlign: TextAlign.center,
        style: PixelText.title(
          size: compact ? 15 : 17,
          color: valueColor ?? AppColors.of(context).textDark,
        ),
      ),
    ],
  );
}

class RacePrizePoolSheet extends StatelessWidget {
  const RacePrizePoolSheet({super.key, required this.presentation});
  final RacePayoutPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final p = presentation;
    final colors = AppColors.of(context);
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.84,
        child: Container(
          key: const Key('race-prize-pool-sheet'),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          decoration: BoxDecoration(
            color: colors.parchmentLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.woodMid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'PRIZE POOL',
                      style: PixelText.title(size: 17, color: colors.textDark),
                    ),
                  ),
                  if (p.statusTag.isNotEmpty)
                    Container(
                      key: p.statusTag == 'PROJECTED'
                          ? const Key('race-prize-pool-sheet-projected')
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.coinDark,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p.statusTag,
                        style: PixelText.title(size: 8, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                key: const Key('race-prize-pool-hero-band'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.parchment,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.coinDark, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SpinningCoin(size: 28),
                    const SizedBox(width: 10),
                    Text(
                      formatPrizeCoins(p.prizeCoins),
                      style: PixelText.number(size: 34, color: colors.coinDark),
                    ),
                  ],
                ),
              ),
              if (p.callout != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: p.isTeamRace
                      ? const Key('race-prize-pool-team-split')
                      : const Key('race-prize-pool-rule-callout'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.parchmentDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    p.callout!,
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 12, color: colors.textMid),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'PAYOUTS',
                style: PixelText.title(size: 14, color: colors.textDark),
              ),
              const SizedBox(height: 7),
              if (!p.isTeamRace && p.tiers.isNotEmpty) ...[
                _summary(context),
                const SizedBox(height: 9),
              ],
              Expanded(child: _tierBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tierBody(BuildContext context) {
    final p = presentation;
    final colors = AppColors.of(context);
    if (p.isTeamRace) {
      return Center(
        child: Text(
          'Paid evenly to the winning team’s eligible runners.',
          textAlign: TextAlign.center,
          style: PixelText.body(size: 13, color: colors.textMid),
        ),
      );
    }
    if (p.tiers.isEmpty) {
      return Center(
        child: Text(
          'Payout details are not available yet.',
          style: PixelText.body(size: 13, color: colors.textMid),
        ),
      );
    }
    return ListView.separated(
      key: const Key('race-prize-pool-tier-list'),
      padding: const EdgeInsets.only(bottom: 22),
      itemCount: p.tiers.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: colors.parchmentBorder.withValues(alpha: 0.55),
      ),
      itemBuilder: (_, index) {
        final tier = p.tiers[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  payoutPlacementLabel(tier.placement),
                  style: PixelText.title(size: 12, color: colors.textMid),
                ),
              ),
              const SpinningCoin(size: 14),
              const SizedBox(width: 6),
              Text(
                formatPrizeCoins(tier.amount),
                style: PixelText.title(size: 14, color: colors.coinDark),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summary(BuildContext context) {
    final p = presentation;
    final colors = AppColors.of(context);
    return Container(
      key: p.mode == RacePayoutMode.even
          ? const Key('race-prize-pool-payout-summary')
          : p.mode == RacePayoutMode.graded
          ? const Key('race-prize-pool-graded-payout-summary')
          : const Key('race-prize-pool-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.parchment,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.parchmentBorder),
      ),
      child: Column(
        children: [
          Text(
            p.modeHeadline,
            textAlign: TextAlign.center,
            style: PixelText.body(size: 12, color: colors.textMid),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                p.mode == RacePayoutMode.even
                    ? '~${p.secondaryValue}'
                    : p.secondaryValue,
                style: PixelText.title(size: 14, color: colors.coinDark),
              ),
              const SizedBox(width: 5),
              Text(
                p.mode == RacePayoutMode.even ? 'coins each' : 'coins for 1st',
                style: PixelText.body(size: 11.5, color: colors.textMid),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            p.acceptedCount > 0
                ? 'Top ${p.paidPlaces} of ${p.acceptedCount} get paid'
                : 'Top ${p.paidPlaces} get paid',
            style: PixelText.body(size: 11.5, color: colors.textMid),
          ),
          if (p.mode == RacePayoutMode.graded) ...[
            const SizedBox(height: 3),
            Text(
              'Projected. Final payouts settle on who walked.',
              style: PixelText.body(size: 11, color: colors.textMid),
            ),
          ],
          if (p.viewerSentence != null) ...[
            const SizedBox(height: 5),
            Text(
              p.viewerSentence!,
              style: PixelText.body(size: 11.5, color: colors.coinDark),
            ),
          ],
        ],
      ),
    );
  }
}
