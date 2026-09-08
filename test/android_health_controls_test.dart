import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/widgets/android_health_controls.dart';
import 'package:step_tracker/widgets/onboarding_permission_gate.dart';

class _Health extends Health {
  bool? permission = true;
  bool available = true;
  bool background = false;
  bool deny = false;
  int requests = 0;
  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async => permission;
  @override
  Future<bool> isHealthDataInBackgroundAvailable() async => available;
  @override
  Future<bool> isHealthDataInBackgroundAuthorized() async => background;
  @override
  Future<bool> requestHealthDataInBackgroundAuthorization() async {
    requests++;
    return background = !deny;
  }
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'health_authorized': true}),
  );
  testWidgets(
    'Android onboarding help and escape fit a compact large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var helped = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: OnboardingPermissionGate(
            label: 'CONNECT STEPS',
            headline: 'Every step counts',
            body: 'Connect your steps to join races.',
            icon: Icons.directions_walk,
            onContinue: () {},
            onEscape: () {},
            onHelp: () {
              helped = true;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('USING GOOGLE FIT?'));
      await tester.tap(find.text('USING GOOGLE FIT?'));
      await tester.pump();
      expect(helped, isTrue);
      expect(find.text('CONTINUE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'denied background and failed settings remain actionable at large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final native = _Health()..deny = true;
      const channel = MethodChannel('com.steptracker/settings');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => false,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AndroidHealthControls(
                healthService: HealthService(
                  health: native,
                  isAndroidForTesting: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALLOW BACKGROUND STEPS'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Background access is optional.'),
        findsOneWidget,
      );
      expect(native.requests, 1);
      await tester.tap(find.text('CONNECT GOOGLE FIT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OPEN HEALTH CONNECT'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Couldn’t open settings.'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background permission is explicit and provider help remains available',
    (tester) async {
      final native = _Health();
      final health = HealthService(health: native, isAndroidForTesting: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AndroidHealthControls(healthService: health)),
        ),
      );
      await tester.pumpAndSettle();
      expect(native.requests, 0);
      expect(find.text('CONNECT GOOGLE FIT'), findsOneWidget);
      await tester.tap(find.text('ALLOW BACKGROUND STEPS'));
      await tester.pumpAndSettle();
      expect(native.requests, 1);
      expect(find.text('Background steps connected'), findsOneWidget);
      await tester.tap(find.text('CONNECT GOOGLE FIT'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Sync Fit with Health Connect'),
        findsOneWidget,
      );
    },
  );
  testWidgets('unsupported background access preserves provider help', (
    tester,
  ) async {
    final native = _Health()..available = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AndroidHealthControls(
            healthService: HealthService(
              health: native,
              isAndroidForTesting: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ALLOW BACKGROUND STEPS'), findsNothing);
    expect(
      find.textContaining('Open Bara to update your steps'),
      findsOneWidget,
    );
    expect(find.text('CONNECT GOOGLE FIT'), findsOneWidget);
    expect(native.requests, 0);
  });
  testWidgets('health recovery invokes an actual native settings method', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('com.steptracker/settings');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AndroidHealthControls(
            healthService: HealthService(
              health: _Health(),
              isAndroidForTesting: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONNECT GOOGLE FIT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OPEN HEALTH CONNECT'));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['openHealthSettings']);
  });
}
