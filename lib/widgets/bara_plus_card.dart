import 'package:flutter/material.dart';
import '../services/billing_controller.dart';
import '../models/billing.dart';
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
        if (!billing.canShowMembership &&
            billing.snapshot.status == BillingStatus.free) {
          return const SizedBox.shrink();
        }
        final colors = AppColors.of(context);
        return Semantics(
          button: true,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              key: const Key('bara-plus-card'),
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, color: colors.roofMid, size: 27),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bara Gold',
                            style: PixelText.title(
                              size: 25,
                              color: colors.roofDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'More room to move, play, and collect.',
                            style: PixelText.body(
                              size: 12,
                              color: colors.textMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, color: colors.roofMid),
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
