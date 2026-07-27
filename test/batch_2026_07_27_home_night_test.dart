import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

/// Batch 2026-07-27.
///
/// Item 11 — the race-row eyebrow (INVITE / ACTIVE / LIVE / FINISHED / PUBLIC /
/// OPEN) was painted with `roofMid`, a surface green. At night that is #214637
/// on a #1B2A34 parchment card: ~1.2:1, i.e. invisible. It must use a real text
/// token that clears AA on both palettes.
///
/// Item 20 — the home section headers carried a full-width `feltLine`
/// (12%-alpha white) top border, a leftover from the felt-table look. It reads
/// as a faint white rule under the block above it, in both light and night.
class _FakeApi extends BackendApiService {}

/// The exact colour `AppColors.feltLine` used to be. Asserted by value (not by
/// token) so the guard survives the token's deletion.
const _feltLine = Color(0x1FFFFFFF);

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Map<String, dynamic> _inviteCard() => {
  'state': 'PENDING_INVITE',
  'data': {
    'raceId': 'race-1',
    'inviter': {'userId': 'u2', 'displayName': 'Sneaky Pete'},
    'participantCount': 4,
    'durationHours': 24,
  },
};

Future<void> _pumpHome(WidgetTester tester, {required ThemeData theme}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: HomeTab(
          key: UniqueKey(),
          stepData: StepData(steps: 2400, date: DateTime(2026, 7, 27)),
          isLoading: false,
          error: null,
          healthAuthorized: true,
          notificationsState: true,
          displayName: 'Trail Walker',
          authService: auth,
          backendApiService: _FakeApi(),
          onRefresh: () async {},
          onEnableHealth: () {},
          onEnableNotifications: () {},
          onDisplayNameChanged: () {},
          friendsSteps: const [],
          raceCard: _inviteCard(),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Every `Border` painted anywhere in the pumped tree, from both `Container`
/// (via its `decoration`) and bare `DecoratedBox`.
Iterable<BoxDecoration> _decorations(WidgetTester tester) sync* {
  for (final d in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
    final dec = d.decoration;
    if (dec is BoxDecoration) yield dec;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The home tab's PixelText styles are google_fonts; a runtime fetch that
    // outlives the test zone crashes the whole suite. Tests render with the
    // fallback face instead.
    GoogleFonts.config.allowRuntimeFetching = false;
    // PackageInfo.fromPlatform() never resolves inside testWidgets' fake-async
    // zone; the activation-analytics writes on the home tab hang without this.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.steptracker',
      version: '2.0.1',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('item 11 — the race-row eyebrow is legible at night', () {
    testWidgets('night: INVITE is not painted with the invisible roofMid', (
      tester,
    ) async {
      await _pumpHome(tester, theme: AppThemeData.night());
      await tester.dragUntilVisible(
        find.text('INVITE'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pump();

      final label = tester.widget<Text>(find.text('INVITE'));
      expect(label.style?.color, isNot(AppPalette.night.roofMid));
      expect(label.style?.color, AppPalette.night.successText);
    });

    testWidgets('day: the eyebrow keeps its green, unchanged', (tester) async {
      await _pumpHome(tester, theme: AppThemeData.light());
      await tester.dragUntilVisible(
        find.text('INVITE'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pump();

      final label = tester.widget<Text>(find.text('INVITE'));
      // successText maps to roofMid in the day palette, so day is pixel-identical.
      expect(label.style?.color, AppPalette.light.roofMid);
    });

    test('the chosen token clears AA on a night parchment card', () {
      expect(
        _contrast(AppPalette.night.successText, AppPalette.night.parchment),
        greaterThanOrEqualTo(4.5),
      );
      // And the token it replaces does not — this is the bug being fixed.
      expect(
        _contrast(AppPalette.night.roofMid, AppPalette.night.parchment),
        lessThan(4.5),
      );
    });
  });

  group('item 20 — no faint white rule above the home section headers', () {
    // NOTE: build the ThemeData inside the test body. AppThemeData calls
    // GoogleFonts at construction; doing it in the group body starts a font
    // fetch outside any test zone and takes the whole suite down.
    for (final night in [false, true]) {
      final name = night ? 'night' : 'day';
      testWidgets('$name: nothing paints a feltLine border', (tester) async {
        await _pumpHome(
          tester,
          theme: night ? AppThemeData.night() : AppThemeData.light(),
        );
        await tester.dragUntilVisible(
          find.text('RACES'),
          find.byType(Scrollable).first,
          const Offset(0, -200),
        );
        await tester.pump();

        for (final dec in _decorations(tester)) {
          final border = dec.border;
          if (border == null) continue;
          if (border is Border) {
            for (final side in [
              border.top,
              border.bottom,
              border.left,
              border.right,
            ]) {
              expect(
                side.color,
                isNot(_feltLine),
                reason: 'a feltLine rule is still painted on the home tab',
              );
            }
          }
        }
      });
    }

    testWidgets('the RACES header keeps its padding after the rule is gone', (
      tester,
    ) async {
      await _pumpHome(tester, theme: AppThemeData.light());
      await tester.dragUntilVisible(
        find.text('RACES'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pump();

      final paddings = tester
          .widgetList<Padding>(
            find.ancestor(
              of: find.text('RACES'),
              matching: find.byType(Padding),
            ),
          )
          .map((p) => p.padding)
          .toList();
      expect(paddings, contains(const EdgeInsets.fromLTRB(16, 16, 16, 9)));
    });

    testWidgets('the SETUP header keeps its padding too', (tester) async {
      await _pumpHome(tester, theme: AppThemeData.light());
      await tester.dragUntilVisible(
        find.text('SETUP'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pump();

      final paddings = tester
          .widgetList<Padding>(
            find.ancestor(
              of: find.text('SETUP'),
              matching: find.byType(Padding),
            ),
          )
          .map((p) => p.padding)
          .toList();
      expect(paddings, contains(const EdgeInsets.fromLTRB(16, 16, 16, 9)));
    });
  });
}
