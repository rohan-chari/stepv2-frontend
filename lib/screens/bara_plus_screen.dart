import 'dart:async';
import 'package:flutter/material.dart';

import '../models/billing.dart';
import '../services/billing_controller.dart';
import '../services/meta_app_events_service.dart';
import '../styles.dart';
import '../widgets/billing_action_feedback.dart';
import '../widgets/billing_scope.dart';
import '../widgets/home_course_track.dart';
import '../widgets/home_hero_scene.dart';
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
  static const _capeAccessory = <Map<String, dynamic>>[
    <String, dynamic>{
      'slot': 'BACK',
      'assetKey': 'cape',
      'renderMetadata': <String, dynamic>{
        'scale': 2.1499999999999995,
        'offsetX': -0.1,
        'offsetY': -0.00423728813559332,
        'rotation': 0.24915254237288265,
        'renderLayer': 'front',
        'animationFrames': 6,
      },
    },
  ];

  BillingPlan _plan = BillingPlan.monthly;
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

  Widget _goldHero() {
    final colors = AppColors.of(context);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    const heroHeight = 154.0;
    const groundHeight = 58.0;
    const capySize = 116.0;

    return ClipRRect(
      key: const Key('bara-gold-paywall-hero'),
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: heroHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            HomeHeroScene(
              groundHeight: groundHeight,
              groundScrollSpeed: 24,
              excludeBackgroundSemantics: true,
              child: const SizedBox.expand(),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: groundHeight - 4 - capySize * .22 - 2,
              child: Center(
                child: AnimatedCapybaraWithAccessories(
                  accessories: _capeAccessory,
                  size: capySize,
                  stepDuration: const Duration(milliseconds: 720),
                  animate: !disableAnimations,
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _benefitTile(
    IconData icon,
    String title,
    String detail, {
    Key? key,
  }) {
    final colors = AppColors.of(context);
    final iconColor = colors.isDark ? colors.feedGold : colors.pillGoldDark;
    final tileColor = colors.isDark
        ? colors.parchmentDark.withValues(alpha: 0.88)
        : colors.parchment.withValues(alpha: 0.92);

    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.parchmentBorder.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.pillGold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 23, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(title, size: 15, title: true),
                const SizedBox(height: 3),
                _text(detail, size: 12),
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
    final monthly = offer.plan == BillingPlan.monthly;
    final title = offer.plan == BillingPlan.weekly ? 'WEEKLY' : 'MONTHLY';
    final fill = selected ? colors.roofMid : colors.parchment;
    final borderColor = selected
        ? (colors.isDark ? colors.feedGold : colors.pillGoldDark)
        : colors.parchmentBorder;
    final foreground = selected ? colors.textLight : colors.textDark;
    final secondary = selected
        ? colors.textLight.withValues(alpha: 0.74)
        : colors.textMid;

    return Stack(
      clipBehavior: Clip.none,
      children: [
          Material(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: Key('plan-' + offer.plan.name),
              borderRadius: BorderRadius.circular(16),
              onTap: billing.snapshot.isMember
                  ? null
                  : () => setState(() => _plan = offer.plan),
              child: Container(
                constraints: const BoxConstraints(minHeight: 150),
                padding: const EdgeInsets.fromLTRB(12, 22, 12, 15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: PixelText.title(size: 12.5, color: foreground),
                    ),
                    const SizedBox(height: 12),
                    if (monthly && selected && offer.price == r'$3.99') ...[
                      Text(
                        r'$5.99',
                        style: PixelText.body(
                          size: 14,
                          color: secondary,
                        ).copyWith(
                          decoration: TextDecoration.lineThrough,
                          decorationColor: colors.error,
                          decorationThickness: 2,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        offer.price,
                        style: PixelText.title(
                          size: 30,
                          color: foreground,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      offer.plan == BillingPlan.weekly
                          ? 'per week'
                          : 'per month',
                      style: PixelText.body(size: 12, color: secondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (monthly)
            Positioned(
              left: -8,
              top: -11,
              child: Container(
                key: const Key('bara-gold-best-deal'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colors.pillGold,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.pillGoldDark),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 13,
                      color: colors.isDark
                          ? colors.textLight
                          : colors.textDark,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'BEST DEAL',
                      style: PixelText.title(
                        size: 9.5,
                        color: colors.isDark
                            ? colors.textLight
                            : colors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
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
        final colors = AppColors.of(context);
        final state = billing.snapshot;
        final offers = billing.plans
            .where(
              (offer) =>
                  offer.plan == BillingPlan.weekly ||
                  offer.plan == BillingPlan.monthly,
            )
            .toList();
        final matching = offers.where((item) => item.plan == _plan);
        final monthly = offers.where(
          (item) => item.plan == BillingPlan.monthly,
        );
        final StorePlanOffer? offer = matching.isNotEmpty
            ? matching.first
            : monthly.isNotEmpty
            ? monthly.first
            : offers.isNotEmpty
            ? offers.first
            : null;
        final disabled =
            _busy || state.busy || offer == null || !billing.isAvailable;
        final trialDays = offer?.trialDays ?? 0;

        return Container(
          key: const Key('bara-gold-paywall'),
          color: colors.parchmentLight,
          padding: EdgeInsets.fromLTRB(
            12,
            widget.standalone ? 8 : 4,
            12,
            24,
          ),
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
                      color: colors.textDark,
                    ),
                  ),
                ),
              if (!state.isMember) ...[
                _goldHero(),
                const SizedBox(height: 12),
                _benefitTile(
                  Icons.monetization_on_outlined,
                  'Monthly coin bonus',
                  'Get extra coins every month. Monthly members get the biggest bonus.',
                  key: const Key('gold-benefit-coins'),
                ),
                const SizedBox(height: 7),
                _benefitTile(
                  Icons.block_rounded,
                  'Ad-free experience',
                  'No banners, no inline ads, no interruptions. Just Bara.',
                  key: const Key('gold-benefit-adfree'),
                ),
                const SizedBox(height: 7),
                _benefitTile(
                  Icons.card_giftcard_rounded,
                  'Free rerolls on everything',
                  'Reroll Daily Spins and boxes anytime, no ads required.',
                  key: const Key('gold-benefit-rerolls'),
                ),
                const SizedBox(height: 7),
                _benefitTile(
                  Icons.workspace_premium_rounded,
                  'Exclusive characters & powerups',
                  'Unlock special characters, unique accessories, and exclusive shop powerups only for Gold members.',
                  key: const Key('gold-benefit-exclusive'),
                ),
                const SizedBox(height: 16),
                if (offers.isEmpty)
                  _text('Store pricing is currently unavailable.')
                else ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cardWidth = ((constraints.maxWidth - 36) / 2)
                          .clamp(118.0, 142.0);
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final planOffer in offers)
                            SizedBox(
                              width: cardWidth,
                              child: _planButton(billing, planOffer),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  PillButton(
                    key: Key(
                      trialDays > 0
                          ? 'start-bara-trial'
                          : 'subscribe-bara',
                    ),
                    label: trialDays > 0
                        ? 'TRY ' + trialDays.toString() + ' DAYS FREE'
                        : 'SUBSCRIBE',
                    fullWidth: true,
                    loading: _busy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    onPressed: disabled || offer == null
                        ? null
                        : () {
                            unawaited(
                              MetaAppEventsService.instance.log(
                                MetaConversion.purchaseIntent,
                              ),
                            );
                            unawaited(
                              _perform(
                                () => trialDays > 0
                                    ? billing.startTrial(offer.plan)
                                    : billing.subscribe(offer.plan),
                              ),
                            );
                          },
                  ),
                  const SizedBox(height: 9),
                  Text(
                    trialDays > 0
                        ? 'The store confirms trial eligibility; billing starts after the trial unless cancelled. Auto-renews until cancelled.'
                        : (offer == null
                              ? ''
                              : offer.price +
                                    ' per ' +
                                    (offer.plan == BillingPlan.weekly
                                        ? 'week'
                                        : 'month') +
                                    '. Auto-renews until cancelled.'),
                    textAlign: TextAlign.center,
                    style: PixelText.body(
                      size: 11.5,
                      color: colors.textMid,
                    ),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 8),
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
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _text(
                    state.message ?? 'Purchase is awaiting confirmation.',
                    size: 12,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
