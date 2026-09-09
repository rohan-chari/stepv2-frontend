import 'package:flutter/material.dart';

import '../models/billing.dart';
import '../services/billing_controller.dart';
import 'error_toast.dart';
import 'info_toast.dart';

/// Feedback belongs to the widget/session that initiated an operation. Snapshot
/// messages are durable state, never a stream of UI events to replay on rebuild.
class BillingActionFeedback {
  BillingActionFeedback({required this.context, required this.isMounted});
  final BuildContext Function() context;
  final bool Function() isMounted;
  BillingController? _controller;
  String? _userId;
  int _generation = 0;
  int _sequence = 0;
  bool _pending = false;
  bool _disposed = false;
  VoidCallback? _dismiss;

  void observe(BillingController? controller) {
    // Register a route dependency so covering checkout also clears its overlay.
    if (isMounted() && ModalRoute.of(context())?.isCurrent == false) {
      final dismiss = _dismiss;
      _dismiss = null;
      if (dismiss != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => dismiss());
      }
    }
    if (identical(_controller, controller) && _userId == controller?.userId) {
      return;
    }
    _controller?.removeListener(_changed);
    _dismiss?.call();
    _dismiss = null;
    _controller = controller;
    _userId = controller?.userId;
    _sequence = controller?.pendingFeedback?.sequence ?? 0;
    _generation++;
    _pending = false;
    controller?.addListener(_changed);
  }

  void _changed() {
    final controller = _controller;
    if (_disposed || controller == null || !isMounted()) return;
    if (controller.userId != _userId) {
      observe(controller);
      return;
    }
    final event = controller.pendingFeedback;
    if (event == null || event.sequence <= _sequence) return;
    _sequence = event.sequence;
    if (!_pending || event.userId != _userId) return;
    _pending = false;
    _show(event.result);
  }

  Future<void> perform(
    BillingController controller,
    Future<BillingResult> Function() action,
  ) async {
    observe(controller);
    final generation = _generation;
    final sequence = controller.pendingFeedback?.sequence ?? 0;
    _pending = false;
    bool current() =>
        !_disposed &&
        isMounted() &&
        generation == _generation &&
        identical(controller, _controller) &&
        controller.userId == _userId;
    BillingResult result;
    try {
      result = await action();
    } catch (_) {
      result = const BillingResult(
        success: false,
        message: 'That could not be completed. Please try again.',
      );
    }
    if (!current()) return;
    if (result.disposition == BillingDisposition.pending) {
      _pending = true;
      // Reconciliation may finish between the action's future and this await.
      _sequence = sequence;
      _changed();
    } else {
      _show(result);
    }
  }

  void _show(BillingResult result) {
    if (_disposed || !isMounted() || result.message.trim().isEmpty) return;
    if (result.disposition == BillingDisposition.cancelled ||
        result.disposition == BillingDisposition.pending) {
      return;
    }
    final ownerContext = context();
    if (ModalRoute.of(ownerContext)?.isCurrent == false) return;
    _dismiss?.call();
    _dismiss = result.disposition == BillingDisposition.error
        ? showErrorToast(context(), result.message)
        : showInfoToast(context(), result.message);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _controller?.removeListener(_changed);
    _dismiss?.call();
    _dismiss = null;
  }
}
