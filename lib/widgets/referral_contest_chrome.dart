import 'package:flutter/material.dart';

import '../models/giveaway.dart';
import '../styles.dart';

/// Shared card and formatting primitives for the referral-contest flow.
///
BoxDecoration referralContestPanelDecoration(BuildContext context) {
  final colors = AppColors.of(context);
  return BoxDecoration(
    color: colors.parchmentLight,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: colors.woodDark.withValues(alpha: .28), width: 1),
  );
}

String formatReferralContestCoins(int value) => value
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

String formatReferralContestTimeLeft(GiveawayContest contest) {
  if (contest.status == GiveawayStatus.finalResult ||
      contest.status == GiveawayStatus.verifying) {
    return 'ENDED';
  }
  final delta = contest.endsAt.difference(DateTime.now().toUtc());
  if (delta <= Duration.zero) return 'ENDED';
  if (delta.inDays >= 1) {
    return '${delta.inDays}D ${delta.inHours.remainder(24)}H LEFT';
  }
  if (delta.inHours >= 1) {
    return '${delta.inHours}H ${delta.inMinutes.remainder(60)}M LEFT';
  }
  return '${delta.inMinutes.clamp(1, 59)}M LEFT';
}
