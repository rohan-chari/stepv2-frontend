import 'dart:async';

import 'package:flutter/material.dart';

import '../models/giveaway.dart';
import '../styles.dart';
import 'app_avatar.dart';
import 'app_refresh_indicator.dart';
import 'loading_skeleton.dart';
import 'pill_button.dart';
import 'referral_contest_chrome.dart';

/// The post-entry referral contest control center.
///
/// Data loading, sharing, copying, leaderboard state, and navigation stay with
/// [GiveawayScreen]. This widget owns only the joined presentation so those
/// established behaviors cannot drift from the rest of the contest flow.
class ReferralContestJoinedDashboard extends StatelessWidget {
  const ReferralContestJoinedDashboard({
    super.key,
    required this.data,
    required this.shareEnabled,
    required this.leadersOpen,
    required this.onRefresh,
    required this.onShare,
    required this.onCopyCode,
    required this.onCopyUrl,
    required this.onToggleLeaderboard,
    required this.onRules,
    required this.leaderboard,
    this.statusNotice,
  });

  final GiveawayCurrent data;
  final bool shareEnabled;
  final bool leadersOpen;
  final Future<void> Function() onRefresh;
  final VoidCallback? onShare;
  final VoidCallback? onCopyCode;
  final VoidCallback? onCopyUrl;
  final VoidCallback onToggleLeaderboard;
  final VoidCallback onRules;
  final Widget leaderboard;
  final Widget? statusNotice;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final notice = statusNotice;
    return AppRefreshIndicator(
      key: const Key('contest-trail-scene'),
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        key: const Key('giveaway-content-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ContestSummary(data: data),
            if (notice != null) ...[const SizedBox(height: 15), notice],
            const SizedBox(height: 14),
            _InviteCard(
              share: shareEnabled ? data.share : null,
              prizeCoins: data.contest.prize.coins,
              enabled: shareEnabled,
              onShare: onShare,
              onCopyCode: onCopyCode,
              onCopyUrl: onCopyUrl,
            ),
            const SizedBox(height: 16),
            const _SectionTitle(label: 'YOUR STANDING'),
            const SizedBox(height: 11),
            KeyedSubtree(
              key: const Key('contest-trail-hud'),
              child: _StandingCard(data: data),
            ),
            const SizedBox(height: 16),
            _LeaderboardPreview(
              data: data,
              open: leadersOpen,
              onToggle: onToggleLeaderboard,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: leadersOpen
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: leaderboard,
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 14),
            _RecentReferralsCard(
              items: data.recentReferrals.take(3).toList(growable: false),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('contest-dashboard-official-rules'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.of(context).textAccent,
                backgroundColor: AppColors.of(context).parchmentLight,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                  side: BorderSide(
                    color: AppColors.of(context).feedGold.withValues(alpha: .5),
                  ),
                ),
              ),
              onPressed: onRules,
              icon: const Icon(Icons.menu_book_rounded, size: 18),
              label: Text('OFFICIAL RULES', style: PixelText.title(size: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

class ReferralContestJoinedDashboardSkeleton extends StatelessWidget {
  const ReferralContestJoinedDashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SingleChildScrollView(
      key: const Key('contest-dashboard-skeleton'),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 24),
      child: LoadingSkeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SkeletonPanel(
              height: 92,
              child: Row(
                children: [
                  const SkeletonBox(width: 48, height: 48, radius: 8),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonLine(width: 145, height: 18),
                        SizedBox(height: 9),
                        SkeletonLine(width: 100, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: SkeletonBox(
                width: 185,
                height: 18,
                color: colors.parchment.withValues(alpha: .42),
              ),
            ),
            const SizedBox(height: 11),
            const _SkeletonPanel(height: 156),
            const SizedBox(height: 16),
            const _SkeletonPanel(height: 206),
            const SizedBox(height: 16),
            const _SkeletonPanel(height: 112),
            const SizedBox(height: 16),
            const _SkeletonPanel(height: 152),
          ],
        ),
      ),
    );
  }
}

class _ContestSummary extends StatefulWidget {
  const _ContestSummary({required this.data});

  final GiveawayCurrent data;

  @override
  State<_ContestSummary> createState() => _ContestSummaryState();
}

class _ContestSummaryState extends State<_ContestSummary> {
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
    final data = widget.data;
    final contestLabel = data.contest.title.trim().toUpperCase();
    final summaryLabel =
        contestLabel == 'BARA REFERRAL CONTEST' ||
            contestLabel == 'REFERRAL CONTEST'
        ? 'YOU’RE IN'
        : contestLabel;
    return Container(
      key: const Key('contest-dashboard-summary'),
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: referralContestPanelDecoration(context),
      child: Row(
        children: [
          Image.asset(
            'assets/images/referral/pixel_trophy.png',
            width: 50,
            height: 50,
            filterQuality: FilterQuality.none,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summaryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PixelText.title(size: 10, color: colors.textMid),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${formatReferralContestCoins(data.contest.prize.coins)} COINS',
                    style: PixelText.title(size: 23, color: colors.feedGold),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_shortContestDate(data.contest.startsAt)} · ${formatReferralContestTimeLeft(data.contest)}',
                  style: PixelText.body(
                    size: 14,
                    color: colors.textDark,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusBadge(data: data),
        ],
      ),
    );
  }

  static String _shortContestDate(DateTime date) {
    const months = <String>[
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.data});

  final GiveawayCurrent data;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final entry = data.entry?.status;
    final (label, active) = switch ((data.contest.status, entry)) {
      (GiveawayStatus.active, GiveawayEntryStatus.eligible) => ('JOINED', true),
      (GiveawayStatus.active, GiveawayEntryStatus.underReview) => (
        'REVIEW',
        false,
      ),
      (GiveawayStatus.verifying, _) => ('CHECKING', false),
      (GiveawayStatus.finalResult, _) => ('FINAL', false),
      (GiveawayStatus.scheduled, _) => ('SOON', false),
      _ => ('ENTRY', false),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? colors.pillGreen.withValues(alpha: .16)
            : colors.pillGold.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: PixelText.title(
          size: 10.5,
          color: active ? colors.textAccent : colors.textMid,
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
        Text('✦', style: TextStyle(color: colors.pillGold, fontSize: 13)),
        const SizedBox(width: 9),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: PixelText.title(size: 16, color: colors.textLight),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text('✦', style: TextStyle(color: colors.pillGold, fontSize: 13)),
      ],
    );
  }
}

class _StandingCard extends StatelessWidget {
  const _StandingCard({required this.data});

  final GiveawayCurrent data;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final standing = data.standing;
    final rank = standing?.provisionalRank;
    final verified = standing?.verifiedCount ?? 0;
    final pending = standing?.reviewableCount ?? 0;
    final percentile = standing?.percentile;
    final targetRank = standing?.nextTargetRank;
    final referralsBehind = standing?.referralsBehindNextTarget;
    final chaseEnabled =
        data.contest.status == GiveawayStatus.active &&
        (data.entry?.status == GiveawayEntryStatus.eligible ||
            data.entry?.status == GiveawayEntryStatus.underReview);
    final chaseCopy = !chaseEnabled
        ? null
        : rank == null
        ? 'Complete a qualifying referral to enter the leaderboard.'
        : rank == 1
        ? 'You’re leading the pack.'
        : targetRank != null && referralsBehind != null
        ? '$referralsBehind more verified ${referralsBehind == 1 ? 'referral' : 'referrals'} to reach #$targetRank.'
        : 'Share your invite to climb the leaderboard.';
    final semantics = <String>[
      rank == null ? 'Rank unavailable' : 'Rank $rank',
      '$verified qualified referrals',
      '$pending referrals pending review',
      if (percentile != null) 'Top $percentile percent',
      ?chaseCopy,
    ].join('. ');
    return Semantics(
      key: const Key('contest-dashboard-standing'),
      container: true,
      label: semantics,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: referralContestPanelDecoration(context),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StandingMetric(
                      asset: 'assets/images/referral/rules_ranking_review.png',
                      label: 'CURRENT RANK',
                      value: rank == null ? '—' : '#$rank',
                    ),
                  ),
                  Container(
                    width: 1.5,
                    height: 58,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: colors.feedGold.withValues(alpha: .72),
                  ),
                  Expanded(
                    child: _StandingMetric(
                      asset: 'assets/images/referral/checkered_finish_flag.png',
                      label: 'QUALIFIED REFERRALS',
                      value: '$verified',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: colors.feedGold.withValues(alpha: .35),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 14,
                      runSpacing: 5,
                      children: [
                        _ContextLabel(label: '$verified VERIFIED'),
                        if (percentile != null)
                          _ContextLabel(label: 'TOP $percentile%'),
                        _ContextLabel(label: '$pending PENDING REVIEW'),
                      ],
                    ),
                    if (chaseCopy != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        chaseCopy,
                        textAlign: TextAlign.center,
                        style: PixelText.body(
                          size: 12,
                          color: colors.textDark,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StandingMetric extends StatelessWidget {
  const _StandingMetric({
    required this.asset,
    required this.label,
    required this.value,
  });

  final String asset;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              asset,
              width: 23,
              height: 23,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: PixelText.title(size: 9.5, color: colors.textMid),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: PixelText.title(size: 36, color: colors.textAccent),
          ),
        ),
      ],
    );
  }
}

class _ContextLabel extends StatelessWidget {
  const _ContextLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: PixelText.title(size: 10.5, color: AppColors.of(context).textAccent),
  );
}

class _LeaderboardPreview extends StatelessWidget {
  const _LeaderboardPreview({
    required this.data,
    required this.open,
    required this.onToggle,
  });

  final GiveawayCurrent data;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final viewerRank = data.standing?.provisionalRank;
    final uniqueViewerRank =
        viewerRank != null &&
        data.leaderboard.where((row) => row.rank == viewerRank).length == 1;
    final top = data.leaderboard.take(3).toList(growable: false);
    final viewerInTop =
        uniqueViewerRank && top.any((row) => row.rank == viewerRank);
    final viewerName = data.entry?.displayName;
    final previewRows =
        <({int rank, String displayName, int count, bool isViewer})>[
          for (final row in top)
            (
              rank: row.rank,
              displayName: row.displayName,
              count: row.completedCount,
              isViewer: viewerInTop && row.rank == viewerRank,
            ),
          if (!viewerInTop && viewerRank != null && viewerName != null)
            (
              rank: viewerRank,
              displayName: viewerName,
              count: data.standing?.verifiedCount ?? 0,
              isViewer: true,
            ),
        ];
    return Container(
      key: const Key('contest-dashboard-leaderboard-preview'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: referralContestPanelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'LEADERBOARD PREVIEW',
                  style: PixelText.title(size: 13, color: colors.textAccent),
                ),
              ),
              Semantics(
                button: true,
                expanded: open,
                label: open
                    ? 'Hide full contest leaderboard'
                    : 'View full contest leaderboard',
                child: TextButton(
                  key: const Key('contest-dashboard-view-leaderboard'),
                  onPressed: onToggle,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textAccent,
                    minimumSize: const Size(88, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        open ? 'HIDE FULL' : 'VIEW FULL',
                        style: PixelText.title(
                          size: 10.5,
                          color: colors.textAccent,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        open ? Icons.expand_less : Icons.chevron_right,
                        size: 19,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (previewRows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
              child: Text(
                'No verified referrals yet. Be the first on the board.',
                textAlign: TextAlign.center,
                style: PixelText.body(size: 12.5, color: colors.textMid),
              ),
            )
          else
            for (var index = 0; index < previewRows.length; index++) ...[
              if (index > 0 && !(previewRows[index].isViewer && !viewerInTop))
                Container(
                  height: 1,
                  color: colors.pillGold.withValues(alpha: .32),
                ),
              if (index > 0 && previewRows[index].isViewer && !viewerInTop)
                const _PreviewEllipsis(),
              _PreviewRow(row: previewRows[index]),
            ],
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.row});

  final ({int rank, String displayName, int count, bool isViewer}) row;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final badgeColor = switch (row.rank) {
      1 => colors.medalGold,
      2 => colors.medalSilver,
      3 => colors.medalBronze,
      _ => colors.roofLight.withValues(alpha: .15),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      margin: row.isViewer ? const EdgeInsets.symmetric(vertical: 3) : null,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        color: row.isViewer
            ? colors.pillGold.withValues(alpha: .18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: row.isViewer
            ? Border.all(
                color: colors.feedGold.withValues(alpha: .68),
                width: 1.25,
              )
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
              border: Border.all(color: colors.roofDark.withValues(alpha: .35)),
            ),
            child: Text(
              '${row.rank}',
              style: PixelText.title(size: 10, color: colors.textDark),
            ),
          ),
          const SizedBox(width: 8),
          AppAvatar(
            name: row.displayName,
            size: 34,
            borderColor: colors.roofDark.withValues(alpha: .25),
            borderWidth: 1.25,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    row.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.body(
                      size: 13.5,
                      color: colors.textDark,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (row.isViewer) ...[
                  const SizedBox(width: 6),
                  Text(
                    'YOU',
                    style: PixelText.title(size: 8.5, color: colors.feedGold),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${row.count}',
                style: PixelText.title(size: 16, color: colors.textAccent),
              ),
              Text(
                'VERIFIED',
                style: PixelText.body(
                  size: 7.5,
                  color: colors.textMid,
                ).copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewEllipsis extends StatelessWidget {
  const _PreviewEllipsis();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: Center(
      child: Text(
        '•••',
        style: PixelText.title(size: 11, color: AppColors.of(context).feedGold),
      ),
    ),
  );
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.share,
    required this.prizeCoins,
    required this.enabled,
    required this.onShare,
    required this.onCopyCode,
    required this.onCopyUrl,
  });

  final GiveawayShare? share;
  final int prizeCoins;
  final bool enabled;
  final VoidCallback? onShare;
  final VoidCallback? onCopyCode;
  final VoidCallback? onCopyUrl;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final invite = share;
    return Container(
      key: const Key('contest-dashboard-invite-card'),
      padding: const EdgeInsets.all(12),
      decoration: referralContestPanelDecoration(context),
      child: invite == null
          ? _MissingInvite(colors: colors)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InviteDetails(
                  invite: invite,
                  enabled: enabled,
                  onCopyCode: onCopyCode,
                  onCopyUrl: onCopyUrl,
                ),
                if (enabled) ...[
                  const SizedBox(height: 11),
                  _ShareIdeas(prizeCoins: prizeCoins),
                ],
                const SizedBox(height: 10),
                KeyedSubtree(
                  key: const Key('contest-trail-share'),
                  child: Semantics(
                    button: enabled,
                    label: 'Share your referral contest invite',
                    child: PillButton(
                      key: const Key('contest-dashboard-share'),
                      label: enabled ? 'SHARE YOUR INVITE' : 'SHARING CLOSED',
                      icon: enabled ? Icons.ios_share_rounded : null,
                      variant: PillButtonVariant.secondary,
                      fontSize: 16,
                      fullWidth: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      onPressed: enabled ? onShare : null,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ShareIdeas extends StatelessWidget {
  const _ShareIdeas({required this.prizeCoins});

  final int prizeCoins;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final prize = formatReferralContestCoins(prizeCoins);
    return Semantics(
      key: const Key('contest-dashboard-share-ideas'),
      container: true,
      label:
          'Make some noise. Drop your invite in the group chat or post it on Instagram. One share could win you $prize coins.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          decoration: BoxDecoration(
            color: colors.grassDark.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: colors.feedGold.withValues(alpha: .42)),
          ),
          child: Column(
            children: [
              Text(
                'MAKE SOME NOISE',
                style: PixelText.title(size: 11, color: colors.textAccent),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ShareIdea(
                      icon: Icons.forum_rounded,
                      label: 'DROP IT IN THE GROUP CHAT',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ShareIdea(
                      icon: Icons.camera_alt_rounded,
                      label: 'POST IT ON INSTAGRAM',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                'ONE SHARE COULD WIN YOU $prize COINS',
                maxLines: 2,
                textAlign: TextAlign.center,
                style: PixelText.title(size: 11, color: colors.textAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareIdea extends StatelessWidget {
  const _ShareIdea({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 38),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: colors.parchmentLight,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.textAccent),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              maxLines: 3,
              style: PixelText.title(size: 8.5, color: colors.textAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteDetails extends StatelessWidget {
  const _InviteDetails({
    required this.invite,
    required this.enabled,
    required this.onCopyCode,
    required this.onCopyUrl,
  });

  final GiveawayShare invite;
  final bool enabled;
  final VoidCallback? onCopyCode;
  final VoidCallback? onCopyUrl;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset(
              'assets/images/referral/how_it_works_invite.png',
              width: 31,
              height: 31,
              filterQuality: FilterQuality.none,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR INVITE',
                    style: PixelText.title(
                      size: 10.5,
                      color: colors.textAccent,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      invite.code,
                      maxLines: 1,
                      style: PixelText.title(size: 23, color: colors.textDark),
                    ),
                  ),
                ],
              ),
            ),
            _CompactCopyButton(
              key: const Key('contest-dashboard-copy-code'),
              tooltip: 'Copy invite code',
              onPressed: enabled ? onCopyCode : null,
            ),
          ],
        ),
        Semantics(
          button: enabled,
          label: 'Copy invite link ${invite.url}',
          child: InkWell(
            key: const Key('contest-dashboard-copy-url'),
            onTap: enabled ? onCopyUrl : null,
            borderRadius: BorderRadius.circular(7),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.only(left: 8, right: 4),
              decoration: BoxDecoration(
                color: colors.parchmentLight,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: colors.roofDark.withValues(alpha: .25),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      invite.url.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.body(size: 11, color: colors.textMid),
                    ),
                  ),
                  Icon(Icons.copy_rounded, size: 17, color: colors.textAccent),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactCopyButton extends StatelessWidget {
  const _CompactCopyButton({super.key, required this.tooltip, this.onPressed});

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    padding: EdgeInsets.zero,
    onPressed: onPressed,
    icon: Icon(
      Icons.copy_rounded,
      size: 18,
      color: AppColors.of(context).textAccent,
    ),
  );
}

class _MissingInvite extends StatelessWidget {
  const _MissingInvite({required this.colors});

  final AppPalette colors;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Image.asset(
        'assets/images/referral/how_it_works_invite.png',
        width: 42,
        height: 42,
        filterQuality: FilterQuality.none,
        excludeFromSemantics: true,
      ),
      const SizedBox(height: 8),
      Text(
        'INVITE UNAVAILABLE',
        style: PixelText.title(size: 14, color: colors.textDark),
      ),
      const SizedBox(height: 5),
      Text(
        'Pull down to refresh your contest invite.',
        textAlign: TextAlign.center,
        style: PixelText.body(size: 13, color: colors.textMid),
      ),
    ],
  );
}

class _RecentReferralsCard extends StatelessWidget {
  const _RecentReferralsCard({required this.items});

  final List<GiveawayRecentReferral> items;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      key: const Key('contest-dashboard-recent-card'),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      decoration: referralContestPanelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'RECENT REFERRALS',
            style: PixelText.title(size: 13, color: colors.textAccent),
          ),
          const SizedBox(height: 5),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/referral/how_it_works_invite.png',
                    width: 32,
                    height: 32,
                    filterQuality: FilterQuality.none,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NO REFERRALS YET',
                          style: PixelText.title(
                            size: 11,
                            color: colors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Share your invite to get started.',
                          style: PixelText.body(
                            size: 11.5,
                            color: colors.textMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                Container(
                  height: 1,
                  color: colors.pillGold.withValues(alpha: .35),
                ),
              _RecentReferralRow(item: items[index]),
            ],
        ],
      ),
    );
  }
}

class _RecentReferralRow extends StatelessWidget {
  const _RecentReferralRow({required this.item});

  final GiveawayRecentReferral item;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      label:
          '${item.displayName}, ${_statusLabel(item.status)}, ${_relativeTime(item.occurredAt)}',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 49),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              AppAvatar(
                name: item.displayName,
                size: 31,
                borderColor: colors.roofDark.withValues(alpha: .35),
                borderWidth: 1.5,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.body(
                        size: 12.5,
                        color: colors.textDark,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _relativeTime(item.occurredAt),
                      style: PixelText.body(size: 10.5, color: colors.textMid),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ReferralStatusBadge(status: item.status),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferralStatusBadge extends StatelessWidget {
  const _ReferralStatusBadge({required this.status});

  final GiveawayRecentReferralStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final face = switch (status) {
      GiveawayRecentReferralStatus.qualified => colors.pillGreen.withValues(
        alpha: .22,
      ),
      GiveawayRecentReferralStatus.inRace ||
      GiveawayRecentReferralStatus.underReview => colors.pillGold.withValues(
        alpha: .36,
      ),
      GiveawayRecentReferralStatus.notCounted => colors.errorLight.withValues(
        alpha: .34,
      ),
      GiveawayRecentReferralStatus.signedUp => colors.roofLight.withValues(
        alpha: .14,
      ),
    };
    final textColor = status == GiveawayRecentReferralStatus.notCounted
        ? colors.error
        : colors.textAccent;
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: face,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _statusLabel(status),
        textAlign: TextAlign.center,
        style: PixelText.title(size: 8.5, color: textColor),
      ),
    );
  }
}

class _SkeletonPanel extends StatelessWidget {
  const _SkeletonPanel({required this.height, this.child});

  final double height;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.all(14),
    decoration: referralContestPanelDecoration(context),
    child: child,
  );
}

String _statusLabel(GiveawayRecentReferralStatus status) => switch (status) {
  GiveawayRecentReferralStatus.signedUp => 'SIGNED UP',
  GiveawayRecentReferralStatus.inRace => 'IN RACE',
  GiveawayRecentReferralStatus.underReview => 'REVIEW',
  GiveawayRecentReferralStatus.qualified => 'QUALIFIED',
  GiveawayRecentReferralStatus.notCounted => 'NOT COUNTED',
};

String _relativeTime(DateTime occurredAt) {
  final delta = DateTime.now().toUtc().difference(occurredAt.toUtc());
  if (delta.isNegative || delta.inMinutes < 1) return 'Just now';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  final weeks = delta.inDays ~/ 7;
  return '${weeks.clamp(1, 99)}w ago';
}
