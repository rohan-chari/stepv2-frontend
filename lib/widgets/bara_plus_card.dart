import 'package:flutter/material.dart';
import '../screens/bara_plus_screen.dart';
import '../services/billing_controller.dart';
import '../styles.dart';
import 'billing_scope.dart';

class BaraPlusCard extends StatelessWidget {
  final BillingController? controller;
  final VoidCallback? onTap;
  const BaraPlusCard({super.key, this.controller, this.onTap});
  @override
  Widget build(BuildContext context) {
    final billing = controller ?? BillingScope.maybeOf(context);
    if (billing == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: billing,
      builder: (context, _) {
        if (!billing.canShowMembership) return const SizedBox.shrink();
        final colors = AppColors.of(context);
        final member = billing.snapshot.isMember;
        return Semantics(
          button: true,
          child: Material(
            color: colors.roofMid,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              key: const Key('bara-plus-card'),
              borderRadius: BorderRadius.circular(18),
              onTap:
                  onTap ??
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BaraPlusScreen(controller: billing),
                    ),
                  ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, color: colors.pillGold, size: 27),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bara+',
                            style: PixelText.title(
                              size: 25,
                              color: colors.textLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            billing.snapshot.isPermanent
                                ? 'Permanently owned · ${billing.snapshot.availableCredits} rerolls left'
                                : member
                                ? '15% shop savings · ${billing.snapshot.availableCredits} rerolls left'
                                : 'More for your capy. 15% shop savings + monthly perks.',
                            style: PixelText.body(
                              size: 12,
                              color: colors.textLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, color: colors.textLight),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
