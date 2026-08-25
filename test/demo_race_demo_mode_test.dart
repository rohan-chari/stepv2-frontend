import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/demo/demo_auth_service.dart';
import 'package:step_tracker/demo/demo_race_api_service.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/notification_service.dart';
import 'package:step_tracker/widgets/ad_banner_slot.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/race_alert_opt_in_card.dart';

import 'support/demo_race_harness.dart';

/// Spec §10 items 15, 16, 16a, 16f and 16g — the side effects the real screen
/// is capable of firing, asserted against the REAL screen in `demoMode`.

class _CountingNotificationService extends NotificationService {
  int permissionRequests = 0;
  int permissionStateReads = 0;

  @override
  Future<bool> requestPermission(String? authToken) async {
    permissionRequests += 1;
    return true;
  }

  @override
  Future<bool?> getPermissionState() async {
    permissionStateReads += 1;
    // Undetermined — a brand-new user's state, which is exactly what makes the
    // opt-in card render on a non-demo screen.
    return null;
  }
}

class _StarterRewardSpyApi extends DemoRaceApiService {
  _StarterRewardSpyApi(super.engine);

  int starterFetches = 0;
  int starterClaims = 0;
  int discards = 0;
  int batchOpens = 0;
  int activeNoticeFetches = 0;
  int activeNoticeAcks = 0;
  int activeReceiptAcks = 0;

  @override
  Future<ActiveImpactNoticesResult> fetchActiveRaceImpactNotices({
    required String identityToken,
    required String raceId,
    DateTime? resolvedAfter,
  }) async {
    activeNoticeFetches += 1;
    return super.fetchActiveRaceImpactNotices(
      identityToken: identityToken,
      raceId: raceId,
      resolvedAfter: resolvedAfter,
    );
  }

  @override
  Future<bool> acknowledgeActiveRaceImpactNotice({
    required String identityToken,
    required String raceId,
    required String noticeId,
  }) async {
    activeNoticeAcks += 1;
    return super.acknowledgeActiveRaceImpactNotice(
      identityToken: identityToken,
      raceId: raceId,
      noticeId: noticeId,
    );
  }

  @override
  Future<bool> acknowledgeActiveImpactReceipt({
    required String identityToken,
    required String raceId,
    required String receiptId,
  }) async {
    activeReceiptAcks += 1;
    return super.acknowledgeActiveImpactReceipt(
      identityToken: identityToken,
      raceId: raceId,
      receiptId: receiptId,
    );
  }

  @override
  Future<Map<String, dynamic>> fetchStarterReward({
    required String identityToken,
  }) async {
    starterFetches += 1;
    return super.fetchStarterReward(identityToken: identityToken);
  }

  @override
  Future<Map<String, dynamic>> claimStarterReward({
    required String identityToken,
  }) async {
    starterClaims += 1;
    return super.claimStarterReward(identityToken: identityToken);
  }

  @override
  Future<Map<String, dynamic>> discardPowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async {
    discards += 1;
    return super.discardPowerup(
      identityToken: identityToken,
      raceId: raceId,
      powerupId: powerupId,
    );
  }

  @override
  Future<Map<String, dynamic>> openMysteryBoxBatch({
    required String identityToken,
    required String raceId,
    required List<String> powerupIds,
    bool includeQueued = true,
    int maxCount = 20,
  }) async {
    batchOpens += 1;
    return super.openMysteryBoxBatch(
      identityToken: identityToken,
      raceId: raceId,
      powerupIds: powerupIds,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<
    ({
      DemoRaceEngine engine,
      _StarterRewardSpyApi api,
      _CountingNotificationService notifications,
      AuthService real,
    })
  >
  pumpDemoScreen(WidgetTester tester, {bool demoMode = true}) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final real = seededRealAuthService();
    final engine = DemoRaceEngine(
      myUserId: real.userId!,
      myDisplayName: real.displayName!,
    )..skipPrologue();
    final api = _StarterRewardSpyApi(engine);
    final notifications = _CountingNotificationService();

    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: DemoAuthService(real),
          raceId: DemoRaceEngine.raceId,
          backendApiService: api,
          notificationService: notifications,
          demoMode: demoMode,
        ),
      ),
    );
    await settleDemo(tester);
    return (engine: engine, api: api, notifications: notifications, real: real);
  }

  testWidgets('15 — no AdBannerSlot renders an ad in demoMode', (tester) async {
    await pumpDemoScreen(tester);

    final slots = tester.widgetList<AdBannerSlot>(find.byType(AdBannerSlot));
    expect(slots, isNotEmpty, reason: 'the slot is still in the tree');
    expect(
      slots.every((s) => s.hidden),
      isTrue,
      reason: 'every banner slot on the demo screen must be hidden',
    );
  });

  testWidgets('16 — the starter reward is never fetched or claimed', (
    tester,
  ) async {
    final ctx = await pumpDemoScreen(tester);
    expect(ctx.api.starterFetches, 0);
    expect(ctx.api.starterClaims, 0);
  });

  testWidgets('16b — active-impact APIs stay offline in demoMode', (
    tester,
  ) async {
    final ctx = await pumpDemoScreen(tester);
    expect(ctx.api.activeNoticeFetches, 0);
    expect(ctx.api.activeNoticeAcks, 0);
    expect(ctx.api.activeReceiptAcks, 0);
  });

  testWidgets(
    '16a — RaceAlertOptInCard never renders and no OS prompt fires (G3)',
    (tester) async {
      final ctx = await pumpDemoScreen(tester);

      expect(find.byType(RaceAlertOptInCard), findsNothing);
      expect(ctx.notifications.permissionRequests, 0);
      expect(
        ctx.notifications.permissionStateReads,
        0,
        reason: 'demoMode must not even ask the OS for the permission state',
      );
    },
  );

  testWidgets('16f — the case-opening reel hides its ad slots too (G8)', (
    tester,
  ) async {
    await pumpDemoScreen(tester);

    // Tap the first mystery box: the real CaseOpeningScreen is pushed.
    final boxes = find.byWidgetPredicate(
      (w) => w is ItemSlot && w.state == ItemSlotState.mysteryBox,
    );
    expect(boxes, findsNWidgets(3));
    await tester.tap(boxes.first);
    await settleDemo(tester);

    expect(find.byType(CaseOpeningScreen), findsOneWidget);
    final slots = tester.widgetList<AdBannerSlot>(find.byType(AdBannerSlot));
    expect(
      slots.every((s) => s.hidden),
      isTrue,
      reason: 'the reel renders two of its own banner slots',
    );
  });

  testWidgets('16g — discard, upgrade ladders and OPEN ALL are disabled', (
    tester,
  ) async {
    final ctx = await pumpDemoScreen(tester);

    // OPEN ALL: three boxes are openable, which is exactly when the real screen
    // shows the button. It must be absent in demoMode.
    expect(find.text('OPEN ALL'), findsNothing);
    expect(ctx.api.batchOpens, 0);

    // Nothing is pre-owned any more, so roll the boxes through the engine to
    // reach the state this test is about: a held, upgradeable Shortcut.
    for (final id in DemoRaceEngine.mysteryBoxIds) {
      ctx.engine.openBox(id);
      ctx.engine.commitBoxOpen(id);
    }
    await settleDemo(tester, frames: 20);

    // Open the powerup sheet on the held Shortcut.
    final held = find.byWidgetPredicate(
      (w) =>
          w is ItemSlot &&
          w.state == ItemSlotState.held &&
          w.powerupType == 'SHORTCUT',
    );
    expect(held, findsOneWidget);
    await tester.tap(held);
    await settleDemo(tester);

    expect(find.text('USE'), findsOneWidget);
    expect(
      find.text('DISCARD'),
      findsNothing,
      reason: 'discarding the boost would dead-end the script (§5.7b)',
    );
    // SHORTCUT is upgradeable, so the real sheet would render a tier ladder.
    expect(
      find.textContaining('Steal up to 1,500 steps'),
      findsNothing,
      reason: 'upgrade ladders cost coins and are disabled in demoMode',
    );
    expect(ctx.api.discards, 0);
  });

  testWidgets('demoMode does NOT change how standings or powerups render', (
    tester,
  ) async {
    final ctx = await pumpDemoScreen(tester);

    // The real standings, from the real screen, with the real user's name and
    // the real "(you)" self-marker the plank renders.
    expect(find.textContaining('${ctx.real.displayName!} (you)'), findsWidgets);
    expect(find.textContaining('CapyBot'), findsWidgets);
    // Three real inventory slots: one held + two boxes.
    expect(find.byType(ItemSlot), findsNWidgets(3));
  });
}
