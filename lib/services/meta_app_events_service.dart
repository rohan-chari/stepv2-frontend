import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// This boundary intentionally cannot accept arbitrary event names, user data,
/// purchase amounts, health data, or race identifiers.
enum MetaConversion {
  registrationCompleted,
  onboardingCompleted,
  raceJoined,
  shopViewed,
  membershipViewed,
  coinOffersViewed,
  purchaseIntent,
}

/// Native iOS owns permission and lifecycle evaluation. Product actions never
/// wait for Meta's network, and other platforms never call the native channel.
class MetaAppEventsService {
  const MetaAppEventsService();

  static const instance = MetaAppEventsService();
  static const _channel = MethodChannel('com.steptracker/meta_app_events');

  Future<void> log(MetaConversion event) =>
      _invoke('logEvent', {'event': event.name});

  /// Reports whether CMP resolution succeeded, not `canRequestAds` or another
  /// partner's consent. Native code evaluates Meta's own applicable signals.
  Future<void> updateConsent({required bool resolved}) =>
      _invoke('updateConsent', {'resolved': resolved});

  Future<void> _invoke(String method, Map<String, Object> arguments) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<bool>(method, arguments);
    } catch (_) {
      // Measurement must never fail a successful user action or block startup.
    }
  }
}
