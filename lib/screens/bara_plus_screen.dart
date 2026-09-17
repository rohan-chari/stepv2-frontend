import 'dart:async';
import 'package:flutter/material.dart';

import '../models/billing.dart';
import '../services/billing_controller.dart';
import '../services/meta_app_events_service.dart';
import '../styles.dart';
import '../widgets/billing_action_feedback.dart';
import '../widgets/billing_scope.dart';
import '../widgets/pill_button.dart';

/// Bara Gold membership surface. Prices come from native store metadata.
class BaraPlusScreen extends StatelessWidget {
  const BaraPlusScreen({super.key, this.controller});
  final BillingController? controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).parchmentLight,
    body: SafeArea(
      child: SingleChildScrollView(
        child: BaraPlusBody(controller: controller, standalone: true),
      ),
    ),
  );
}

class BaraPlusBody extends StatefulWidget {
  const BaraPlusBody({super.key, this.controller, this.standalone = false});
  final BillingController? controller;

  /// Embedded sheets omit the page back button.
  final bool standalone;

  @override
  State<BaraPlusBody> createState() => _BaraGoldBodyState();
}

class _BaraGoldBodyState extends State<BaraPlusBody> {
  BillingPlan _plan = BillingPlan.weekly;
  bool _busy = false;
  late final _feedback = BillingActionFeedback(
    context: () => context,
    isMounted: () => mounted,
  );

  BillingController? get _billing =>
      widget.controller ?? BillingScope.maybeOf(context);

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<BillingResult> Function() action) async {
    final billing = _billing;
    if (billing == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _feedback.perform(billing, action);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _text(
    String value, {
    double size = 14,
    bool title = false,
    Color? color,
  }) => Text(
    value,
    style: title
        ? PixelText.title(
            size: size,
            color: color ?? AppColors.of(context).textDark,
          )
        : PixelText.body(
            size: size,
            color: color ?? AppColors.of(context).textMid,
          ),
  );

  Widget _benefit(IconData icon, String title, String detail) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.pillGold.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                icon,
                color: colors.isDark ? colors.medalGold : colors.pillGoldDark,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(title, size: 16, title: true),
                const SizedBox(height: 3),
                _text(detail, size: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planButton(BillingController billing, StorePlanOffer offer) {
    final colors = AppColors.of(context);
    final selected = !billing.snapshot.isMember && _plan == offer.plan;
    final cadence = offer.plan == BillingPlan.weekly ? 'week' : 'month';
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.roofMid : colors.parchment,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('plan-${offer.plan.name}'),
          borderRadius: BorderRadius.circular(16),
          onTap: billing.snapshot.isMember
              ? null
              : () => setState(() => _plan = offer.plan),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? colors.roofMid : colors.parchmentBorder,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(
                  offer.plan == BillingPlan.weekly ? 'WEEKLY' : 'MONTHLY',
                  size: 13,
                  title: true,
                  color: selected ? colors.textLight : null,
                ),
                const SizedBox(height: 6),
                _text(
                  offer.price,
                  size: 23,
                  title: true,
                  color: selected ? colors.textLight : null,
                ),
                const SizedBox(height: 3),
                _text(
                  '${billingCoinLabel(offer.coinGrant)} coins / $cadence',
                  size: 11,
                  color: selected ? colors.textLight : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final billing = _billing;
    if (billing == null || !billing.goldPolicyAvailable) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: _text('Bara Gold is not available right now.'),
      );
    }
    return ListenableBuilder(
      listenable: billing,
      builder: (context, _) {
        final state = billing.snapshot;
        final offers = billing.plans
            .where(
              (offer) =>
                  offer.plan == BillingPlan.weekly ||
                  offer.plan == BillingPlan.monthly,
            )
            .toList();
        final offer =
            offers.where((item) => item.plan == _plan).firstOrNull ??
            offers.firstOrNull;
        final disabled =
            _busy || state.busy || offer == null || !billing.isAvailable;
        return Container(
          key: const Key('bara-gold-paywall'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.standalone)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                ),
              _text('A LITTLE EXTRA JOY', size: 10),
              _text('Bara Gold', size: 42, title: true),
              const SizedBox(height: 6),
              _text('More room to move, play, and collect.', size: 16),
              const SizedBox(height: 20),
              _benefit(
                Icons.local_offer_outlined,
                '15% off the shop',
                'Save on eligible coin purchases across the shop.',
              ),
              _benefit(
                Icons.monetization_on_outlined,
                'Plan-specific coin grants',
                'Weekly Gold grants 200 coins. Monthly Gold grants 1,000 coins.',
              ),
              _benefit(
                Icons.visibility_off_outlined,
                'No forced ads',
                'Banners, inline ads, and interruptions stay out of your run.',
              ),
              _benefit(
                Icons.bolt_rounded,
                'Ad-free extra Daily Spin and box reroll',
                'Eligible bonus spins and box rerolls skip their rewarded ad. Other rewarded placements remain unchanged.',
              ),
              _benefit(
                Icons.refresh_rounded,
                'One free reroll per powerup',
                'Gold rerolls do not consume coins or historical balances.',
              ),
              _benefit(
                Icons.pets_rounded,
                'Gold character access',
                'Unlock the Gold character catalog with server-defined coin prices.',
              ),
              if (!state.isMember) ...[
                const SizedBox(height: 16),
                if (offers.isEmpty)
                  _text('Store pricing is currently unavailable.')
                else ...[
                  Row(
                    children: [
                      for (var index = 0; index < offers.length; index++) ...[
                        if (index > 0) const SizedBox(width: 10),
                        Expanded(child: _planButton(billing, offers[index])),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  if ((offer?.trialDays ?? 0) > 0)
                    _text(
                      'Try ${offer!.trialDays} days free. The store confirms trial eligibility; billing starts after the trial unless cancelled.',
                      size: 12,
                    ),
                  const SizedBox(height: 14),
                  PillButton(
                    key: Key(
                      (offer?.trialDays ?? 0) > 0
                          ? 'start-bara-trial'
                          : 'subscribe-bara',
                    ),
                    label: (offer?.trialDays ?? 0) > 0
                        ? 'TRY ${offer!.trialDays} DAYS FREE'
                        : 'SUBSCRIBE',
                    fullWidth: true,
                    loading: _busy,
                    onPressed: disabled
                        ? null
                        : () {
                            unawaited(
                              MetaAppEventsService.instance.log(
                                MetaConversion.purchaseIntent,
                              ),
                            );
                            unawaited(
                              _perform(
                                () => offer.trialDays > 0
                                    ? billing.startTrial(offer.plan)
                                    : billing.subscribe(offer.plan),
                              ),
                            );
                          },
                  ),
                  const SizedBox(height: 9),
                  Align(
                    alignment: Alignment.center,
                    child: _text(
                      '${offer!.price} per ${offer.plan == BillingPlan.weekly ? 'week' : 'month'}. Auto-renews until cancelled.',
                      size: 12,
                    ),
                  ),
                ],
              ] else ...[
                _text(
                  state.isTrial
                      ? 'Your Gold trial is active.'
                      : 'Your Bara Gold membership is active.',
                  size: 20,
                  title: true,
                ),
                const SizedBox(height: 10),
                PillButton(
                  key: const Key('manage-bara'),
                  label: 'MANAGE MEMBERSHIP',
                  fullWidth: true,
                  variant: PillButtonVariant.secondary,
                  onPressed: _busy || state.busy
                      ? null
                      : () => _perform(billing.cancelRenewal),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                key: const Key('restore-bara'),
                onPressed: disabled ? null : () => _perform(billing.restore),
                child: _text('Restore purchases', size: 12),
              ),
              if (state.operationStatus == BillingOperationStatus.pending)
                _text(
                  state.message ?? 'Purchase is awaiting confirmation.',
                  size: 12,
                ),
            ],
          ),
        );
      },
    );
  }
}
