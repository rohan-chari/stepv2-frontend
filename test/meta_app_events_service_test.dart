import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/meta_app_events_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.steptracker/meta_app_events');
  final calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('native boundary receives only the fixed conversion name', () async {
    for (final event in MetaConversion.values) {
      await MetaAppEventsService.instance.log(event);
    }
    expect(calls.map((call) => call.method), everyElement('logEvent'));
    expect(calls.map((call) => call.arguments), [
      for (final event in MetaConversion.values) {'event': event.name},
    ]);
  });

  test('Android never invokes an iOS channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await MetaAppEventsService.instance.log(MetaConversion.shopViewed);
    await MetaAppEventsService.instance.updateConsent(resolved: true);
    expect(calls, isEmpty);
  });

  test(
    'consent signal reports resolution, not permission to request ads',
    () async {
      await MetaAppEventsService.instance.updateConsent(resolved: false);
      expect(calls.single.method, 'updateConsent');
      expect(calls.single.arguments, {'resolved': false});
    },
  );

  test('unavailable native integration cannot fail a product action', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'unavailable');
        });
    await MetaAppEventsService.instance.log(MetaConversion.shopViewed);
    await MetaAppEventsService.instance.updateConsent(resolved: false);
  });
}
