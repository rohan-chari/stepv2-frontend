import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

/// Batch 2026-08-09 item 10 moved the icon gallery and the toast harness into
/// the hub's DEBUG section, which ships collapsed. Opening it is the only
/// change here — every assertion below is the one that already shipped.
Future<void> _openDebug(WidgetTester tester) async {
  final header = find.byKey(const Key('admin-section-header-DEBUG'));
  await tester.ensureVisible(header);
  await tester.pump();
  await tester.tap(header);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('admin powerup icon list includes newer powerups', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AdminScreen(authService: AuthService())),
    );
    await _openDebug(tester);

    expect(find.text('Cleanse'), findsOneWidget);
    expect(find.text('Imposter'), findsOneWidget);
    expect(find.text('Rainstorm'), findsOneWidget);
    expect(find.text('Lucky Horseshoe'), findsOneWidget);
    expect(find.text('Sneaky Swap'), findsOneWidget);
    expect(find.text('Mirror'), findsOneWidget);

    // One row per type PowerupIcon can render — keeps the admin list from
    // drifting out of sync when new powerups are added.
    expect(find.byType(PowerupIcon), findsNWidgets(PowerupIcon.knownTypeCount));
  });

  testWidgets('admin toast test buttons show shared toasts', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AdminScreen(authService: AuthService())),
    );
    await _openDebug(tester);

    await tester.ensureVisible(find.text('TEST INFO TOAST'));
    await tester.pump();
    await tester.tap(find.text('TEST INFO TOAST'));
    await tester.pump();

    expect(find.byKey(const Key('info-toast-shell')), findsOneWidget);
    expect(find.text('This is a test notification toast.'), findsOneWidget);

    await tester.ensureVisible(find.text('TEST ERROR TOAST'));
    await tester.pump();
    await tester.tap(find.text('TEST ERROR TOAST'));
    await tester.pump();

    expect(find.byKey(const Key('error-toast-shell')), findsOneWidget);
    expect(find.text('This is a test error toast.'), findsOneWidget);
  });
}
