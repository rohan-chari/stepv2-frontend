import 'package:flutter/material.dart';
import '../models/billing.dart';
import '../services/billing_controller.dart';
import '../styles.dart';
import 'billing_scope.dart';
import 'pill_button.dart';
import 'loading_skeleton.dart';

/// Product quantities and localized prices always come from the shared store
/// controller. Artwork identifies a tier; it never determines a grant.
class CoinPackOffers extends StatefulWidget {
  final BillingController? controller;
  final bool onGreenSurface;
  const CoinPackOffers({
    super.key,
    this.controller,
    this.onGreenSurface = false,
  });
  @override
  State<CoinPackOffers> createState() => _CoinPackOffersState();
}

class _CoinPackOffersState extends State<CoinPackOffers> {
  bool _busy = false;
  String? _message;
  BillingController? _controller;
  String? _userId;
  int _generation = 0;

  void _observe(BillingController? controller) {
    if (identical(controller, _controller) && controller?.userId == _userId) {
      return;
    }
    _controller = controller;
    _userId = controller?.userId;
    _generation++;
    _message = null;
    _busy = false;
  }

  Future<void> _buy(BillingController controller, CoinPackOffer offer) async {
    final generation = _generation;
    final userId = controller.userId;
    bool current() =>
        mounted && generation == _generation && controller.userId == userId;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await controller.buyCoins(offer);
      if (current()) setState(() => _message = result.message);
    } catch (_) {
      if (current()) {
        setState(
          () => _message = 'Purchase could not be completed. Please try again.',
        );
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
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
        Text('COINS', style: PixelText.title(size: 25, color: headingColor)),
        const SizedBox(height: 5),
        Text(
          'A little more for your next adventure.',
          style: PixelText.body(size: 12, color: headingColor),
        ),
        const SizedBox(height: 16),
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
        if (offers.isEmpty || controller?.isAvailable != true)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.parchment,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.parchmentBorder, width: 2),
            ),
            child: Column(
              children: [
                Text(
                  loading
                      ? 'Finding your coin packs…'
                      : 'Coin packs are currently unavailable.',
                  textAlign: TextAlign.center,
                  style: PixelText.body(size: 14, color: colors.textDark),
                ),
                if (controller != null && !loading)
                  TextButton(
                    onPressed: state?.busy == true ? null : controller.refresh,
                    child: Text(
                      'Try again',
                      style: PixelText.body(size: 13, color: colors.textDark),
                    ),
                  ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth < 340 ||
                      MediaQuery.textScalerOf(context).scale(14) > 19
                  ? 1
                  : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: [
                  for (final offer in offers)
                    SizedBox(
                      width: width,
                      child: Container(
                        key: Key('coin-tile-${offer.id}'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.parchment,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors.coinDark, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: colors.roofDark.withValues(alpha: .55),
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              billingCoinLabel(offer.coins),
                              textAlign: TextAlign.center,
                              style: PixelText.title(
                                size: 29,
                                color: colors.textDark,
                              ),
                            ),
                            Text(
                              'COINS',
                              textAlign: TextAlign.center,
                              style: PixelText.body(
                                size: 10,
                                color: colors.textMid,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Image.asset(
                              'assets/images/shop/coin_sack_${_art(offer)}.png',
                              height: 120,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.none,
                              excludeFromSemantics: true,
                            ),
                            const SizedBox(height: 8),
                            PillButton(
                              key: Key('buy-coins-${offer.id}'),
                              label: offer.price,
                              fontSize: 15,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              fullWidth: true,
                              variant: PillButtonVariant.secondary,
                              onPressed: _busy || state?.busy == true
                                  ? null
                                  : () => _buy(controller!, offer),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        if (state?.message != null || _message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              state?.message ?? _message ?? '',
              style: PixelText.body(size: 13, color: headingColor),
            ),
          ),
        if (state?.operationStatus == BillingOperationStatus.pending)
          TextButton(
            onPressed: controller?.refresh,
            child: Text(
              'Check purchase status',
              style: PixelText.body(size: 13, color: headingColor),
            ),
          ),
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
}
