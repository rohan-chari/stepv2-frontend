import 'package:flutter/material.dart';

import '../styles.dart';
import '../screens/bara_plus_screen.dart';
import 'billing_scope.dart';

/// Shared secondary action shown beneath eligible rewarded-ad actions for
/// non-members. The host owns navigation so every surface reuses the same
/// presentation without duplicating paywall routing.
class RemoveAdsAction extends StatelessWidget {
  const RemoveAdsAction({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static void openPaywall(BuildContext context) {
    final controller = BillingScope.maybeOf(context);
    if (controller == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BaraPlusScreen(controller: controller)),
    );
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.center,
    child: TextButton(
      key: const Key('remove-ads-action'),
      onPressed: onPressed,
      child: Text(
        'Remove Ads',
        style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
      ),
    ),
  );
}
