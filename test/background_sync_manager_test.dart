import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/background_sync_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'be.tramckrijte.workmanager/foreground_channel_work_manager',
  );

  final calls = <MethodCall>[];

  setUp(() {
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

  test('scheduleNextSync schedules the configured background task', () async {
    final scheduled = await BackgroundSyncManager.scheduleNextSync();

    expect(scheduled, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'registerOneOffTask');

    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments['uniqueName'], BackgroundSyncManager.taskIdentifier);
    expect(arguments['taskName'], BackgroundSyncManager.taskName);
    expect(arguments['networkType'], 'connected');
    expect(arguments['existingWorkPolicy'], 'replace');
    expect(arguments['initialDelaySeconds'], 3600);
  });

  test('scheduleNextSync returns false when scheduling fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'bgTaskSchedulingFailed',
            message: 'Unrecognized Identifier',
          );
        });

    final scheduled = await BackgroundSyncManager.scheduleNextSync();

    expect(scheduled, isFalse);
  });
}
