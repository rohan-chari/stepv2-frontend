import 'dart:async';
import 'package:flutter/material.dart';
import '../services/meta_app_events_service.dart';
import '../models/billing.dart';
import '../services/billing_controller.dart';
import '../styles.dart';
import 'billing_scope.dart';
import 'billing_action_feedback.dart';
import 'pill_button.dart';
import 'loading_skeleton.dart';
import 'shop_product_grid.dart';

/// Product quantities and localized prices always come from the shared store
/// controller. Artwork identifies a tier; it never determines a grant.
class CoinPackOffers extends StatefulWidget {
  final BillingController? controller;
  final bool onGreenSurface;
  final Widget? leadingTile;
  final bool showHeading;
  const CoinPackOffers({
    super.key,
    this.controller,
    this.onGreenSurface = false,
    this.leadingTile,
    this.showHeading = true,
  });
  @override
  State<CoinPackOffers> createState() => _CoinPackOffersState();
}

class _CoinPackOffersState extends State<CoinPackOffers> {
  bool _busy = false;
  String? _busyOfferId;
  late final _feedback = BillingActionFeedback(
    context: () => context,
    isMounted: () => mounted,
  );
  BillingController? _controller;
  String? _userId;
  int _generation = 0;

  void _observe(BillingController? controller) {
    _feedback.observe(controller);
    if (identical(controller, _controller) && controller?.userId == _userId) {
      return;
    }
    _controller = controller;
    _userId = controller?.userId;
    _generation++;
    _busy = false;
    _busyOfferId = null;
  }

  Future<void> _buy(BillingController controller, CoinPackOffer offer) async {
    final generation = _generation;
    final userId = controller.userId;
    bool current() =>
        mounted && generation == _generation && controller.userId == userId;
    if (_busy || controller.snapshot.busy) return;
    if (!controller.isPreview) {
      unawaited(
        MetaAppEventsService.instance.log(MetaConversion.purchaseIntent),
      );
    }
    setState(() {
      _busy = true;
      _busyOfferId = offer.id;
    });
    try {
      await _feedback.perform(controller, () => controller.buyCoins(offer));
    } finally {
      if (current()) {
        setState(() {
          _busy = false;
          _busyOfferId = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  String _art(CoinPackOffer offer) => switch (offer.id) {
    'coins_2800' => 'medium',
    'coins_6000' => 'large',
    _ => 'small',
  };

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? BillingScope.maybeOf(context);
    if (controller == null) return _content(context, null);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _content(context, controller),
    );
  }

  Widget _content(BuildContext context, BillingController? controller) {
    _observe(controller);
    final colors = AppColors.of(context);
    final state = controller?.snapshot;
    final offers = controller?.coinPacks ?? const <CoinPackOffer>[];
    final headingColor = widget.onGreenSurface ? Colors.white : colors.textDark;
    final loading = state?.operationStatus == BillingOperationStatus.loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading) ...[
          Text('COINS', style: PixelText.title(size: 25, color: headingColor)),
          const SizedBox(height: 8),
        ],
        if (loading) ...[
          Semantics(
            label: 'Loading store products',
            child: LinearProgressIndicator(),
          ),
          const SizedBox(height: 12),
          if (offers.isEmpty)
            const LoadingSkeleton(
              child: Row(
                children: [
                  Expanded(
                    child: SkeletonBox(
                      width: double.infinity,
                      height: 180,
                      radius: 16,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: SkeletonBox(
                      width: double.infinity,
                      height: 180,
                      radius: 16,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
        ShopProductGrid(
          gridKey: const Key('shop-featured-grid'),
          children: [
            ?widget.leadingTile,
            if (controller != null && controller.isAvailable)
              for (final offer in offers) _tile(context, controller, offer),
          ],
        ),
        if (offers.isEmpty || controller?.isAvailable != true)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  loading
                      ? 'Finding your coin packs…'
                      : 'Coin packs are currently unavailable.',
                  textAlign: TextAlign.center,
                  style: PixelText.body(size: 13, color: headingColor),
                ),
                if (controller != null && !loading)
                  TextButton(
                    onPressed: state?.busy == true ? null : controller.refresh,
                    child: Text(
                      'Try again',
                      style: PixelText.body(size: 13, color: headingColor),
                    ),
                  ),
              ],
            ),
          ),
        if (state?.operationStatus == BillingOperationStatus.pending) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              state?.message ?? 'Purchase is awaiting confirmation.',
              style: PixelText.body(size: 13, color: headingColor),
            ),
          ),
          TextButton(
            onPressed: controller?.refresh,
            child: Text(
              'Check purchase status',
              style: PixelText.body(size: 13, color: headingColor),
            ),
          ),
        ],
        if (controller?.isPreview == true)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              'PREVIEW · Sample USD prices. No real charges.',
              style: PixelText.body(size: 11, color: headingColor),
            ),
          ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    BillingController controller,
    CoinPackOffer offer,
  ) {
    final colors = AppColors.of(context);
    return Container(
      key: Key('coin-tile-${offer.id}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.parchmentBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 25,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  billingCoinLabel(offer.coins),
                  style: PixelText.title(size: 19, color: colors.textDark),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Image.asset(
                'assets/images/shop/coin_sack_${_art(offer)}.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                excludeFromSemantics: true,
              ),
            ),
          ),
          SizedBox(
            height: 16,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'COINS',
                  style: PixelText.body(size: 9, color: colors.textMid),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: PillButton(
                key: Key('buy-coins-${offer.id}'),
                label: 'Buy · ${offer.price}',
                loading: _busy && _busyOfferId == offer.id,
                fontSize: 12,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                fullWidth: true,
                variant: PillButtonVariant.primary,
                onPressed: _busy || controller.snapshot.busy
                    ? null
                    : () => _buy(controller, offer),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
