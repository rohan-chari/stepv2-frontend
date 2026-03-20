import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.steptracker/background_sync');
  final calls = <MethodCall>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('persistBackendBaseUrl stores the backend url for native background sync', () async {
    final service = BackgroundSyncBootstrapService();

    await service.persistBackendBaseUrl();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(BackgroundSyncBootstrapService.backendBaseUrlKey),
      isNotNull,
    );
  });

  test('enableHealthKitBackgroundDelivery calls the native background sync channel', () async {
    final service = BackgroundSyncBootstrapService();

    await service.enableHealthKitBackgroundDelivery();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'enableHealthKitBackgroundDelivery');
  });
}
