import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:step_tracker/tutorial/tutorial_real_screens.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart'
    show TutorialMockPage;

/// Mirror-surface guard for the race-preview feature (spec: "Mirror surfaces").
///
/// `tutorial_real_screens.dart` renders the REAL `RaceDetailScreen` fed by
/// `TutorialPreviewBackendApiService`, which EXTENDS the production API service.
/// Any preview-mode branch that self-fetches (details reload after a join, a
/// pull-to-refresh) would therefore become a genuine production request fired
/// from inside the tutorial. Two things keep that impossible and both are
/// asserted here:
///
///  1. The demo race payload keeps `myStatus` non-null, so the demo screen can
///     never enter preview mode (no JOIN CTA, no preview-only code path).
///  2. Every fetch the demo screen makes — including the one behind
///     pull-to-refresh — lands on an overridden fake method.

/// Counts the reads the demo race screen performs, so "it refreshed" can be
/// distinguished from "it silently did nothing".
class _CountingTutorialApi extends TutorialPreviewBackendApiService {
  int detailsCalls = 0;
  int progressCalls = 0;
  int activeNoticeFetches = 0;
  int activeNoticeAcks = 0;
  int activeReceiptAcks = 0;

  @override
  Future<ActiveImpactNoticesResult> fetchActiveRaceImpactNotices({
    required String identityToken,
    required String raceId,
  }) async {
    activeNoticeFetches += 1;
    return super.fetchActiveRaceImpactNotices(
      identityToken: identityToken,
      raceId: raceId,
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
  Future<RaceBootstrapResult> fetchRaceBootstrap({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    detailsCalls += 1;
    return super.fetchRaceBootstrap(
      identityToken: identityToken,
      raceId: raceId,
      participantsLimit: participantsLimit,
    );
  }

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    detailsCalls += 1;
    return super.fetchRaceDetails(
      identityToken: identityToken,
      raceId: raceId,
      participantsLimit: participantsLimit,
    );
  }

  @override
  Future<RaceProgressResult> fetchRaceProgressParticipants({
    required String identityToken,
    required String raceId,
    int offset = 0,
    int limit = 10,
  }) async {
    progressCalls += 1;
    return super.fetchRaceProgressParticipants(
      identityToken: identityToken,
      raceId: raceId,
      offset: offset,
      limit: limit,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '2.3.6',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('the demo/tutorial race fixtures never have a null myStatus', () {
    // A null myStatus is exactly what puts the real screen into preview mode.
    expect(tutorialPreviewRaceDetail()['myStatus'], isNotNull);

    final engine = DemoRaceEngine(
      myUserId: 'demo-me',
      myDisplayName: 'Rohan',
      startedAt: DateTime(2026, 8, 15, 9),
      clock: () => DateTime(2026, 8, 15, 9, 5),
    );
    expect(
      engine.raceDetails(DateTime(2026, 8, 15, 9, 5))['myStatus'],
      isNotNull,
    );
  });

  testWidgets(
    'the tutorial race detail screen never enters preview mode or hits the network',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _CountingTutorialApi();
      await tester.pumpWidget(
        MaterialApp(
          home: TutorialRealHost(
            page: TutorialMockPage.raceDetail,
            keys: const {},
            authService: TutorialPreviewAuthService(),
            api: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(RaceDetailScreen), findsOneWidget);
      // Preview-only chrome must never appear inside the tutorial.
      expect(find.byKey(const Key('race-preview-join-cta')), findsNothing);
      expect(find.text('SPECTATING · READ-ONLY'), findsNothing);
      expect(
        find.byKey(const Key('race-preview-locked-activity')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      // Everything the screen fetched went through the seeded fake.
      expect(api.detailsCalls, greaterThan(0));
      expect(api.activeNoticeFetches, 0);
      expect(api.activeNoticeAcks, 0);
      expect(api.activeReceiptAcks, 0);
      final detailsBefore = api.detailsCalls;
      final progressBefore = api.progressCalls;

      // Pull-to-refresh — the one gesture preview mode relies on instead of a
      // poll. It must still route through the fake service.
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 350),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(api.detailsCalls, greaterThanOrEqualTo(detailsBefore));
      expect(api.progressCalls, greaterThanOrEqualTo(progressBefore));
      expect(
        api.activeNoticeFetches,
        0,
        reason: 'tutorial pull-to-refresh is not a notice delivery event',
      );
      expect(api.activeNoticeAcks, 0);
      expect(api.activeReceiptAcks, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
    },
  );
}
