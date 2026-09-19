import 'dart:async';
import 'package:flutter/material.dart';

import '../models/billing.dart';
import '../services/billing_controller.dart';
import '../services/meta_app_events_service.dart';
import '../styles.dart';
import '../widgets/bara_gold_benefits.dart';
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
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    const sceneHeight = 154.0;
    const groundHeight = 58.0;
    const capySize = 116.0;
    // Same scene and feet anchoring as before; trim only unused dirt below it.
    const visibleHeight = sceneHeight - groundHeight + 18;

    return ClipRRect(
      key: const Key('bara-gold-paywall-hero'),
      borderRadius: BorderRadius.circular(18),
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: visibleHeight / sceneHeight,
        child: SizedBox(
          height: sceneHeight,
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
      ),
    );
  }

  Widget _benefitTile(BaraGoldBenefit benefit) {
    final colors = AppColors.of(context);
    return Container(
      key: Key('gold-benefit-${benefit.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colors.parchmentBorder.withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BaraGoldBenefitIcon(benefit: benefit),
          const SizedBox(width: 10),
          Expanded(child: BaraGoldBenefitText(benefit: benefit)),
        ],
      ),
    );
  }

  double get _planHeight =>
      150.0 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 3.0);

  Widget _planButton(BillingController billing, StorePlanOffer offer) {
    final colors = AppColors.of(context);
    final selected = !billing.snapshot.isMember && _plan == offer.plan;
    final monthly = offer.plan == BillingPlan.monthly;
    final title = offer.plan == BillingPlan.weekly ? 'WEEKLY' : 'MONTHLY';
    final fill = selected
        ? (colors.isDark
              ? colors.pillGoldDark
              : Color.alphaBlend(
                  colors.pillGold.withValues(alpha: 0.18),
                  colors.parchment,
                ))
        : colors.parchment;
    final borderColor = selected
        ? (colors.isDark ? colors.pillGold : colors.pillGoldDark)
        : colors.parchmentBorder;
    final foreground = colors.textDark;
    final secondary = colors.textMid;

    return SizedBox(
      width: double.infinity,
      height: _planHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              color: fill,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: Key('plan-${offer.plan.name}'),
                borderRadius: BorderRadius.circular(16),
                onTap: billing.snapshot.isMember
                    ? null
                    : () => setState(() => _plan = offer.plan),
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(minHeight: _planHeight),
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
                          style: PixelText.body(size: 14, color: secondary)
                              .copyWith(
                                decoration: TextDecoration.lineThrough,
                                decorationColor: colors.error,
                                decorationThickness: 2,
                              ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            offer.price,
                            style: PixelText.title(size: 30, color: foreground),
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
          ),
          if (monthly)
            Positioned(
              left: 0,
              right: 0,
              top: -11,
              child: Center(
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
                        color: colors.textDark,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'BEST DEAL',
                          textAlign: TextAlign.center,
                          style: PixelText.title(
                            size: 9.5,
                            color: colors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
          padding: EdgeInsets.fromLTRB(12, widget.standalone ? 8 : 4, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.standalone)
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: colors.textDark,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Bara Gold',
                        textAlign: TextAlign.center,
                        style: PixelText.title(
                          size: 22,
                          color: colors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              if (!state.isMember) ...[
                _goldHero(),
                const SizedBox(height: 10),
                for (final benefit in BaraGoldBenefit.values) ...[
                  if (benefit != BaraGoldBenefit.values.first)
                    const SizedBox(height: 6),
                  _benefitTile(benefit),
                ],
                const SizedBox(height: 16),
                if (offers.isEmpty)
                  _text('Store pricing is currently unavailable.')
                else ...[
                  LayoutBuilder(
                    key: const Key('bara-gold-plan-row'),
                    builder: (context, constraints) {
                      final weeklyOffer = offers
                          .where((item) => item.plan == BillingPlan.weekly)
                          .firstOrNull;
                      final monthlyOffer = offers
                          .where((item) => item.plan == BillingPlan.monthly)
                          .firstOrNull;
                      if (weeklyOffer == null || monthlyOffer == null) {
                        return Center(
                          child: SizedBox(
                            width: constraints.maxWidth * 0.55,
                            child: _planButton(billing, offers.first),
                          ),
                        );
                      }
                      const gap = 28.0;
                      final cardWidth = (constraints.maxWidth * 0.39).clamp(
                        118.0,
                        142.0,
                      );
                      final totalWidth = cardWidth * 2 + gap;
                      final sideInset = (constraints.maxWidth - totalWidth) / 2;
                      return SizedBox(
                        height: _planHeight + 11,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: sideInset,
                              top: 0,
                              width: cardWidth,
                              child: KeyedSubtree(
                                key: const Key('bara-gold-weekly-slot'),
                                child: _planButton(billing, weeklyOffer),
                              ),
                            ),
                            Positioned(
                              right: sideInset,
                              top: 0,
                              width: cardWidth,
                              child: KeyedSubtree(
                                key: const Key('bara-gold-monthly-slot'),
                                child: _planButton(billing, monthlyOffer),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  PillButton(
                    key: Key(
                      trialDays > 0 ? 'start-bara-trial' : 'subscribe-bara',
                    ),
                    label: trialDays > 0
                        ? 'TRY ${trialDays.toString()} DAYS FREE'
                        : 'SUBSCRIBE',
                    variant: PillButtonVariant.secondary,
                    fullWidth: true,
                    loading: _busy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
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
                              : '${offer.price} per ${offer.plan == BillingPlan.weekly ? 'week' : 'month'}. Auto-renews until cancelled.'),
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 11.5, color: colors.textMid),
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
