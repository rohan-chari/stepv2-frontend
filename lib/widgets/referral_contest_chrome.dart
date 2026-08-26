import 'package:flutter/material.dart';

import '../models/giveaway.dart';
import '../styles.dart';

/// Shared card and formatting primitives for the referral-contest flow.
///
BoxDecoration referralContestPanelDecoration(BuildContext context) {
  final colors = AppColors.of(context);
  return BoxDecoration(
    color: colors.parchment,
    borderRadius: BorderRadius.circular(15),
    border: Border.all(
      color: colors.roofDark.withValues(alpha: .48),
      width: 1.5,
    ),
    boxShadow: [
      BoxShadow(
        color: colors.roofEdge.withValues(alpha: .62),
        offset: const Offset(0, 5),
        blurRadius: 1,
      ),
    ],
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
