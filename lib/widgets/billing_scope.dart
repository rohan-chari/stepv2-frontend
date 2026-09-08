import 'package:flutter/widgets.dart';
import '../services/billing_controller.dart';

class BillingScope extends InheritedNotifier<BillingController> {
  const BillingScope({
    super.key,
    required BillingController controller,
    required super.child,
  }) : super(notifier: controller);
  const BillingScope.disabled({super.key, required super.child})
    : super(notifier: null);
  static BillingController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BillingScope>()?.notifier;
  static BillingController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BillingScope>()?.notifier;
}
