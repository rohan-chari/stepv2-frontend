import 'package:flutter/material.dart';
import '../models/billing.dart';
import '../services/billing_controller.dart';
import '../styles.dart';
import 'billing_scope.dart';
import 'pill_button.dart';

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
  Future<void> _buy(BillingController controller, CoinPackOffer offer) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await controller.buyCoins(offer);
      if (mounted) setState(() => _message = result.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Purchase could not be completed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? BillingScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isAvailable) return const SizedBox.shrink();
        final colors = AppColors.of(context);
        final state = controller.snapshot;
        final headingColor = widget.onGreenSurface
            ? Colors.white
            : colors.textDark;
        final supportingColor = widget.onGreenSurface
            ? Colors.white
            : colors.textMid;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A LITTLE MORE POSSIBILITY',
              style: PixelText.body(size: 11, color: supportingColor),
            ),
            const SizedBox(height: 4),
            Text(
              'Fill your coin pouch',
              style: PixelText.title(size: 25, color: headingColor),
            ),
            const SizedBox(height: 6),
            Text(
              'Pick your next outfit, powerup or box reroll.',
              style: PixelText.body(size: 13, color: supportingColor),
            ),
            const SizedBox(height: 16),
            for (final offer in controller.coinPacks)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.parchment,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colors.parchmentBorder, width: 2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.pillGold.withValues(alpha: .25),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.pets_rounded,
                          color: colors.textDark,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (offer.highlight != null)
                              Text(
                                offer.highlight!,
                                style: PixelText.body(
                                  size: 9,
                                  color: colors.textMid,
                                ),
                              ),
                            Text(
                              billingCoinLabel(offer.coins),
                              style: PixelText.title(
                                size: 25,
                                color: colors.textDark,
                              ),
                            ),
                            Text(
                              'coins',
                              style: PixelText.body(
                                size: 12,
                                color: colors.textMid,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      PillButton(
                        key: Key('buy-coins-${offer.id}'),
                        label: offer.price,
                        fontSize: 14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        variant: PillButtonVariant.secondary,
                        onPressed: _busy || state.busy
                            ? null
                            : () => _buy(controller, offer),
                      ),
                    ],
                  ),
                ),
              ),
            if (state.operationStatus == BillingOperationStatus.loading)
              const LinearProgressIndicator(),
            if (state.message != null || _message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  state.message ?? _message ?? '',
                  style: PixelText.body(size: 13, color: headingColor),
                ),
              ),
            if (state.operationStatus == BillingOperationStatus.pending)
              TextButton(
                onPressed: controller.refresh,
                child: Text(
                  'Check purchase status',
                  style: PixelText.body(size: 13, color: headingColor),
                ),
              ),
            if (controller.isPreview)
              Text(
                'PREVIEW · Sample USD prices. No real charges.',
                style: PixelText.body(size: 11, color: supportingColor),
              ),
          ],
        );
      },
    );
  }
}
