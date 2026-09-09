import '../config/animals.dart';
import '../services/remote_asset_cache.dart';
import '../widgets/accessory_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/billing.dart';
import '../services/billing_controller.dart';
import '../styles.dart';
import '../widgets/billing_scope.dart';
import '../widgets/billing_action_feedback.dart';
import '../widgets/pill_button.dart';

/// Internal full-page wrapper; app entry points use the embedded Shop body.
class BaraPlusScreen extends StatelessWidget {
  final BillingController? controller;
  const BaraPlusScreen({super.key, this.controller});
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
  final BillingController? controller;
  const BaraPlusBody({super.key, this.controller, this.standalone = false});
  final bool standalone;
  @override
  State<BaraPlusBody> createState() => _BaraPlusScreenState();
}

class _BaraPlusScreenState extends State<BaraPlusBody> {
  BillingPlan _plan = BillingPlan.monthly;
  bool _busy = false;
  late final _feedback = BillingActionFeedback(
    context: () => context,
    isMounted: () => mounted,
  );
  BillingController? _observedController;
  String? _observedUser;
  int _generation = 0;

  void _observe(BillingController? controller) {
    if (!identical(controller, _observedController) ||
        controller?.userId != _observedUser) {
      _generation++;
      _busy = false;
      _observedController = controller;
      _observedUser = controller?.userId;
    }
    _feedback.observe(controller);
  }

  Future<void> _perform(Future<BillingResult> Function() action) async {
    final controller = widget.controller ?? BillingScope.read(context);
    if (controller == null || _busy) return;
    _observe(controller);
    final generation = _generation;
    setState(() => _busy = true);
    try {
      await _feedback.perform(controller, action);
    } finally {
      if (mounted &&
          generation == _generation &&
          controller.userId == _observedUser) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
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
  String _subscriptionGuidance(BillingSubscription subscription) {
    final access = subscription.givesAccess
        ? ''
        : 'Its subscription benefits are currently unavailable. ';
    final renewal = subscription.renews
        ? 'Cancel renewal in your store to stop future charges. Each paid renewal still adds its plan’s bundle.'
        : 'Check your store for renewal and payment status.';
    return 'Permanent Bara+ does not cancel your existing subscription. $access$renewal';
  }

  Widget _benefit(IconData icon, String title, String detail) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.roofLight.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: colors.roofLight, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(title, size: 17, title: true),
                const SizedBox(height: 4),
                _text(detail, size: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planButton(
    BillingPlan plan,
    String title,
    String price,
    String detail,
  ) {
    final colors = AppColors.of(context);
    final selected =
        (widget.controller ?? BillingScope.maybeOf(context))
                ?.snapshot
                .isMember ==
            true
        ? plan == BillingPlan.permanent
        : _plan == plan;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.roofMid : colors.parchment,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('plan-${plan.name}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _plan = plan),
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
                  title,
                  size: 14,
                  title: true,
                  color: selected ? colors.textLight : colors.textDark,
                ),
                const SizedBox(height: 7),
                _text(
                  price,
                  size: 23,
                  title: true,
                  color: selected ? colors.textLight : colors.textDark,
                ),
                const SizedBox(height: 5),
                _text(
                  detail,
                  size: 11,
                  color: selected ? colors.textLight : colors.textMid,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthlyCosmetic(BillingCosmetic? cosmetic) {
    final colors = AppColors.of(context);
    final art = cosmetic == null
        ? Image.asset(
            'assets/images/accessories/wizard_hat.png',
            width: 72,
            height: 72,
            filterQuality: FilterQuality.none,
          )
        : SizedBox(
            width: 72,
            height: 72,
            child: AccessoryThumbnail(
              assetKey: cosmetic.assetKey,
              assetPath: cosmetic.slot == 'CHARACTER'
                  ? animalSpriteFor(cosmetic.assetKey).asset
                  : null,
              animationFrames: cosmetic.slot == 'CHARACTER'
                  ? animalSpriteFor(cosmetic.assetKey).frameCount
                  : cosmetic.animationFrames,
              remoteKind: cosmetic.slot == 'CHARACTER'
                  ? RemoteAssetKind.characters
                  : RemoteAssetKind.accessories,
              errorBuilder: (context, error, stack) =>
                  Icon(Icons.checkroom_rounded, color: colors.textMid),
            ),
          );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text('THE MONTHLY LOOK', size: 10),
        const SizedBox(height: 5),
        _text(cosmetic?.name ?? 'Something to show off', size: 18, title: true),
        const SizedBox(height: 4),
        _text(
          cosmetic == null
              ? 'Sample cosmetic · existing art'
              : '${cosmetic.month} · Added to your wardrobe',
          size: 11,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 230 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: art),
              const SizedBox(height: 12),
              copy,
            ],
          );
        }
        return Row(
          children: [
            art,
            const SizedBox(width: 14),
            Expanded(child: copy),
          ],
        );
      },
    );
  }

  Widget _planChoices(BillingController billing) {
    final choices = [
      if (!billing.snapshot.isMember)
        _planButton(
          BillingPlan.monthly,
          'MONTHLY',
          billing.plans
                  .where((p) => p.plan == BillingPlan.monthly)
                  .firstOrNull
                  ?.price ??
              'Unavailable',
          'Billed each month',
        ),
      _planButton(
        BillingPlan.permanent,
        'PERMANENT',
        billing.plans
                .where((p) => p.plan == BillingPlan.permanent)
                .firstOrNull
                ?.price ??
            'Unavailable',
        'One-time payment',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 300 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < choices.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                choices[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < choices.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: choices[i]),
            ],
          ],
        );
      },
    );
  }

  Future<void> _manage(BillingController billing) async {
    if (!billing.isPreview) {
      await _perform(billing.cancelRenewal);
      return;
    }
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.of(context).parchment,
        title: _text(
          billing.isPreview ? 'Preview membership' : 'Manage membership',
          size: 22,
          title: true,
        ),
        content: _text(
          billing.snapshot.isPermanent
              ? 'Cancel the separate subscription renewal? Permanent Bara+ and its monthly rewards stay yours.'
              : 'Cancel renewal? Your paid membership lasts through its current period. Paid rerolls and owned cosmetics stay yours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('KEEP MEMBERSHIP'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CANCEL RENEWAL'),
          ),
        ],
      ),
    );
    if (cancel == true && mounted) await _perform(billing.cancelRenewal);
  }

  Future<void> _changePlan(BillingController billing) async {
    final offer = billing.plans
        .where(
          (offer) =>
              offer.plan == BillingPlan.monthly &&
              offer.plan != billing.snapshot.plan,
        )
        .firstOrNull;
    if (offer == null) return;
    final annual = offer.plan == BillingPlan.annual;
    final confirmed = await showModalBottomSheet<bool>(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _text('Change billing plan', size: 26, title: true),
                const SizedBox(height: 12),
                _text(
                  '${annual ? 'Yearly' : 'Monthly'} · ${offer.price}/${annual ? 'year' : 'month'}',
                  size: 22,
                  title: true,
                ),
                const SizedBox(height: 12),
                _text(
                  'Your current plan continues until the next renewal. The new price and paid benefits start when the new plan is charged. Confirm the change and its date in the store.',
                  size: 14,
                ),
                const SizedBox(height: 20),
                PillButton(
                  key: const Key('confirm-bara-plan-change'),
                  label: 'CONTINUE TO STORE',
                  fullWidth: true,
                  onPressed: () => Navigator.pop(context, true),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: _text('Keep current plan', size: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(() => billing.changePlan(offer.plan));
    }
  }

  @override
  Widget build(BuildContext context) {
    final billing = widget.controller ?? BillingScope.maybeOf(context);
    final colors = AppColors.of(context);
    _observe(billing);
    if (billing == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: _text('Membership is not available yet.'),
      );
    }
    return ListenableBuilder(
      listenable: billing,
      builder: (context, _) {
        final state = billing.snapshot;
        _observe(billing);
        final cosmetic = billing.cosmetic;
        final selectedPlan = state.isMember ? BillingPlan.permanent : _plan;
        final permanent = selectedPlan == BillingPlan.permanent;
        final legacyAnnual = state.isMember && state.plan == BillingPlan.annual;
        final unknownPlan = state.isMember && state.plan == null;
        final offer = billing.plans
            .where((p) => p.plan == selectedPlan)
            .firstOrNull;
        final annual = legacyAnnual && offer == null;
        final trialDays = offer?.trialDays ?? 0;
        final disabled = _busy || state.busy || !billing.isAvailable;
        return Container(
          decoration: BoxDecoration(
            color: colors.parchmentLight,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: billing.isPreview
                            ? _text('PREVIEW · NO REAL CHARGES', size: 10)
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              if (widget.standalone || billing.isPreview || cosmetic != null)
                Container(
                  padding: EdgeInsets.all(widget.standalone ? 22 : 10),
                  decoration: BoxDecoration(
                    color: colors.roofMid,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.standalone) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _text(
                                    'A LITTLE EXTRA JOY',
                                    size: 10,
                                    color: colors.textLight,
                                  ),
                                  const SizedBox(height: 5),
                                  _text(
                                    'Bara+',
                                    size: 48,
                                    title: true,
                                    color: colors.textLight,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.auto_awesome,
                              color: colors.pillGold,
                              size: 35,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _text(
                          'For you. For your capy.',
                          size: 24,
                          title: true,
                          color: colors.textLight,
                        ),
                        const SizedBox(height: 8),
                        _text(
                          'Shop savings, fresh looks and more chances at a favorite powerup.',
                          size: 14,
                          color: colors.textLight,
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (billing.isPreview || cosmetic != null)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.parchment,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: _monthlyCosmetic(cosmetic),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 22),
              if (state.status != BillingStatus.free) ...[
                _text(
                  state.isPermanent
                      ? 'Bara+ permanently owned'
                      : state.isTrial
                      ? 'Your 7-day trial'
                      : state.isMember
                      ? 'Your Bara+ membership'
                      : 'Your membership has ended',
                  size: 23,
                  title: true,
                ),
                const SizedBox(height: 12),
                _text(
                  '${state.paidCredits} paid rerolls',
                  size: 20,
                  title: true,
                ),
                _text(
                  'Paid credits roll over and remain usable after membership ends.',
                  size: 12,
                ),
                if (state.isTrial) ...[
                  const SizedBox(height: 9),
                  _text(
                    '${state.trialCredits} trial rerolls',
                    size: 20,
                    title: true,
                  ),
                  _text(
                    'Unused trial credits expire when the trial ends.',
                    size: 12,
                  ),
                ],
                if (!state.isPermanent && state.accessUntil != null) ...[
                  const SizedBox(height: 9),
                  _text(
                    '${state.renews ? 'Next renewal' : 'Access until'}: ${state.accessUntil!.month}/${state.accessUntil!.day}/${state.accessUntil!.year}',
                    size: 12,
                  ),
                ],
                if (state.isMember && !state.isPermanent && !state.renews)
                  _text(
                    'Renewal cancelled. Your current benefits remain active.',
                    size: 12,
                  ),
                if (state.isPermanent)
                  if (state.nextRewardAt case final DateTime rewardAt)
                    _text(
                      'Next reward: ${DateFormat("MMM d, yyyy 'at' h:mm a 'UTC'").format(rewardAt.toUtc())}',
                      size: 12,
                    ),
                if (state.isPermanent)
                  if (state.subscription
                      case final BillingSubscription subscription)
                    _text(_subscriptionGuidance(subscription), size: 12),
                if (legacyAnnual && offer != null) ...[
                  const SizedBox(height: 9),
                  _text('Legacy annual membership', size: 14, title: true),
                  _text('6,000 coins upfront', size: 12),
                  _text('120 reroll actions upfront', size: 12),
                  _text(
                    'Your existing annual plan’s paid bundle. Permanent rewards are listed below.',
                    size: 12,
                  ),
                ],
                const SizedBox(height: 20),
              ],
              if (!state.isPermanent) ...[
                _text(
                  state.isMember
                      ? 'Keep Bara+ permanently'
                      : 'Choose your membership',
                  size: 23,
                  title: true,
                ),
                const SizedBox(height: 12),
                _planChoices(billing),
                const SizedBox(height: 16),
              ],
              _benefit(
                Icons.local_offer_outlined,
                '15% off the shop',
                'Save on cosmetic and powerup items, using earned or purchased coins.',
              ),
              _benefit(
                Icons.pets_rounded,
                unknownPlan
                    ? 'Member coin rewards'
                    : annual
                    ? '6,000 coins upfront'
                    : '500 coins each month',
                unknownPlan
                    ? 'Your verified plan determines reward timing.'
                    : annual
                    ? 'The full year’s coins arrive after payment. Spend them anywhere.'
                    : (state.isPermanent || (permanent && offer != null))
                    ? 'Every month forever, with no renewal payment. Spend them anywhere.'
                    : 'Your coin grant arrives after each monthly payment.',
              ),
              _benefit(
                Icons.refresh_rounded,
                unknownPlan
                    ? 'Member reroll rewards'
                    : annual
                    ? '120 reroll actions upfront'
                    : '10 reroll actions each month',
                'Skip the ad. One credit covers a single reroll or Reroll All. Paid credits never expire.',
              ),
              _benefit(
                Icons.checkroom_rounded,
                'A fresh cosmetic every month',
                'The shared calendar collection. Each month’s look arrives during paid membership and stays in your wardrobe.',
              ),
              _benefit(
                Icons.auto_awesome,
                'Make your profile yours',
                'A member badge and profile styling while Bara+ is active.',
              ),
              const SizedBox(height: 18),
              if (!state.isPermanent && (!state.isMember || offer != null)) ...[
                if (permanent)
                  _text(
                    state.isMember && !state.isTrial
                        ? 'One-time payment for permanent access. If an existing paid subscription period has time remaining, your first 500 coins and 10 credits arrive when it ends; otherwise they arrive now. Rewards continue monthly forever. This does not cancel your subscription; cancel renewal in your store to stop future charges.'
                        : state.isTrial
                        ? 'One-time payment for permanent access. Receive 500 coins and 10 paid reroll credits now, then monthly forever. Unused trial credits end when permanent Bara+ activates. This does not cancel your trial subscription; cancel renewal in your store to avoid its future charges.'
                        : 'One-time payment for permanent access. Receive 500 coins and 10 paid reroll credits now, then monthly forever. No subscription renewal or trial.',
                    size: 13,
                  ),
                if (trialDays > 0)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.pillGold.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _text('Your first 7 days', size: 20, title: true),
                        const SizedBox(height: 7),
                        _text(
                          'Shop savings, member styling and 3 trial rerolls. Coins, paid rerolls and permanent cosmetics begin only after the first payment.',
                          size: 13,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                PillButton(
                  key: Key(
                    permanent
                        ? 'buy-permanent-bara'
                        : trialDays > 0
                        ? 'start-bara-trial'
                        : 'subscribe-bara',
                  ),
                  label: permanent
                      ? 'GET PERMANENT BARA+'
                      : trialDays > 0
                      ? 'TRY $trialDays DAYS FREE'
                      : 'SUBSCRIBE',
                  fullWidth: true,
                  loading: _busy,
                  onPressed: disabled || offer == null
                      ? null
                      : () => _perform(
                          () => permanent
                              ? billing.buyPermanent()
                              : trialDays > 0
                              ? billing.startTrial(selectedPlan)
                              : billing.subscribe(selectedPlan),
                        ),
                ),
                const SizedBox(height: 10),
                _text(
                  offer == null
                      ? 'Store pricing is currently unavailable.'
                      : permanent
                      ? '${offer.price}. One-time payment.'
                      : '${trialDays > 0 ? 'Then ' : ''}${offer.price}/month. Auto-renews until cancelled.',
                  size: 12,
                ),
                if (trialDays > 0)
                  _text(
                    'Trial eligibility will be confirmed by the store. Cancel before the trial ends to avoid payment.',
                    size: 11,
                  ),
                if (billing.isPreview && !permanent)
                  TextButton(
                    key: const Key('preview-paid-membership'),
                    onPressed: disabled
                        ? null
                        : () => _perform(() => billing.subscribe(_plan)),
                    child: _text('Preview paid membership', size: 13),
                  ),
              ],
              if (billing.canManageSubscription) ...[
                PillButton(
                  key: const Key('manage-bara'),
                  label: 'MANAGE MEMBERSHIP',
                  fullWidth: true,
                  variant: PillButtonVariant.secondary,
                  onPressed: _busy || state.busy
                      ? null
                      : () => _manage(billing),
                ),
                if (billing.canChangePlan)
                  TextButton(
                    key: const Key('change-bara-plan'),
                    onPressed: disabled ? null : () => _changePlan(billing),
                    child: _text('Change billing plan', size: 13),
                  ),
                if (state.isTrial && billing.isPreview)
                  TextButton(
                    key: const Key('preview-paid-membership'),
                    onPressed: disabled
                        ? null
                        : () => _perform(
                            () => billing.subscribe(state.plan ?? _plan),
                          ),
                    child: _text('Preview first payment', size: 13),
                  ),
              ],
              TextButton(
                key: const Key('restore-bara'),
                onPressed: disabled ? null : () => _perform(billing.restore),
                child: _text('Restore purchases', size: 13),
              ),
              if (billing.termsUrl != null || billing.privacyUrl != null)
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    if (billing.termsUrl case final String url)
                      TextButton(
                        onPressed: () => _perform(() => billing.openLegal(url)),
                        child: _text('Terms of Use', size: 12),
                      ),
                    if (billing.privacyUrl case final String url)
                      TextButton(
                        onPressed: () => _perform(() => billing.openLegal(url)),
                        child: _text('Privacy Policy', size: 12),
                      ),
                  ],
                ),
              if (state.operationStatus == BillingOperationStatus.pending) ...[
                _text(
                  state.message ?? 'Purchase is awaiting confirmation.',
                  size: 13,
                ),
                TextButton(
                  onPressed: () => billing.refresh(),
                  child: _text('Check purchase status', size: 13),
                ),
              ],
              if (billing.isPreview)
                _text(
                  'Frontend preview · Sample USD prices and cosmetic. Checkout and subscription management are simulated.',
                  size: 11,
                ),
            ],
          ),
        );
      },
    );
  }
}
