import 'package:flutter/material.dart';
import '../models/billing.dart';
import '../services/billing_controller.dart';
import '../styles.dart';
import 'pill_button.dart';
import 'remove_ads_action.dart';

Future<RerollFunding?> showRerollPaymentSheet(
  BuildContext context, {
  required BillingController controller,
  bool adSupported = false,
  bool batch = false,
  RerollFunding? pendingFunding,
}) => showModalBottomSheet<RerollFunding>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.of(context).parchment,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final colors = AppColors.of(context);
            final state = controller.snapshot;
            final cost = controller.rerollCoinCost;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.refresh_rounded, size: 36, color: colors.roofLight),
                const SizedBox(height: 12),
                Text(
                  batch ? 'Give them another roll' : 'Give it another roll',
                  style: PixelText.title(size: 27, color: colors.textDark),
                ),
                const SizedBox(height: 8),
                Text(
                  batch
                      ? 'One action rerolls all eligible boxes.'
                      : 'One action rerolls this box.',
                  style: PixelText.body(size: 14, color: colors.textMid),
                ),
                const SizedBox(height: 8),
                Text(
                  'The new reward replaces the original and could be worse. One reroll per box.',
                  style: PixelText.body(size: 13, color: colors.textDark),
                ),
                const SizedBox(height: 22),
                if (state.isMember) ...[
                  PillButton(
                    key: const Key('reroll-funding-gold'),
                    label: pendingFunding == RerollFunding.freeGold
                        ? 'RETRY BARA GOLD REROLL'
                        : 'FREE BARA GOLD REROLL',
                    fullWidth: true,
                    onPressed: !state.busy
                        ? () => Navigator.pop(context, RerollFunding.freeGold)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'One free reroll per powerup. No coins or ad required.',
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 12, color: colors.textMid),
                  ),
                ],
                if (!state.isMember) ...[
                  const SizedBox(height: 18),
                  PillButton(
                    key: const Key('reroll-funding-coins'),
                    label: pendingFunding == RerollFunding.coins
                        ? 'RETRY PREVIOUS COIN REROLL'
                        : 'SPEND $cost COINS',
                    variant: PillButtonVariant.secondary,
                    fullWidth: true,
                    onPressed:
                        (pendingFunding == RerollFunding.coins ||
                                pendingFunding == null &&
                                    state.coins >= cost) &&
                            !state.busy
                        ? () => Navigator.pop(context, RerollFunding.coins)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.coins < cost
                        ? 'You need $cost coins. Balance: ${state.coins}.'
                        : '$cost coins per action · Balance: ${billingCoinLabel(state.coins)}',
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 12, color: colors.textMid),
                  ),
                  if (pendingFunding != null)
                    Text(
                      'Your previous action is still being checked. Retrying recovers that same action without a second charge.',
                      style: PixelText.body(size: 12, color: colors.textMid),
                    ),
                ],
                if (!state.isMember &&
                    adSupported &&
                    pendingFunding == null) ...[
                  const SizedBox(height: 18),
                  PillButton(
                    key: const Key('reroll-funding-ad'),
                    label: 'WATCH AN AD',
                    fullWidth: true,
                    variant: PillButtonVariant.rewardedAd,
                    onPressed: state.busy
                        ? null
                        : () => Navigator.pop(context, RerollFunding.ad),
                  ),
                  RemoveAdsAction(
                    onPressed: () => RemoveAdsAction.openPaywall(context),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'CANCEL',
                    style: PixelText.body(size: 13, color: colors.textMid),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  ),
);
