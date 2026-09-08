import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/live_billing_controller.dart';
import '../services/store_billing_client.dart';
import 'billing_scope.dart';

/// Lives above MaterialApp's Navigator without changing the app's navigation.
class LiveBillingScope extends StatefulWidget {
  final AuthService auth;
  final Widget child;
  const LiveBillingScope({super.key, required this.auth, required this.child});
  @override
  State<LiveBillingScope> createState() => _LiveBillingScopeState();
}

class _LiveBillingScopeState extends State<LiveBillingScope>
    with WidgetsBindingObserver {
  late final LiveBillingController controller;
  @override
  void initState() {
    super.initState();
    final platform = kIsWeb
        ? ''
        : Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
        ? 'android'
        : '';
    final key = platform == 'ios'
        ? const String.fromEnvironment('REVENUECAT_IOS_API_KEY')
        : platform == 'android'
        ? const String.fromEnvironment('REVENUECAT_ANDROID_API_KEY')
        : '';
    controller = LiveBillingController(
      auth: widget.auth,
      api: BackendApiService(),
      store: RevenueCatBillingClient(apiKey: key),
      platform: platform,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(controller.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BillingScope(controller: controller, child: widget.child);
}
